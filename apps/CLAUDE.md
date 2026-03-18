[根目录](../CLAUDE.md) > **apps**

# Apps

## 模块职责

Apps 目录包含 OpenClaw 的客户端应用，包括：

1. **iOS 应用** - Apple iOS 客户端
2. **Android 应用** - Android 客户端
3. **macOS 应用** - macOS 菜单栏应用（Gateway 宿主）
4. **共享代码** - 跨平台共享的 Swift 代码

## 应用列表

| 应用 | 目录 | 平台 | 描述 |
|------|------|------|------|
| iOS | `ios/` | iOS | iPhone/iPad 客户端 |
| Android | `android/` | Android | Android 客户端 |
| macOS | `macos/` | macOS | 菜单栏应用 + Gateway 宿主 |
| Shared | `shared/` | 跨平台 | 共享 Swift 代码 |

## 开发命令

### iOS

```bash
pnpm ios:gen      # 生成 Xcode 项目
pnpm ios:open     # 打开 Xcode
pnpm ios:build    # 构建
pnpm ios:run      # 运行
```

### Android

```bash
pnpm android:assemble  # 构建 APK
pnpm android:install   # 安装
pnpm android:run       # 运行
pnpm android:lint      # Lint 检查
pnpm android:test      # 测试
```

### macOS

```bash
pnpm mac:package   # 打包应用
pnpm mac:open      # 打开应用
pnpm mac:restart   # 重启 Gateway
```

## 关键配置

### 版本位置

- iOS: `apps/ios/Sources/Info.plist`
- Android: `apps/android/app/build.gradle.kts`
- macOS: `apps/macos/Sources/OpenClaw/Resources/Info.plist`

### 签名

- iOS: 运行 `./scripts/ios-configure-signing.sh` 配置签名
- macOS: 需要 Apple Developer 证书

## 相关文件

- [根目录 CLAUDE.md](../CLAUDE.md)
- [macOS 发布文档](../docs/platforms/mac/release.md)

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
