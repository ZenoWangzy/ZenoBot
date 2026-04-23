"""
Unified Gateway Watchdog — 统一看门狗
监控 OpenClaw Gateway + Hermes Gateway 的健康状态，异常时自动修复。

检查项:
1. OpenClaw Gateway 进程 + HTTP 健康端点
2. OpenClaw Discord 连接
3. Hermes Gateway 进程 + gateway_state.json
4. Hermes Discord + 微信连接状态

修复策略:
- 确定性修复（重启）→ 失败则 Claude Code 修复
"""

import json
import subprocess
import sys
import tempfile
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path

# ─── 配置 ───
OPENCLAW_PORT = 18789
OPENCLAW_HEALTH_URL = f"http://127.0.0.1:{OPENCLAW_PORT}/health"
OPENCLAW_HOME = Path.home() / ".openclaw"
HERMES_HOME = Path.home() / ".hermes"
LOG_FILE = Path.home() / "unified-watchdog.log"
STATE_FILE = Path(tempfile.gettempdir()) / "unified-watchdog-state.json"

# Claude Code 修复阈值
CLAUDE_THRESHOLD = 3
CLAUDE_TIMEOUT = 300  # 秒

def log(msg: str):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass

def run(cmd: str, timeout: int = 30) -> str:
    try:
        return subprocess.check_output(
            cmd, shell=True, stderr=subprocess.STDOUT, text=True,
            timeout=timeout, encoding="utf-8", errors="replace",
        )
    except subprocess.CalledProcessError as e:
        return e.output if e.output else ""
    except subprocess.TimeoutExpired:
        return ""
    except Exception as e:
        return str(e)

def load_state() -> dict:
    try:
        if STATE_FILE.exists():
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except Exception:
        pass
    return {
        "openclaw_failures": 0,
        "hermes_failures": 0,
        "last_healthy_at": None,
        "last_run_at": None,
        "last_claude_at": None,
        "last_claude_reason": None,
    }

def save_state(state: dict):
    state["last_run_at"] = datetime.now(timezone.utc).isoformat()
    try:
        STATE_FILE.write_text(json.dumps(state, indent=2, ensure_ascii=False), encoding="utf-8")
    except Exception:
        pass

# ─── OpenClaw 检查 ───

