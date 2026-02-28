[根目录](../CLAUDE.md) > **scripts**

---

# Scripts 模块

> 构建部署脚本

---

## 变更记录 (Changelog)

### 2026-02-11
- 创建模块文档

---

## 模块职责

`scripts/` 包含项目构建、部署和开发脚本。

### 主要脚本类别

| 类别 | 描述 |
|------|------|
| 构建 | TypeScript 构建、UI 打包 |
| 部署 | macOS/iOS/Android 打包 |
| 测试 | E2E 测试、Docker 测试 |
| 开发 | 开发服务器、文件监听 |
| 工具 | 代码生成、协议生成 |

---

## 关键脚本

| 脚本 | 描述 |
|------|------|
| `scripts/run-node.mjs` | 运行 Node 入口 |
| `scripts/watch-node.mjs` | 文件监听模式 |
| `scripts/ui.js` | UI 构建/开发 |
| `scripts/protocol-gen.ts` | 协议生成 |
| `scripts/package-mac-app.sh` | macOS 打包 |

---

## 相关文件清单

```
scripts/
├── run-node.mjs             # 运行入口
├── watch-node.mjs           # 文件监听
├── ui.js                    # UI 脚本
├── protocol-gen.ts          # 协议生成
├── package-mac-app.sh       # macOS 打包
├── build-icon.sh            # 图标构建
├── docs-i18n/               # 文档国际化
│   └── *.go
├── docker/                  # Docker 脚本
├── e2e/                     # E2E 测试脚本
└── systemd/                 # systemd 服务文件
```
