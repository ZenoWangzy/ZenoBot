[根目录](../../CLAUDE.md) > **apps** > **ios**

---

# iOS 应用模块

> iOS 原生应用

---

## 变更记录 (Changelog)

### 2026-03-06
- 添加版本管理、签名信息

### 2026-02-11
- 创建模块文档

---

## 模块职责

`apps/ios/` 是 OpenClaw 的 iOS 原生应用，使用 Swift 开发。

---

## 版本管理

### 版本位置
- `apps/ios/Sources/Info.plist` - CFBundleShortVersionString, CFBundleVersion
- `apps/ios/Tests/Info.plist` - 测试目标版本

### 签名
```bash
# 查找 Team ID
security find-identity -p codesigning -v
# 或
defaults read com.apple.dt.Xcode IDEProvisioningTeamIdentifiers
```

---

## 入口与启动

### 构建命令
```bash
# 生成 Xcode 项目
pnpm ios:gen

# 打开 Xcode
pnpm ios:open

# 构建
pnpm ios:build
```

---

## 相关文件清单

```
apps/ios/
├── Sources/
│   ├── Assets.xcassets/
│   └── OpenClaw/
└── project.yml
```