def check_openclaw_gateway() -> bool:
    """检查 OpenClaw Gateway HTTP 健康端点"""
    try:
        req = urllib.request.Request(OPENCLAW_HEALTH_URL, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
            return data.get("ok") is True
    except Exception:
        return False

def check_openclaw_discord() -> bool:
    """通过 OpenClaw CLI 检查 Discord 连接"""
    output = run(f'node {Path("D:/zeno/openclaw/dist/index.js").as_posix()} channels status --probe', timeout=30)
    if not output:
        return False
    if "Gateway not reachable" in output:
        return False
    import re
    return bool(re.search(r"(?im)^\s*-\s*Discord[^\r\n]*:\s.*\b(connected|ready)\b", output))

def restart_openclaw_gateway():
    """重启 OpenClaw Gateway"""
    log("[openclaw] Stopping gateway...")
    # Kill existing process on port
    run(f'for /f "tokens=5" %a in (\'netstat -ano ^| findstr :{OPENCLAW_PORT} ^| findstr LISTENING\') do taskkill /PID %a /F', timeout=10)
    time.sleep(2)

    log("[openclaw] Starting gateway...")
    # Use the existing gateway.cmd or direct node
    gateway_cmd = OPENCLAW_HOME / "gateway.cmd"
    if gateway_cmd.exists():
        subprocess.Popen(
            ["cmd", "/c", str(gateway_cmd)],
            creationflags=subprocess.CREATE_NO_WINDOW,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    else:
        subprocess.Popen(
            ["node", "D:/zeno/openclaw/dist/index.js", "gateway", "--port", str(OPENCLAW_PORT)],
            creationflags=subprocess.CREATE_NO_WINDOW,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    time.sleep(10)

# ─── Hermes 检查 ───

def check_hermes_gateway() -> bool:
    """检查 Hermes Gateway 进程和状态"""
    state_file = HERMES_HOME / "gateway_state.json"
    if not state_file.exists():
        return False
    try:
        state = json.loads(state_file.read_text(encoding="utf-8"))
        return state.get("gateway_state") == "running"
    except Exception:
        return False

def check_hermes_platforms() -> dict:
    """检查 Hermes 各平台连接状态"""
    state_file = HERMES_HOME / "gateway_state.json"
    if not state_file.exists():
        return {"discord": False, "weixin": False}
    try:
        state = json.loads(state_file.read_text(encoding="utf-8"))
        platforms = state.get("platforms", {})
        return {
            "discord": platforms.get("discord", {}).get("state") == "connected",
            "weixin": platforms.get("weixin", {}).get("state") == "connected",
        }
    except Exception:
        return {"discord": False, "weixin": False}

def restart_hermes_gateway():
    """重启 Hermes Gateway"""
    log("[hermes] Restarting via PM2...")
    # Clean stale PID
    pid_file = HERMES_HOME / "gateway.pid"
    if pid_file.exists():
        pid_file.unlink()
    run("pm2 restart hermes-gateway", timeout=15)
    time.sleep(5)
    run("pm2 save", timeout=10)

# ─── Claude Code 修复 ───

def claude_repair(reason: str):
    """调用 Claude Code 进行智能修复"""
    log(f"[claude] Invoking Claude Code repair: {reason}")

    # 收集诊断信息
    diagnostics = []
    diagnostics.append(f"=== OpenClaw Gateway Log (last 30 lines) ===")
    gateway_log = Path(tempfile.gettempdir()) / "openclaw-gateway.log"
    if gateway_log.exists():
        try:
            lines = gateway_log.read_text(encoding="utf-8", errors="replace").splitlines()
            diagnostics.extend(lines[-30:])
        except Exception:
            diagnostics.append("(无法读取)")

    diagnostics.append(f"\n=== Hermes Gateway Log (last 30 lines) ===")
    hermes_log = HERMES_HOME / "logs" / "gateway.log"
    if hermes_log.exists():
        try:
            lines = hermes_log.read_text(encoding="utf-8", errors="replace").splitlines()
            diagnostics.extend(lines[-30:])
        except Exception:
            diagnostics.append("(无法读取)")

    diagnostics.append(f"\n=== Hermes Healthcheck Log (last 20 lines) ===")
    hc_log = HERMES_HOME / "healthcheck.log"
    if hc_log.exists():
        try:
            lines = hc_log.read_text(encoding="utf-8", errors="replace").splitlines()
            diagnostics.extend(lines[-20:])
        except Exception:
            diagnostics.append("(无法读取)")

    diag_text = "\n".join(diagnostics)

    prompt = f"""Unified Gateway Watchdog 检测到问题: {reason}

## 诊断信息
{diag_text}

## 修复要求
请诊断并修复问题。重点关注:
1. Gateway 进程状态
2. Discord 连接 (OpenClaw + Hermes)
3. 微信连接 (Hermes)
4. 配置文件正确性

修复后确保两个 Gateway 都正常运行。"""

    result = run(f'claude -p "{prompt}" --allowedTools Read,Write,Edit,Bash', timeout=CLAUDE_TIMEOUT)
    log(f"[claude] Repair completed: {result[:200]}...")

# ─── 主循环 ───

def watchdog_tick():
    state = load_state()
    all_healthy = True

    # ── 检查 OpenClaw ──
    log("Checking OpenClaw Gateway...")
    oc_healthy = check_openclaw_gateway()

    if not oc_healthy:
        log("[openclaw] Gateway unhealthy, attempting restart...")
        restart_openclaw_gateway()
        oc_healthy = check_openclaw_gateway()

    if oc_healthy:
        state["openclaw_failures"] = 0
        log("[openclaw] Gateway healthy")

        # 检查 Discord
        oc_discord = check_openclaw_discord()
        if oc_discord:
            log("[openclaw] Discord connected")
        else:
            log("[openclaw] Discord not connected (gateway OK, channel may need time)")
    else:
        state["openclaw_failures"] = state.get("openclaw_failures", 0) + 1
        all_healthy = False
        log(f"[openclaw] Still unhealthy after restart. Failures: {state['openclaw_failures']}")

    # ── 检查 Hermes ──
    log("Checking Hermes Gateway...")
    hermes_healthy = check_hermes_gateway()

    if not hermes_healthy:
        log("[hermes] Gateway unhealthy, attempting restart...")
        restart_hermes_gateway()
        hermes_healthy = check_hermes_gateway()

    if hermes_healthy:
        state["hermes_failures"] = 0
        platforms = check_hermes_platforms()
        hermes_discord = platforms.get("discord", False)
        hermes_weixin = platforms.get("weixin", False)
        log(f"[hermes] Gateway healthy | Discord: {'OK' if hermes_discord else 'DOWN'} | 微信: {'OK' if hermes_weixin else 'DOWN'}")

        if not hermes_discord or not hermes_weixin:
            log(f"[hermes] Platform issue: discord={hermes_discord}, weixin={hermes_weixin}")
            all_healthy = False
    else:
        state["hermes_failures"] = state.get("hermes_failures", 0) + 1
        all_healthy = False
        log(f"[hermes] Still unhealthy after restart. Failures: {state['hermes_failures']}")

    # ── Claude Code 修复 ──
    total_failures = state.get("openclaw_failures", 0) + state.get("hermes_failures", 0)
    if total_failures >= CLAUDE_THRESHOLD and not all_healthy:
        reasons = []
        if state.get("openclaw_failures", 0) >= CLAUDE_THRESHOLD:
            reasons.append(f"OpenClaw Gateway failed {state['openclaw_failures']}x")
        if state.get("hermes_failures", 0) >= CLAUDE_THRESHOLD:
            reasons.append(f"Hermes Gateway failed {state['hermes_failures']}x")
        reason = "; ".join(reasons)
        claude_repair(reason)
        state["last_claude_at"] = datetime.now(timezone.utc).isoformat()
        state["last_claude_reason"] = reason

    if all_healthy:
        state["last_healthy_at"] = datetime.now(timezone.utc).isoformat()

    save_state(state)

    # 输出摘要
    status = "ALL HEALTHY" if all_healthy else "ISSUES DETECTED"
    log(f"Tick complete: {status} | OC failures: {state.get('openclaw_failures', 0)} | Hermes failures: {state.get('hermes_failures', 0)}")

if __name__ == "__main__":
    watchdog_tick()
