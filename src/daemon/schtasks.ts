import fs from "node:fs/promises";
import path from "node:path";
import type { GatewayServiceRuntime } from "./service-runtime.js";
import type {
  GatewayServiceCommandConfig,
  GatewayServiceControlArgs,
  GatewayServiceEnv,
  GatewayServiceEnvArgs,
  GatewayServiceInstallArgs,
  GatewayServiceManageArgs,
} from "./service-types.js";
import { parseCmdScriptCommandLine } from "./cmd-argv.js";
import { assertNoCmdLineBreak, parseCmdSetAssignment } from "./cmd-set.js";
import { resolveGatewayWindowsTaskName } from "./constants.js";
import { formatLine, writeFormattedLines } from "./output.js";
import { resolveGatewayStateDir } from "./paths.js";
import { parseKeyValueOutput } from "./runtime-parse.js";
import { execSchtasks } from "./schtasks-exec.js";
import { buildWatchdogScript, resolveWatchdogScriptPath } from "./watchdog.js";

function resolveTaskName(env: GatewayServiceEnv): string {
  const override = env.OPENCLAW_WINDOWS_TASK_NAME?.trim();
  if (override) {
    return override;
  }
  return resolveGatewayWindowsTaskName(env.OPENCLAW_PROFILE);
}

export function resolveTaskScriptPath(env: GatewayServiceEnv): string {
  const override = env.OPENCLAW_TASK_SCRIPT?.trim();
  if (override) {
    return override;
  }
  const scriptName = env.OPENCLAW_TASK_SCRIPT_NAME?.trim() || "gateway.cmd";
  const stateDir = resolveGatewayStateDir(env);
  return path.join(stateDir, scriptName);
}

