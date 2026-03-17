# QMD 集成指南

> QMD 是 zenomacbot 的本地文档搜索引擎
> 支持关键词搜索、语义搜索、混合搜索

---

## 🚀 快速开始

### 1. 创建集合（Collections）

```bash
# 创建 zenomacbot 记忆集合
cd ~/.openclaw/workspace
qmd collection add . --name zenomacbot

# 创建每日笔记集合（可选）
qmd collection add memory --name daily-notes --mask "**/*.md"

# 查看所有集合
qmd collection list
```

### 2. 添加上下文（Context）

```bash
# 为 zenomacbot 添加上下文
qmd context add qmd://zenomacbot "zenomacbot 的身份、人格、规则和记忆"

# 为 daily-notes 添加上下文
qmd context add qmd://daily-notes "每日学习笔记，包含对话、事件、学习到的新信息"

# 查看所有上下文
qmd context list
```

### 3. 生成向量嵌入

```bash
# 为所有集合生成嵌入
qmd embed
```

---

## 🔍 使用 QMD 搜索

### 基本搜索

```bash
# 关键词搜索（快速）
qmd search "终极目标"

# 语义搜索（理解含义）
qmd vsearch "关于成功的观点"

# 混合搜索（最准确）
qmd query "怎么处理记忆"
```

### 高级搜索

```bash
# 在特定集合中搜索
qmd search "感情" -c zenomacbot

# 返回更多结果（默认 5，最多 20）
qmd query "创业" -n 10

# 设置最低分数阈值
qmd query "价值观" --min-score 0.5

# 显示完整文档内容
qmd search "网络自动恢复" --full
```

### JSON 输出（用于 AI 集成）

```bash
# JSON 格式输出（适合程序处理）
qmd search "WhatsApp" --json -n 5

# 返回所有匹配（用于深度检索）
qmd query "备份策略" --all --files --min-score 0.3
```

---

## 🤖 与 AI 集成

### 在工具中使用

当需要搜索记忆时，使用以下命令：

```bash
# 关键词搜索（快速）
qmd search "关键词" --json -n 5

# 语义搜索（理解）
qmd vsearch "自然语言查询" --json -n 5

# 混合搜索（最佳）
qmd query "复杂查询" --json -n 10 --min-score 0.3
```

### 解析 JSON 输出

JSON 输出格式：

```json
{
  "query": "终极目标",
  "results": [
    {
      "docid": "a1b2c3",
      "score": 0.92,
      "filepath": "MEMORY.md",
      "context": "zenomacbot 的长期记忆"
    }
  ]
}
```

---

## 📊 维护

### 更新索引

```bash
# 当记忆文件更新后，重新索引
qmd update

# 强制重新嵌入所有文档
qmd embed -f
```

### 查看状态

```bash
# 查看索引状态
qmd status
```

### 清理

```bash
# 清理缓存和孤立数据
qmd cleanup
```

---

## 🔧 常用命令速查

```bash
# 创建集合
qmd collection add <path> --name <name>

# 添加上下文
qmd context add qmd://<collection> "<description>"

# 生成嵌入
qmd embed

# 搜索
qmd search "<keywords>"              # 关键词
qmd vsearch "<query>"               # 语义
qmd query "<query>" -n 10           # 混合

# 获取文档
qmd get <filepath>                # 按路径
qmd get <docid>                  # 按 docid

# 多个文档
qmd multi-get "pattern"           # 按模式
qmd multi-get "doc1.md,doc2.md"   # 按列表

# 维护
qmd update                       # 更新索引
qmd status                       # 查看状态
qmd cleanup                      # 清理缓存
```

---

## 🎯 zenomacbot 特定配置

### 集合配置

```
zenomacbot: ~/.openclaw/workspace/
  ├── IDENTITY.md          → 核心身份信息
  ├── SOUL.md              → 核心人格定义
  ├── USER.md              → 用户信息
  ├── BOT-RULES.md         → 行为规则
  ├── BOT-MEMORY.md        → 记忆管理
  ├── MEMORY.md            → 长期记忆 ⭐
  └── memory/              → 每日笔记
      ├── 2026-02-06.md
      └── 2026-02-07.md
```

### 上下文示例

```bash
# 主要身份和人格
qmd context add qmd://zenomacbot "zenomacbot 的身份、人格、规则"

# 长期记忆
qmd context add qmd://zenomacbot "长期记忆，包括目标、观点、用户特征"

# 每日笔记
qmd context add qmd://daily-notes "每日学习笔记，包含对话、事件、学习"

# 配置文件
qmd context add qmd://zenomacbot "配置文件、系统知识"
```

---

## 🔄 自动化

### Git Push 后自动更新索引

在 `backup.sh` 中添加：

```bash
#!/bin/bash
cd ~/.openclaw/workspace

# Git 操作
git add .
git commit -m "Backup - $(date '+%Y-%m-%d %H:%M:%S')"
git push origin main

# 更新 QMD 索引
qmd update

echo "✅ Backup completed"
echo "✅ QMD index updated"
```

### 定期更新（每天）

已经在 crontab 中设置，可以添加：

```bash
# 每天凌晨 00:00 更新 QMD 索引
0 0 * * * cd ~/.openclaw/workspace && qmd update >> ~/.openclaw/logs/qmd-update.log 2>&1
```

---

## 📈 性能优化

### 快速搜索

- **关键词搜索** (`search`) - 最快，< 10ms
- **语义搜索** (`vsearch`) - 快速，< 100ms
- **混合搜索** (`query`) - 中等，< 300ms

### 批量搜索

```bash
# 一次搜索多个关键词
qmd search "终极目标 OR 功成名就 OR 留名青史" -n 10
```

---

## 🐛 故障排查

### 问题：搜索不到结果

**解决方案：**

```bash
# 检查索引状态
qmd status

# 更新索引
qmd update

# 检查集合是否正确
qmd collection list
```

### 问题：向量搜索不准确

**解决方案：**

```bash
# 强制重新嵌入
qmd embed -f
```

---

**QMD 是 zenomacbot 记忆系统的重要补充！**

结合：

- MEMORY.md - 精炼的长期记忆
- memory/\*.md - 详细的每日笔记
- QMD 索引 - 快速、智能的搜索
