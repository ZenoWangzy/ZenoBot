[根目录](../../CLAUDE.md) > **src** > **acp**

---

# ACP 模块

> Agent Client Protocol 实现

---

## 变更记录 (Changelog)

### 2026-02-11
- 创建模块文档

---

## 模块职责

`src/acp/` 实现 Agent Client Protocol (ACP)，是 OpenClaw 与 Agent 之间的标准化通信协议。

---

## 入口与启动

### 关键文件

| 文件 | 描述 |
|------|------|
| `src/acp/client.ts` | ACP 客户端 |
| `src/acp/server.ts` | ACP 服务器 |
| `src/acp/types.ts` | 类型定义 |

---

## 关键依赖与配置

### 外部依赖
```json
{
  "@agentclientprotocol/sdk": "0.14.1"
}
```

---

## 相关文件清单

```
src/acp/
├── client.ts               # ACP 客户端
├── server.ts               # ACP 服务器
├── session.ts              # 会话管理
├── types.ts                # 类型定义
└── event-mapper.ts         # 事件映射
```
