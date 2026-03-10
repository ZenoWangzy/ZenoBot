---
name: codex-deep-search
description: Deep web search using Codex CLI for complex queries that need multi-source synthesis. Use when web_search (Brave) returns insufficient results, when the user asks for in-depth research, comprehensive analysis, or says "deep search", "详细搜索", "帮我查一下", or when a topic needs following multiple links and cross-referencing sources.
user-invocable: true
---

# Codex Deep Search

Use Codex CLI's web search capability for research tasks needing more depth than Brave API snippets.

## When to Prefer Over web_search

- Complex/niche topics needing multi-source synthesis
- User explicitly asks for thorough/deep research
- Brave results are too shallow or missing context

## Usage

### ⚠️ 重要：Agent 必须使用 Dispatch Mode

**在 Gateway Agent 中，必须使用 Dispatch Mode。**
**同步模式 + poll 会导致 session 卡死，gateway 重启后状态丢失。**

### Dispatch Mode (推荐 — background + callback)

**Discord 回调示例**（推荐）：

```bash
nohup bash $HOME/.openclaw/workspace/skills/codex-deep-search/scripts/search.sh \
  --prompt "Your research query" \
  --task-name "my-research" \
  --discord-channel "853303202236858379" \
  --timeout 120 > /tmp/codex-search.log 2>&1 &
```

**Telegram 回调示例**：

```bash
nohup bash $HOME/.openclaw/workspace/skills/codex-deep-search/scripts/search.sh \
  --prompt "Your research query" \
  --task-name "notebooklm-research" \
  --telegram-group "-5006066016" \
  --timeout 120 > /tmp/codex-search.log 2>&1 &
```

After dispatch: tell user search is running, results will arrive via configured channel. **Do NOT poll.**

### Synchronous Mode (仅限本地 CLI 使用，Agent 禁止)

**⚠️ 警告：不要在 Gateway Agent 中使用同步模式 + exec/poll！**
这会导致 session 卡死，因为 poll 依赖 gateway session 保持活跃。

```bash
# 仅限本地 CLI 直接使用，不要在 agent 中使用
bash $HOME/.openclaw/workspace/skills/codex-deep-search/scripts/search.sh \
  --prompt "Quick factual query" \
  --output "/tmp/search-result.md" \
  --timeout 60
```

## Parameters

| Flag                | Required | Default                               | Description                     |
| ------------------- | -------- | ------------------------------------- | ------------------------------- |
| `--prompt`          | Yes      | —                                     | Research query                  |
| `--output`          | No       | `data/codex-search-results/<task>.md` | Output file path                |
| `--task-name`       | No       | `search-<timestamp>`                  | Task identifier                 |
| `--telegram-group`  | No       | —                                     | Telegram chat ID for callback   |
| `--discord-channel` | No       | —                                     | Discord channel ID for callback |
| `--model`           | No       | `gpt-5.3-codex`                       | Model override                  |
| `--timeout`         | No       | `120`                                 | Seconds before auto-stop        |

## Result Files

| File                                         | Content                     |
| -------------------------------------------- | --------------------------- |
| `data/codex-search-results/<task>.md`        | Search report (incremental) |
| `data/codex-search-results/latest-meta.json` | Task metadata + status      |
| `data/codex-search-results/task-output.txt`  | Raw Codex output            |

## Key Design

- **Incremental writes** — results saved after each search round, survives OOM/timeout
- **Low reasoning effort** — reduces memory, prevents OOM SIGKILL
- **Timeout protection** — auto-stops runaway searches
- **Dispatch pattern** — background execution with Discord/Telegram callback, no polling
- **Gateway wake** — 完成后通过 `/hooks/wake` 通知 gateway（需配置 `hooks.token`）
- **Wake 可观测性** — wake 成败细节写入 `latest-meta.json`（`wake.ok`、`wake.httpCode`）
