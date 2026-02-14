import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import type { GatewayServiceRuntime } from "./service-runtime.js";
import { colorize, isRich, theme } from "../terminal/theme.js";
import { resolveGatewayWindowsTaskName } from "./constants.js";
import { resolveGatewayStateDir } from "./paths.js";
import { parseKeyValueOutput } from "./runtime-parse.js";
import { buildWatchdogScript, resolveWatchdogScriptPath } from "./watchdog.js";

const execFileAsync = promisify(execFile);

const formatLine = (label: string, value: string) => {
  const rich = isRich();
  return `${colorize(rich, theme.muted, `${label}:`)} ${colorize(rich, theme.command, value)}`;
};

function resolveTaskName(env: Record<string, string | undefined>): string {
  const override = env.OPENCLAW_WINDOWS_TASK_NAME?.trim();
  if (override) {
    return override;
  }
  return resolveGatewayWindowsTaskName(env.OPENCLAW_PROFILE);
}

export function resolveTaskScriptPath(env: Record<string, string | undefined>): string {
  const override = env.OPENCLAW_TASK_SCRIPT?.trim();
  if (override) {
    return override;
  }
  const scriptName = env.OPENCLAW_TASK_SCRIPT_NAME?.trim() || "gateway.cmd";
  const stateDir = resolveGatewayStateDir(env);
  return path.join(stateDir, scriptName);
}

function quoteCmdArg(value: string): string {
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
  const quotedScript = quoteCmdArg(scriptPath);

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

function resolveTaskUser(env: Record<string, string | undefined>): string | null {
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

function parseCommandLine(value: string): string[] {
  const args: string[] = [];
  let current = "";
  let inQuotes = false;

  for (let i = 0; i < value.length; i++) {
    const char = value[i];
    // `buildTaskScript` only escapes quotes (`\"`).
    // Keep all other backslashes literal so drive and UNC paths are preserved.
    if (char === "\\" && i + 1 < value.length && value[i + 1] === '"') {
      current += value[i + 1];
      i++;
      continue;
    }
    if (char === '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (!inQuotes && /\s/.test(char)) {
      if (current) {
        args.push(current);
        current = "";
      }
      continue;
    }
    current += char;
  }
  if (current) {
    args.push(current);
  }
  return args;
}

export async function readScheduledTaskCommand(env: Record<string, string | undefined>): Promise<{
  programArguments: string[];
  workingDirectory?: string;
  environment?: Record<string, string>;
} | null> {
  const scriptPath = resolveTaskScriptPath(env);
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
      if (line.startsWith("@echo")) {
        continue;
      }
      if (line.toLowerCase().startsWith("rem ")) {
        continue;
      }
      if (line.toLowerCase().startsWith("set ")) {
        const assignment = line.slice(4).trim();
        const index = assignment.indexOf("=");
        if (index > 0) {
          const key = assignment.slice(0, index).trim();
          const value = assignment.slice(index + 1).trim();
          if (key) {
            environment[key] = value;
          }
        }
        continue;
      }
      if (line.toLowerCase().startsWith("cd /d ")) {
        workingDirectory = line.slice("cd /d ".length).trim().replace(/^"|"$/g, "");
        continue;
      }
      commandLine = line;
      break;
    }
    if (!commandLine) {
      return null;
    }
    return {
      programArguments: parseCommandLine(commandLine),
      ...(workingDirectory ? { workingDirectory } : {}),
      ...(Object.keys(environment).length > 0 ? { environment } : {}),
    };
  } catch {
    return null;
  }
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

async function execSchtasks(
  args: string[],
): Promise<{ stdout: string; stderr: string; code: number }> {
  try {
    const { stdout, stderr } = await execFileAsync("schtasks", args, {
      encoding: "utf8",
      windowsHide: true,
    });
    return {
      stdout: String(stdout ?? ""),
      stderr: String(stderr ?? ""),
      code: 0,
    };
  } catch (error) {
    const e = error as {
      stdout?: unknown;
      stderr?: unknown;
      code?: unknown;
      message?: unknown;
    };
    return {
      stdout: typeof e.stdout === "string" ? e.stdout : "",
      stderr:
        typeof e.stderr === "string" ? e.stderr : typeof e.message === "string" ? e.message : "",
      code: typeof e.code === "number" ? e.code : 1,
    };
  }
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
}: {
  env: Record<string, string | undefined>;
  stdout: NodeJS.WritableStream;
  programArguments: string[];
  workingDirectory?: string;
  environment?: Record<string, string | undefined>;
}): Promise<{ scriptPath: string }> {
  await assertSchtasksAvailable();

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

  stdout.write("\n");
  stdout.write(`${formatLine("Installed Scheduled Task", taskName)}\n`);
  stdout.write(`${formatLine("Task script", watchdogScriptPath)}\n`);
  stdout.write(`${formatLine("Repeat interval", "1 minute")}\n`);

  return { scriptPath: watchdogScriptPath };
}

export async function uninstallScheduledTask({
  env,
  stdout,
}: {
  env: Record<string, string | undefined>;
  stdout: NodeJS.WritableStream;
}): Promise<void> {
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

export async function stopScheduledTask({
  stdout,
  env,
}: {
  stdout: NodeJS.WritableStream;
  env?: Record<string, string | undefined>;
}): Promise<void> {
  await assertSchtasksAvailable();
  const taskName = resolveTaskName(env ?? (process.env as Record<string, string | undefined>));
  const res = await execSchtasks(["/End", "/TN", taskName]);
  if (res.code !== 0 && !isTaskNotRunning(res)) {
    throw new Error(`schtasks end failed: ${res.stderr || res.stdout}`.trim());
  }
  stdout.write(`${formatLine("Stopped Scheduled Task", taskName)}\n`);
}

export async function restartScheduledTask({
  stdout,
  env,
}: {
  stdout: NodeJS.WritableStream;
  env?: Record<string, string | undefined>;
}): Promise<void> {
  await assertSchtasksAvailable();
  const taskName = resolveTaskName(env ?? (process.env as Record<string, string | undefined>));
  await execSchtasks(["/End", "/TN", taskName]);
  const res = await execSchtasks(["/Run", "/TN", taskName]);
  if (res.code !== 0) {
    throw new Error(`schtasks run failed: ${res.stderr || res.stdout}`.trim());
  }
  stdout.write(`${formatLine("Restarted Scheduled Task", taskName)}\n`);
}

export async function isScheduledTaskInstalled(args: {
  env?: Record<string, string | undefined>;
}): Promise<boolean> {
  await assertSchtasksAvailable();
  const taskName = resolveTaskName(args.env ?? (process.env as Record<string, string | undefined>));
  const res = await execSchtasks(["/Query", "/TN", taskName]);
  return res.code === 0;
}

export async function readScheduledTaskRuntime(
  env: Record<string, string | undefined> = process.env as Record<string, string | undefined>,
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
