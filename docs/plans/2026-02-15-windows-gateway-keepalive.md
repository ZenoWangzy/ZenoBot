# Windows Gateway Keepalive Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现Windows上的Gateway保活机制，确保gateway崩溃后1分钟内自动重启，电脑重启后自动启动。

**Architecture:** 创建watchdog模块检测端口18789是否被监听，未监听则启动gateway。修改Scheduled Task添加每分钟重复触发器，运行watchdog脚本。

**Tech Stack:** TypeScript, Node.js net模块, Windows schtasks

---

## Task 1: 创建watchdog模块

**Files:**
- Create: `src/daemon/watchdog.ts`
- Create: `src/daemon/watchdog.test.ts`

**Step 1: Write the failing test**

```typescript
// src/daemon/watchdog.test.ts
import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { isPortListening } from "./watchdog.js";

describe("watchdog", () => {
  describe("isPortListening", () => {
    it("returns true when port is listening", async () => {
      // This test will be skipped on non-Windows platforms
      if (process.platform !== "win32") {
        return;
      }
      // We'll mock this in the actual implementation
      const result = await isPortListening(18789);
      expect(typeof result).toBe("boolean");
    });

    it("returns false when port is not listening", async () => {
      if (process.platform !== "win32") {
        return;
      }
      // Use an unlikely port
      const result = await isPortListening(59999);
      expect(result).toBe(false);
    });
  });
});
```

**Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/daemon/watchdog.test.ts`
Expected: FAIL with "could not resolve" or "isPortListening is not defined"

**Step 3: Write minimal implementation**

```typescript
// src/daemon/watchdog.ts
import net from "node:net";

/**
 * Check if a port is being listened on (Windows only).
 * On non-Windows platforms, always returns true (no-op).
 */
export async function isPortListening(port: number, host = "127.0.0.1"): Promise<boolean> {
  if (process.platform !== "win32") {
    return true;
  }

  return new Promise((resolve) => {
    const socket = new net.Socket();
    const timeout = 5000;

    const onError = () => {
      socket.destroy();
      resolve(false);
    };

    socket.setTimeout(timeout);
    socket.once("error", onError);
    socket.once("timeout", onError);

    socket.connect(port, host, () => {
      socket.end();
      resolve(true);
    });
  });
}

/**
 * Resolve the watchdog script path for Windows Scheduled Task.
 */
export function resolveWatchdogScriptPath(env: Record<string, string | undefined>): string {
  const stateDir = env.OPENCLAW_STATE_DIR?.trim();
  if (stateDir) {
    const home = stateDir.startsWith("~") ? env.HOME?.trim() || env.USERPROFILE?.trim() : undefined;
    const basePath = home ? stateDir.replace(/^~(?=$|[/\\])/, home) : stateDir;
    return require("path").join(basePath, "gateway-watchdog.cmd");
  }

  const home = env.HOME?.trim() || env.USERPROFILE?.trim();
  if (!home) {
    throw new Error("Missing HOME or USERPROFILE");
  }

  const profile = env.OPENCLAW_PROFILE?.trim();
  const suffix = profile && profile.toLowerCase() !== "default" ? `-${profile}` : "";
  return require("path").join(home, `.openclaw${suffix}`, "gateway-watchdog.cmd");
}
```

**Step 4: Run test to verify it passes**

Run: `pnpm vitest run src/daemon/watchdog.test.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add src/daemon/watchdog.ts src/daemon/watchdog.test.ts
git commit -m "feat(daemon): add Windows watchdog module for port detection

- Add isPortListening() to check if gateway port is active
- Add resolveWatchdogScriptPath() for watchdog script path resolution
- Windows-only, no-op on other platforms"
```

---

## Task 2: 添加watchdog启动gateway的函数

**Files:**
- Modify: `src/daemon/watchdog.ts`
- Modify: `src/daemon/watchdog.test.ts`

**Step 1: Write the failing test**

```typescript
// Add to src/daemon/watchdog.test.ts
import { spawn } from "node:child_process";
import { buildWatchdogScript } from "./watchdog.js";

describe("buildWatchdogScript", () => {
  it("generates valid batch script content", () => {
    const script = buildWatchdogScript({
      programArguments: ["node", "gateway.js", "--port", "18789"],
      workingDirectory: "C:\\Projects\\openclaw",
      environment: { NODE_ENV: "production" },
    });

    expect(script).toContain("@echo off");
    expect(script).toContain("cd /d");
    expect(script).toContain("C:\\Projects\\openclaw");
    expect(script).toContain("set NODE_ENV=production");
    expect(script).toContain("node gateway.js --port 18789");
  });

  it("handles paths with spaces", () => {
    const script = buildWatchdogScript({
      programArguments: ["C:\\Program Files\\nodejs\\node.exe", "gateway.js"],
      workingDirectory: "C:\\My Projects\\openclaw",
    });

    expect(script).toContain('"C:\\Program Files\\nodejs\\node.exe"');
    expect(script).toContain('"C:\\My Projects\\openclaw"');
  });
});
```

**Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/daemon/watchdog.test.ts`
Expected: FAIL with "buildWatchdogScript is not defined"

