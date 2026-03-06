[根目录](../../CLAUDE.md) > **apps** > **macos**

---

# macOS 应用模块

> macOS 原生应用

---

## 变更记录 (Changelog)

### 2026-03-06
- 添加版本管理、发布流程、Gateway 管理信息

### 2026-02-11
- 创建模块文档

---

## 模块职责

`apps/macos/` 是 OpenClaw 的 macOS 原生应用，使用 Swift 开发。

---

## 版本管理

### 版本位置
- `apps/macos/Sources/OpenClaw/Resources/Info.plist` - CFBundleShortVersionString, CFBundleVersion

### 发布流程
详见 `docs/platforms/mac/release.md` - 包含 Sparkle auto-update、公证、签名流程。

### Gateway 管理
Gateway 当前仅通过 menubar app 运行；无独立 LaunchAgent。
```bash
# 重启 Gateway
./scripts/restart-mac.sh

# 验证 Gateway 状态
launchctl print gui/$UID | grep openclaw
```

---

## 入口与启动

### 构建命令
```bash
# 打包应用
pnpm mac:package

# 打开应用
pnpm mac:open
```

---

## 相关文件清单

```
apps/macos/
├── Sources/
│   └── OpenClaw/
└── project.yml
```
