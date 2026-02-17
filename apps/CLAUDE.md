[根目录](../CLAUDE.md) > **apps**

# apps 模块文档

## 模块职责

`apps/` 包含 OpenClaw 的移动和桌面应用实现，支持 iOS、Android 和 macOS 平台。这些应用作为 Gateway 的节点，提供 Canvas 渲染、语音交互、相机 capture、屏幕录制等功能。

## 入口与启动

### Android 应用
- **入口**: `apps/android/app/src/main/java/ai/openclaw/android/MainActivity.kt`
- **构建**: Gradle (Kotlin)
- **启动命令**: `pnpm android:run`

### iOS 应用
- **入口**: `apps/ios/Sources/`
- **构建**: Xcode (Swift)
- **启动命令**: `pnpm ios:run`

### macOS 应用
- **入口**: `apps/macos/Sources/`
- **构建**: Xcode (Swift)
- **启动命令**: `pnpm mac:open`

## 对外接口

### Android 主要组件
- `MainActivity` - 主 Activity
- `NodeRuntime` - Node.js 运行时管理
- `NodeForegroundService` - 前台服务
- `GatewaySession` - Gateway 会话管理
- `CanvasController` - Canvas 控制
- `VoiceWakeManager` - 语音唤醒

### iOS 主要组件
- OpenClawKit - 共享框架
- Gateway 协议实现
- Bonjour 发现
- Canvas A2UI 支持

### macOS 主要组件
- 菜单栏应用
- Gateway 远程控制
- Voice Wake / PTT
- WebChat 集成

## 关键依赖与配置

### Android 依赖
- Gradle 构建系统
- AndroidX 库
- Kotlin 协程

### iOS/macOS 依赖
- Swift Package Manager
- OpenClawKit 共享框架
- 系统框架：AVFoundation、CoreGraphics 等

### 共享代码
- `apps/shared/OpenClawKit/` - Swift 共享框架
- `apps/shared/MoltbotKit/` - Moltbot 集成

## 数据模型

### Gateway 协议
- WebSocket 通信
- 设备认证和配对
- Canvas A2UI 消息
- 节点命令协议

## 测试与质量

### Android 测试
- 单元测试：`apps/android/app/src/test/`
- 测试运行：`pnpm android:test`

### iOS/macOS 测试
- 通过 Xcode 运行测试

## 子模块索引

| 子模块 | 平台 | 语言 | 职责 |
|--------|------|------|------|
| android | Android | Kotlin | Android 应用 |
| ios | iOS | Swift | iOS 应用 |
| macos | macOS | Swift | macOS 菜单栏应用 |
| shared | iOS/macOS | Swift | 共享代码框架 |

## 功能特性

### 通用功能
- **Canvas 渲染**: A2UI 推送和控制
- **语音交互**: Voice Wake 和 Talk Mode
- **设备配对**: Bonjour/Zeroconf 发现
- **相机 capture**: 拍照和录制
- **屏幕录制**: 屏幕内容共享
- **位置信息**: GPS 坐标获取

### Android 特有
- SMS 集成（可选）
- 前台服务持久化
- 通知管理

### iOS 特有
- TestFlight 分发
- CallKit 集成（未来）
- 后台刷新

### macOS 特有
- 菜单栏控制
- WebChat 集成
- 系统通知
- 快捷键支持

## 常见问题 (FAQ)

### Q: 如何构建 Android 应用？
```bash
cd apps/android && ./gradlew :app:assembleDebug
```

### Q: 如何构建 iOS 应用？
```bash
cd apps/ios && xcodegen generate && xcodebuild ...
```

### Q: 如何调试节点连接？
使用 Gateway 的 `openclaw nodes` 命令查看连接状态。

### Q: Bonjour 发现不工作？
确保设备和 Gateway 在同一网络，并且防火墙允许 mDNS 通信。

## 相关文件清单

### Android
- `apps/android/app/build.gradle.kts`
- `apps/android/app/src/main/AndroidManifest.xml`
- `apps/android/settings.gradle.kts`

### iOS
- `apps/ios/project.yml` (XcodeGen 配置)
- `apps/ios/Sources/`

### macOS
- `apps/macos/Sources/`

### 共享
- `apps/shared/OpenClawKit/`
- `apps/shared/MoltbotKit/`

## 变更记录 (Changelog)

### 2026-02-11 00:58:28
- 初始化 apps 模块文档
- 识别主要平台和入口点
