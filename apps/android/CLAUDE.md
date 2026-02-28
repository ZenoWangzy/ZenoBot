[根目录](../../CLAUDE.md) > **apps** > **android**

---

# Android 应用模块

> Android 原生应用

---

## 变更记录 (Changelog)

### 2026-02-11
- 创建模块文档

---

## 模块职责

`apps/android/` 是 OpenClaw 的 Android 原生应用，使用 Kotlin 开发。

---

## 入口与启动

### 主要入口
- `apps/android/app/src/main/java/ai/openclaw/android/MainActivity.kt`

### 构建命令
```bash
# 构建 APK
pnpm android:assemble

# 安装到设备
pnpm android:install

# 运行
pnpm android:run
```

---

## 关键依赖与配置

### 构建工具
- Gradle (Kotlin DSL)

---

## 相关文件清单

```
apps/android/
├── app/
│   └── src/main/
│       ├── java/ai/openclaw/android/
│       │   ├── MainActivity.kt
│       │   ├── NodeApp.kt
│       │   ├── gateway/
│       │   ├── chat/
│       │   ├── voice/
│       │   └── ui/
│       └── res/
├── build.gradle.kts
└── settings.gradle.kts
```
