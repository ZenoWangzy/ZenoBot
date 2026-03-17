#!/usr/bin/env python3
import argparse
import os
import shlex
import subprocess


def run_with_pty(cmd, cwd=None, env=None):
    script_bin = "script"
    if os.uname().sysname.lower() == "darwin":
        # macOS BSD script syntax
        p = subprocess.run([script_bin, "-q", "/dev/null", *cmd], cwd=cwd, env=env)
    else:
        # Linux util-linux script syntax
        cmd_str = " ".join(shlex.quote(x) for x in cmd)
        p = subprocess.run([script_bin, "-q", "-c", cmd_str, "/dev/null"], cwd=cwd, env=env)
    return p.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--claude-bin", required=True)
    ap.add_argument("--prompt", required=False, default="")
    ap.add_argument("--continue-latest", action="store_true")
    ap.add_argument("--permission-mode", default="bypassPermissions")
    ap.add_argument("--allowed-tools", default="")
    ap.add_argument("--teammate-mode", default="")
    ap.add_argument("--model", default="")
    ap.add_argument("--agent-teams", action="store_true")
    ap.add_argument("--workdir", default="")
    ap.add_argument("--session-id", default="")
    ap.add_argument("--resume", default="", help="Session ID to resume")
    ap.add_argument("--fork-session", action="store_true")
    args = ap.parse_args()

    if not args.prompt and not args.continue_latest and not args.resume:
        raise SystemExit("either --prompt, --continue-latest, or --resume is required")

    cmd = [args.claude_bin, "--permission-mode", args.permission_mode]
    if args.continue_latest:
        cmd += ["--continue"]
    if args.prompt:
        cmd += ["-p", args.prompt]
    if args.allowed_tools:
        cmd += ["--allowedTools", args.allowed_tools]
    if args.teammate_mode:
        cmd += ["--teammate-mode", args.teammate_mode]

    # 多轮对话支持
    if args.session_id:
        cmd += ["--session-id", args.session_id]
    if args.resume:
        cmd += ["--resume", args.resume]
    if args.fork_session:
        cmd += ["--fork-session"]

    env = os.environ.copy()
    if args.model:
        env["ANTHROPIC_MODEL"] = args.model
    if args.agent_teams:
        env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"

    rc = run_with_pty(cmd, cwd=(args.workdir or None), env=env)
    raise SystemExit(rc)


if __name__ == "__main__":
    main()
