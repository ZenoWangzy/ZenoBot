[根目录](../CLAUDE.md) > **skills**

---

# Skills 模块

> AI 技能插件集合

---

## 变更记录 (Changelog)

### 2026-03-06
- 添加技能使用说明

### 2026-02-11
- 创建模块文档

---

## 模块职责

`skills/` 包含各种 AI 技能插件，扩展 OpenClaw 的功能。

### 使用技能
```bash
# 在对话中调用技能
openclaw agent --message "使用 github 技能查看 PR"
```

### 技能开发
技能使用 SKILL.md 格式定义，放置在技能目录中。

### 技能列表

| 技能 | 描述 | 语言 |
|------|------|------|
| 1password | 1Password 集成 | - |
| apple-notes | Apple Notes 集成 | - |
| apple-reminders | Apple Reminders 集成 | - |
| bear-notes | Bear Notes 集成 | - |
| discord | Discord 集成 | - |
| github | GitHub 集成 | - |
| local-places | 本地地点搜索 | Python |
| notion | Notion 集成 | - |
| obsidian | Obsidian 集成 | - |
| openai-image-gen | OpenAI 图像生成 | Python |
| openai-whisper | Whisper 语音转文字 | - |
| slack | Slack 集成 | - |
| spotify-player | Spotify 控制 | - |
| tmux | tmux 会话管理 | Shell |
| trello | Trello 集成 | - |
| weather | 天气查询 | - |

---

## 相关文件清单

```
skills/
├── 1password/
├── apple-notes/
├── apple-reminders/
├── bear-notes/
├── discord/
├── github/
├── local-places/
│   ├── pyproject.toml
│   └── src/
├── notion/
├── obsidian/
├── openai-image-gen/
├── openai-whisper/
├── slack/
├── spotify-player/
├── tmux/
├── trello/
└── weather/
```
