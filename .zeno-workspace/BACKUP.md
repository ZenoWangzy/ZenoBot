# BACKUP.md - 备份策略

> 本文件定义 zenomacbot 的备份策略
> 记忆是核心资产，必须妥善保护

---

## 💾 备份原则（Backup Principles）

### 1. 多层备份（Multiple Layers）

- **本地备份**：本地文件系统
- **版本控制**：Git 历史
- **远程备份**：GitHub 私有仓库
- **定期快照**：完整系统快照（可选）

### 2. 自动化（Automated）

- 备份应该自动进行，不依赖人工
- 用户不需要手动触发

### 3. 版本化（Versioned）

- 保留多个版本，不只是最新版
- 可以回滚到任意历史版本

### 4. 可恢复（Recoverable）

- 备份可以快速恢复
- 恢复过程清晰、有文档

---

## 📂 备份内容（What to Backup）

### 必须备份（Critical）

```
workspace/
├── IDENTITY.md          # 身份定义
├── SOUL.md              # 核心人格
├── USER.md              # 用户信息
├── BOT-RULES.md         # 行为规则
├── BOT-MEMORY.md        # 记忆管理
├── MEMORY.md            # 长期记忆 ⭐
└── memory/              # 每日笔记 ⭐
    ├── 2026-02-06.md
    ├── 2026-02-07.md
    └── ...
```

---

## 🕒 备份频率（Backup Frequency）

### 实时备份（Real-time）

**Git 自动 commit**（每次重要变更后）

- 修改了核心身份文件（IDENTITY.md, SOUL.md）
- 修改了核心规则文件（BOT-RULES.md）
- 添加了重要记忆到 MEMORY.md

### 每日备份（Daily）

**Git 自动 commit**（每天结束时）

- 添加或修改了 daily notes
- 更新了学习进度
- 系统配置有变更

---

## 🔧 备份方法（Backup Methods）

### Git + GitHub（主要方法）

#### 自动备份脚本

```bash
#!/bin/bash
# backup.sh - 自动备份脚本

cd ~/.openclaw/workspace

# 添加所有变更
git add .

# Commit（带时间戳）
git commit -m "Backup - $(date '+%Y-%m-%d %H:%M:%S')"

# Push 到 GitHub
git push origin main

echo "Backup completed at $(date)"
```

---

## 🔄 恢复流程（Restore Procedures）

### 从 Git 恢复

```bash
cd ~/.openclaw/workspace

# 查看历史
git log --oneline

# 恢复到特定版本
git checkout <commit-hash>

# 如果确认恢复正确
git checkout -b recovery-branch
git checkout main
git merge recovery-branch
```

---

## 🗑️ 备份清理（Backup Cleanup）

### 本地备份清理

- 保留最近 7 天的每日备份
- 保留最近 4 周的周备份
- 保留最近 12 个月的月备份

---

## ⚠️ 注意事项

### 1. 敏感信息

**不要备份的内容：**

- API keys
- 密码
- 私人对话记录（除非明确要求）

**在 .gitignore 中排除：**

```
# 敏感文件
*.key
*.token
secrets/
private/

# 临时文件
*.tmp
*.bak
.DS_Store
```

---

**备份的核心原则：**

> 如果有重要数据但没有备份，那它就不存在。

自动、多层、可恢复——这是备份系统的三个关键词。