// `/TR` is parsed by schtasks itself, while the generated `gateway.cmd` line is parsed by cmd.exe.
// Keep their quoting strategies separate so each parser gets the encoding it expects.
function quoteSchtasksArg(value: string): string {
  if (!/[ \t"]/g.test(value)) {
    return value;
  }
  return `"${value.replace(/"/g, '\\"')}"`;
}

/**
 * Build schtasks arguments for watchdog-style task with repeat interval.
 * This creates a task that runs every 1 minute.
 * Note: /RI requires /SC MINUTE, cannot use ONLOGON with repeat interval.
 */
export function buildWatchdogTaskArgs(params: {
  taskName: string;
  scriptPath: string;
  taskUser?: string | null;
}): string[] {
  const { taskName, scriptPath, taskUser } = params;
  const quotedScript = quoteSchtasksArg(scriptPath);

  // Use MINUTE schedule with /MO 1 for every 1 minute
  // This ensures gateway is restarted within 1 minute if it crashes
  const baseArgs = [
    "/Create",
    "/F",
    "/SC",
    "MINUTE",
    "/MO",
    "1", // Every 1 minute
    "/RL",
    "LIMITED",
    "/TN",
    taskName,
    "/TR",
    quotedScript,
  ];

  if (taskUser) {
    return [...baseArgs, "/RU", taskUser, "/NP", "/IT"];
  }

  return baseArgs;
}

function resolveTaskUser(env: GatewayServiceEnv): string | null {
  const username = env.USERNAME || env.USER || env.LOGNAME;
  if (!username) {
    return null;
  }
  if (username.includes("\\")) {
    return username;
  }
  const domain = env.USERDOMAIN;
  if (domain) {
    return `${domain}\\${username}`;
  }
  return username;
}

export async function readScheduledTaskCommand(
  env: GatewayServiceEnv,
): Promise<GatewayServiceCommandConfig | null> {
  // Try watchdog script path first, then fall back to legacy script path
  const watchdogPath = resolveWatchdogScriptPath(env);
  const legacyPath = resolveTaskScriptPath(env);

  const scriptPaths = [watchdogPath, legacyPath].filter(
    (path, index, arr) => arr.indexOf(path) === index,
  );

  for (const scriptPath of scriptPaths) {
    try {
      const content = await fs.readFile(scriptPath, "utf8");
      let workingDirectory = "";
      let commandLine = "";
      const environment: Record<string, string> = {};
      for (const rawLine of content.split(/\r?\n/)) {
        const line = rawLine.trim();
        if (!line) {
          continue;
        }
        const lower = line.toLowerCase();
        if (line.startsWith("@echo")) {
          continue;
        }
        if (lower.startsWith("rem ")) {
          continue;
        }
        if (lower.startsWith("set ")) {
          const assignment = parseCmdSetAssignment(line.slice(4));
          if (assignment) {
            environment[assignment.key] = assignment.value;
          }
          continue;
        }
        if (lower.startsWith("cd /d ")) {
          workingDirectory = line.slice("cd /d ".length).trim().replace(/^"|"$/g, "");
          continue;
        }
        // Skip netstat check lines in watchdog script
        if (lower.startsWith("netstat ") || lower.startsWith("if %errorlevel%")) {
          continue;
        }
        if (lower === ")" || lower.startsWith("exit /b")) {
          continue;
        }
        // Parse start command: start /b "" <actual command>
        if (lower.startsWith("start /b")) {
          const startMatch = line.match(/^start\s+\/b\s+""\s+(.+)$/i);
          if (startMatch) {
            commandLine = startMatch[1];
            break;
          }
        } else {
          commandLine = line;
          break;
        }
      }
      if (!commandLine) {
        continue; // Try next script path
      }
      return {
        programArguments: parseCmdScriptCommandLine(commandLine),
        ...(workingDirectory ? { workingDirectory } : {}),
        ...(Object.keys(environment).length > 0 ? { environment } : {}),
      };
    } catch {
      continue; // Try next script path
    }
  }
  return null;
}

export type ScheduledTaskInfo = {
  status?: string;
  lastRunTime?: string;
  lastRunResult?: string;
};

export function parseSchtasksQuery(output: string): ScheduledTaskInfo {
  const entries = parseKeyValueOutput(output, ":");
  const info: ScheduledTaskInfo = {};
  const status = entries.status;
  if (status) {
    info.status = status;
  }
  const lastRunTime = entries["last run time"];
  if (lastRunTime) {
    info.lastRunTime = lastRunTime;
  }
  const lastRunResult = entries["last run result"];
  if (lastRunResult) {
    info.lastRunResult = lastRunResult;
  }
  return info;
}

async function assertSchtasksAvailable() {
  const res = await execSchtasks(["/Query"]);
  if (res.code === 0) {
    return;
  }
  const detail = res.stderr || res.stdout;
  throw new Error(`schtasks unavailable: ${detail || "unknown error"}`.trim());
}

export async function installScheduledTask({
  env,
  stdout,
  programArguments,
  workingDirectory,
  environment,
  description,
}: GatewayServiceInstallArgs): Promise<{ scriptPath: string }> {
  await assertSchtasksAvailable();

  // Validate description does not contain line breaks
  if (description) {
    assertNoCmdLineBreak(description, "Task description");
  }

  // Use watchdog script instead of direct gateway script
  const watchdogScriptPath = resolveWatchdogScriptPath(env);
  await fs.mkdir(path.dirname(watchdogScriptPath), { recursive: true });

  // Build watchdog script that checks port before starting
  const watchdogScript = buildWatchdogScript({
    programArguments,
    workingDirectory,
    environment,
  });
  await fs.writeFile(watchdogScriptPath, watchdogScript, "utf8");

  const taskName = resolveTaskName(env);
  const taskUser = resolveTaskUser(env);

  // Use watchdog task args with repeat interval
  const baseArgs = buildWatchdogTaskArgs({
    taskName,
    scriptPath: watchdogScriptPath,
    taskUser,
  });

  let create = await execSchtasks(baseArgs);
  if (create.code !== 0 && taskUser) {
    // Retry without user specification
    const fallbackArgs = buildWatchdogTaskArgs({
      taskName,
      scriptPath: watchdogScriptPath,
      taskUser: null,
    });
    create = await execSchtasks(fallbackArgs);
  }

  if (create.code !== 0) {
    const detail = create.stderr || create.stdout;
    const hint = /access is denied/i.test(detail)
      ? " Run PowerShell as Administrator or rerun without installing the daemon."
      : "";
    throw new Error(`schtasks create failed: ${detail}${hint}`.trim());
  }

  // Run the task immediately
  await execSchtasks(["/Run", "/TN", taskName]);

  // Ensure we don't end up writing to a clack spinner line (wizards show progress without a newline).
  writeFormattedLines(
    stdout,
    [
      { label: "Installed Scheduled Task", value: taskName },
      { label: "Task script", value: watchdogScriptPath },
      { label: "Repeat interval", value: "1 minute" },
    ],
    { leadingBlankLine: true },
  );
  return { scriptPath: watchdogScriptPath };
}

export async function uninstallScheduledTask({
  env,
  stdout,
}: GatewayServiceManageArgs): Promise<void> {
  await assertSchtasksAvailable();
  const taskName = resolveTaskName(env);
  await execSchtasks(["/Delete", "/F", "/TN", taskName]);

  // Remove watchdog script
  const watchdogScriptPath = resolveWatchdogScriptPath(env);
  try {
    await fs.unlink(watchdogScriptPath);
    stdout.write(`${formatLine("Removed task script", watchdogScriptPath)}\n`);
  } catch {
    stdout.write(`Task script not found at ${watchdogScriptPath}\n`);
  }

  // Also try to remove old gateway.cmd if it exists
  const oldScriptPath = resolveTaskScriptPath(env);
  if (oldScriptPath !== watchdogScriptPath) {
    try {
      await fs.unlink(oldScriptPath);
      stdout.write(`${formatLine("Removed legacy script", oldScriptPath)}\n`);
    } catch {
      // Ignore
    }
  }
}

function isTaskNotRunning(res: { stdout: string; stderr: string; code: number }): boolean {
  const detail = (res.stderr || res.stdout).toLowerCase();
  return detail.includes("not running");
}

export async function stopScheduledTask({ stdout, env }: GatewayServiceControlArgs): Promise<void> {
  await assertSchtasksAvailable();
  const taskName = resolveTaskName(env ?? (process.env as GatewayServiceEnv));
  const res = await execSchtasks(["/End", "/TN", taskName]);
  if (res.code !== 0 && !isTaskNotRunning(res)) {
    throw new Error(`schtasks end failed: ${res.stderr || res.stdout}`.trim());
  }
  stdout.write(`${formatLine("Stopped Scheduled Task", taskName)}\n`);
}

export async function restartScheduledTask({
  stdout,
  env,
}: GatewayServiceControlArgs): Promise<void> {
  await assertSchtasksAvailable();
  const taskName = resolveTaskName(env ?? (process.env as GatewayServiceEnv));
  await execSchtasks(["/End", "/TN", taskName]);
  const res = await execSchtasks(["/Run", "/TN", taskName]);
  if (res.code !== 0) {
    throw new Error(`schtasks run failed: ${res.stderr || res.stdout}`.trim());
  }
  stdout.write(`${formatLine("Restarted Scheduled Task", taskName)}\n`);
}

export async function isScheduledTaskInstalled(args: GatewayServiceEnvArgs): Promise<boolean> {
  await assertSchtasksAvailable();
  const taskName = resolveTaskName(args.env ?? (process.env as GatewayServiceEnv));
  const res = await execSchtasks(["/Query", "/TN", taskName]);
  return res.code === 0;
}

export async function readScheduledTaskRuntime(
  env: GatewayServiceEnv = process.env as GatewayServiceEnv,
): Promise<GatewayServiceRuntime> {
  try {
    await assertSchtasksAvailable();
  } catch (err) {
    return {
      status: "unknown",
      detail: String(err),
    };
  }
  const taskName = resolveTaskName(env);
  const res = await execSchtasks(["/Query", "/TN", taskName, "/V", "/FO", "LIST"]);
  if (res.code !== 0) {
    const detail = (res.stderr || res.stdout).trim();
    const missing = detail.toLowerCase().includes("cannot find the file");
    return {
      status: missing ? "stopped" : "unknown",
      detail: detail || undefined,
      missingUnit: missing,
    };
  }
  const parsed = parseSchtasksQuery(res.stdout || "");
  const statusRaw = parsed.status?.toLowerCase();
  const status = statusRaw === "running" ? "running" : statusRaw ? "stopped" : "unknown";
  return {
    status,
    state: parsed.status,
    lastRunTime: parsed.lastRunTime,
    lastRunResult: parsed.lastRunResult,
  };
}
