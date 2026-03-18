[根目录](../../CLAUDE.md) > [src](../) > **acp**

# ACP (Agent Client Protocol)

## 模块职责

ACP 模块实现 Agent Client Protocol，用于与支持 ACP 的客户端通信：

1. **协议实现** - ACP 协议的客户端实现
2. **命令处理** - ACP 命令的发送和接收
3. **控制平面** - ACP 控制平面通信
4. **持久绑定** - 会话的持久化绑定管理

## 入口与启动

- 主入口：`client.ts`
- 命令定义：`commands.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `client.ts` | ACP 客户端 |
| `commands.ts` | 命令定义 |
| `control-plane/` | 控制平面 |
| `event-mapper.ts` | 事件映射 |
| `meta.ts` | 元数据处理 |

### 持久绑定

| 模块 | 职责 |
|------|------|
| `persistent-bindings.lifecycle.ts` | 生命周期管理 |
| `persistent-bindings.resolve.ts` | 绑定解析 |
| `persistent-bindings.route.ts` | 路由绑定 |

## 关键依赖与配置

### 依赖

- `@agentclientprotocol/sdk` - ACP SDK

### 配置

```json
{
  "acp": {
    "enabled": true,
    "endpoint": "..."
  }
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖客户端、命令、绑定

## 相关文件清单

```
src/acp/
├── client.ts                      # ACP 客户端
├── commands.ts                    # 命令定义
├── control-plane/                 # 控制平面
├── event-mapper.ts                # 事件映射
├── meta.ts                        # 元数据
├── conversation-id.ts             # 会话 ID
├── persistent-bindings.*.ts       # 持久绑定
└── *.test.ts                      # 测试
```

## 相关模块

- [extensions/acpx](../../extensions/acpx/) - ACP 扩展插件

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
