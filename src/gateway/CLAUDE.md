[根目录](../../CLAUDE.md) > **src** > **gateway**

---

# Gateway 模块

> 网关服务器 - 控制平面核心

---

## 变更记录 (Changelog)

### 2026-02-11
- 创建模块文档

---

## 模块职责

`src/gateway/` 是 OpenClaw 的控制平面核心，负责：

- **WebSocket 服务**：与节点的实时通信
- **协议实现**：Gateway-Node 协议
- **API 端点**：HTTP API 和 OpenAI 兼容 API
- **节点管理**：节点注册、发现、健康检查
- **会话管理**：跨节点的会话协调
- **执行批准**：工具执行的批准流程

---

## 入口与启动

### 主要入口
- `src/gateway/boot.ts` - 网关启动入口

### 启动命令
```bash
# 启动网关
openclaw gateway --port 18789 --verbose

# 开发模式（自动重载）
pnpm gateway:watch
```

### 关键文件

| 文件 | 描述 |
|------|------|
| `src/gateway/boot.ts` | 网关启动入口 |
| `src/gateway/server.ts` | 主服务器实现 |
| `src/gateway/server-http.ts` | HTTP 服务器 |
| `src/gateway/server-discovery.ts` | 节点发现服务 |
| `src/gateway/protocol/` | 协议定义 |

---

## 对外接口

### WebSocket 端点
- `ws://localhost:18789/gateway` - 主 Gateway 连接

### HTTP API
- `GET /health` - 健康检查
- `GET /v1/models` - OpenAI 兼容模型列表
- `POST /v1/chat/completions` - OpenAI 兼容聊天接口

### Discovery (Bonjour/mDNS)
- 服务名: `_openclaw._tcp.local`

---

## 关键依赖与配置

### 外部依赖
```json
{
  "ws": "^8.19.0",
  "express": "^5.2.1",
  "@homebridge/ciao": "^1.3.5"
}
```

### 配置文件
- **存储位置**: `~/.openclaw/gateway/`
- **配置文件**: `~/.openclaw/gateway/config.json`

### 环境变量
- `OPENCLAW_PORT` - 网关端口（默认 18789）
- `OPENCLAW_VERBOSE` - 详细日志

---

## 数据模型

### 协议消息
```typescript
interface GatewayMessage {
  type: string;
  id: string;
  payload: unknown;
}
```

### 节点信息
```typescript
interface NodeInfo {
  id: string;
  type: 'cli' | 'mobile' | 'tui';
  capabilities: string[];
  lastSeen: number;
}
```

---

## 测试与质量

### 测试文件
- `src/gateway/gateway.e2e.test.ts` - E2E 测试
- `src/gateway/server-*.test.ts` - 服务器单元测试

---

## 相关文件清单

```
src/gateway/
├── boot.ts                 # 启动入口
├── server.ts               # 主服务器
├── server-http.ts          # HTTP 服务器
├── server-discovery.ts     # 节点发现
├── server-methods/         # RPC 方法实现
├── protocol/               # 协议定义
│   ├── schema/
│   └── client-info.ts
└── openai-http.ts         # OpenAI 兼容 API
```
