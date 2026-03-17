# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

Add whatever helps you do your job. This is your cheat sheet.

### QMD (记忆检索首选 fallback)

- Binary: `/Users/ZenoWang/.bun/bin/qmd`
- Workspace: `/Users/ZenoWang/.openclaw/workspace`
- Collection: `zenomacbot`
- 常用命令：
  - `qmd search "关键词" -c zenomacbot -n 10`
  - `qmd query "复杂问题" -n 10 --min-score 0.3`
  - `qmd update`
- 约定：当 `memory_search` 不可用时，默认改用 QMD 检索。

### Scrapling（网页抓取）

- Skill: `/Users/ZenoWang/.openclaw/skills/scrapling/SKILL.md`
- Runner: `/Users/ZenoWang/.openclaw/skills/scrapling/scripts/scrapling_fetch.py`
- Venv: `/Users/ZenoWang/.openclaw/workspace/.venvs/scrapling`
- 说明：静态抓取在这台机器上会先尝试校验证书，失败后回退到 insecure 模式并打印 warning；动态抓取走 Playwright Chromium。
