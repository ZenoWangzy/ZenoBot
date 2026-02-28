[根目录](../../CLAUDE.md) > **src** > **plugin-sdk**

---

# Plugin-SDK 模块

> 插件开发 SDK

---

## 变更记录 (Changelog)

### 2026-02-11
- 创建模块文档

---

## 模块职责

`src/plugin-sdk/` 提供开发 OpenClaw 插件（渠道和技能）的 SDK。

---

## 入口与启动

### 关键文件
- `src/plugin-sdk/index.ts` - SDK 主入口
- `src/plugin-sdk/index.test.ts` - SDK 测试

---

## 对外接口

### 导出
```typescript
export * from 'openclaw/plugin-sdk';
```

---

## 相关文件清单

```
src/plugin-sdk/
├── index.ts                # SDK 主入口
└── index.test.ts           # 测试
```