**Step 3: Write minimal implementation**

Add to `src/daemon/watchdog.ts`:

```typescript
import path from "node:path";

/**
 * Quote a command argument for Windows batch script if needed.
 */
function quoteCmdArg(value: string): string {
  if (!/[ \t"]/g.test(value)) {
    return value;
  }
  return `"${value.replace(/"/g, '\\"')}"`;
}

export type WatchdogScriptParams = {
  programArguments: string[];
  workingDirectory?: string;
  environment?: Record<string, string | undefined>;
};

/**
 * Build a Windows batch script that checks port and starts gateway if not running.
 */
export function buildWatchdogScript(params: WatchdogScriptParams): string {
  const lines: string[] = ["@echo off"];
  lines.push("rem OpenClaw Gateway Watchdog");

  // Change to working directory
  if (params.workingDirectory) {
    lines.push(`cd /d ${quoteCmdArg(params.workingDirectory)}`);
  }

  // Set environment variables
  if (params.environment) {
    for (const [key, value] of Object.entries(params.environment)) {
      if (value) {
        lines.push(`set ${key}=${value}`);
      }
    }
  }

  // Check if gateway is already running via port check
  // Use netstat to check if port is listening
  const port = params.programArguments.includes("--port")
    ? params.programArguments[params.programArguments.indexOf("--port") + 1]
    : "18789";

  lines.push("");
  lines.push("rem Check if gateway port is already listening");
  lines.push(`netstat -an | findstr ":${port}.*LISTENING" >nul 2>&1`);
  lines.push("if %errorlevel% equ 0 (");
  lines.push("    rem Gateway already running, exit silently");
  lines.push("    exit /b 0");
  lines.push(")");

  // Start gateway
  lines.push("");
  lines.push("rem Gateway not running, start it");
  const command = params.programArguments.map(quoteCmdArg).join(" ");
  lines.push(`start /b "" ${command}`);

  return `${lines.join("\r\n")}\r\n`;
}
```

**Step 4: Run test to verify it passes**

Run: `pnpm vitest run src/daemon/watchdog.test.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add src/daemon/watchdog.ts src/daemon/watchdog.test.ts
git commit -m "feat(daemon): add buildWatchdogScript for Windows gateway watchdog

- Generates batch script that checks port before starting gateway
- Uses netstat to detect if gateway is already running
- Starts gateway with start /b for background execution"
```

---

## Task 3: 修改schtasks.ts添加重复触发器

**Files:**
- Modify: `src/daemon/schtasks.ts`
- Modify: `src/daemon/schtasks.test.ts`

**Step 1: Write the failing test**

Add to `src/daemon/schtasks.test.ts`:

```typescript
import { buildWatchdogTaskArgs } from "./schtasks.js";

describe("buildWatchdogTaskArgs", () => {
  it("includes repeat interval for watchdog task", () => {
    const args = buildWatchdogTaskArgs({
      taskName: "OpenClaw Gateway",
      scriptPath: "C:\\Users\\test\\.openclaw\\gateway-watchdog.cmd",
    });

    expect(args).toContain("/SC");
    expect(args).toContain("ONLOGON");
    expect(args).toContain("/RI");
    expect(args).toContain("1"); // 1 minute repeat
    expect(args).toContain("/TN");
    expect(args).toContain("OpenClaw Gateway");
  });
});
```

**Step 2: Run test to verify it fails**

Run: `pnpm vitest run src/daemon/schtasks.test.ts`
Expected: FAIL with "buildWatchdogTaskArgs is not defined"

**Step 3: Write minimal implementation**

Add to `src/daemon/schtasks.ts`:

```typescript
/**
 * Build schtasks arguments for watchdog-style task with repeat interval.
 * This creates a task that runs at login and repeats every 1 minute.
 */
export function buildWatchdogTaskArgs(params: {
  taskName: string;
  scriptPath: string;
  taskUser?: string | null;
}): string[] {
  const { taskName, scriptPath, taskUser } = params;
  const quotedScript = quoteCmdArg(scriptPath);

  const baseArgs = [
    "/Create",
    "/F",
    "/SC",
    "ONLOGON",
    "/RL",
    "LIMITED",
    "/RI",
    "1", // Repeat every 1 minute
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
```

**Step 4: Run test to verify it passes**

Run: `pnpm vitest run src/daemon/schtasks.test.ts`
Expected: PASS

**Step 5: Commit**

```bash
git add src/daemon/schtasks.ts src/daemon/schtasks.test.ts
git commit -m "feat(daemon): add buildWatchdogTaskArgs with repeat interval

- Add /RI 1 for 1-minute repeat interval
- Enables scheduled task to check gateway every minute"
```

---

## Task 4: 修改installScheduledTask使用watchdog

**Files:**
- Modify: `src/daemon/schtasks.ts`

**Step 1: 修改installScheduledTask函数**

在 `installScheduledTask` 函数中：

1. 导入watchdog模块
2. 检测是否是Windows平台
3. 生成watchdog脚本而非直接启动gateway的脚本
4. 使用带重复触发器的任务参数

修改后的关键部分：

```typescript
import { buildWatchdogScript, resolveWatchdogScriptPath } from "./watchdog.js";

export async function installScheduledTask({
  env,
  stdout,
  programArguments,
  workingDirectory,
  environment,
  description,
}: {
  env: Record<string, string | undefined>;
  stdout: NodeJS.WritableStream;
  programArguments: string[];
  workingDirectory?: string;
  environment?: Record<string, string | undefined>;
  description?: string;
}): Promise<{ scriptPath: string }> {
  await assertSchtasksAvailable();

  // Use watchdog script instead of direct gateway script
  const watchdogScriptPath = resolveWatchdogScriptPath(env);
  await fs.mkdir(path.dirname(watchdogScriptPath), { recursive: true });

  const taskDescription =
    description ??
    formatGatewayServiceDescription({
      profile: env.OPENCLAW_PROFILE,
      version: environment?.OPENCLAW_SERVICE_VERSION ?? env.OPENCLAW_SERVICE_VERSION,
    });

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
```

**Step 2: Run existing tests to verify no regression**

Run: `pnpm vitest run src/daemon/schtasks.test.ts`
Expected: PASS (existing tests should still pass)

**Step 3: Commit**

```bash
git add src/daemon/schtasks.ts
git commit -m "feat(daemon): use watchdog script in installScheduledTask

- Generate watchdog script instead of direct gateway script
- Use repeat interval for continuous monitoring
- Shows repeat interval in install output"
```

---

## Task 5: 修改uninstallScheduledTask清理watchdog脚本

**Files:**
- Modify: `src/daemon/schtasks.ts`

**Step 1: 修改uninstallScheduledTask函数**

```typescript
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
```

**Step 2: Run tests**

Run: `pnpm vitest run src/daemon/schtasks.test.ts`
Expected: PASS

**Step 3: Commit**

```bash
git add src/daemon/schtasks.ts
git commit -m "fix(daemon): cleanup watchdog script on uninstall

- Remove watchdog script on uninstall
- Also cleanup legacy gateway.cmd if exists"
```

---

## Task 6: 运行完整测试套件验证

**Step 1: Run all daemon tests**

Run: `pnpm vitest run src/daemon/`
Expected: All tests pass

**Step 2: Run lint**

Run: `pnpm lint`
Expected: No errors

**Step 3: Run type check**

Run: `pnpm tsc --noEmit`
Expected: No type errors

**Step 4: Commit if any fixes needed**

```bash
git add -A
git commit -m "fix(daemon): address test/lint/type issues"
```

---

## Task 7: 手动测试验证

**Step 1: Build the project**

Run: `pnpm build`
Expected: Build succeeds

**Step 2: Install daemon**

Run: `openclaw gateway install --daemon`
Expected: Shows "Repeat interval: 1 minute" in output

**Step 3: Verify task was created with repeat**

Run: `schtasks /Query /TN "OpenClaw Gateway" /V /FO LIST`
Expected: Task shows repeat interval of 1 minute

**Step 4: Verify watchdog script exists**

Run: `type %USERPROFILE%\.openclaw\gateway-watchdog.cmd`
Expected: Shows batch script with netstat port check

**Step 5: Test crash recovery**

1. Start gateway
2. Kill gateway process
3. Wait 1-2 minutes
4. Verify gateway restarts automatically

**Step 6: Final commit**

```bash
git add docs/plans/2026-02-15-windows-gateway-keepalive.md
git commit -m "docs: add Windows gateway keepalive implementation plan"
```

---

## Summary

| Task | Description | Files Changed |
|------|-------------|---------------|
| 1 | Create watchdog module | `watchdog.ts`, `watchdog.test.ts` |
| 2 | Add buildWatchdogScript | `watchdog.ts`, `watchdog.test.ts` |
| 3 | Add buildWatchdogTaskArgs | `schtasks.ts`, `schtasks.test.ts` |
| 4 | Modify installScheduledTask | `schtasks.ts` |
| 5 | Modify uninstallScheduledTask | `schtasks.ts` |
| 6 | Run tests | - |
| 7 | Manual verification | - |
