[根目录](../../CLAUDE.md) > [src](../) > **auto-reply**

# Auto-Reply

## 模块职责

Auto-Reply 模块负责自动回复功能，包括：

1. **命令检测** - 检测消息中的命令
2. **命令注册** - 注册和管理可用命令
3. **权限控制** - 命令执行的权限验证
4. **分块处理** - 长消息的分块发送

## 入口与启动

- 主入口：`index.ts` 或通过通道模块集成

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `command-detection.ts` | 命令检测 |
| `commands-registry.data.ts` | 命令注册数据 |
| `command-auth.ts` | 命令授权 |
| `command-control.ts` | 命令控制 |
| `chunk.ts` | 消息分块 |

### 命令参数

| 模块 | 职责 |
|------|------|
| `commands-args.ts` | 命令参数解析 |

## 关键依赖与配置

### 配置

```json
{
  "autoReply": {
    "enabled": true,
    "prefix": "!",
    "maxChunkSize": 4000
  }
}
```

### 权限级别

- `owner` - 所有者（完全权限）
- `admin` - 管理员
- `user` - 普通用户

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖命令检测、参数解析、分块

## 相关文件清单

```
src/auto-reply/
├── command-detection.ts           # 命令检测
├── commands-registry.data.ts      # 命令注册
├── command-auth.ts                # 授权
├── command-control.ts             # 控制
├── commands-args.ts               # 参数解析
├── chunk.ts                       # 消息分块
└── *.test.ts                      # 测试
```

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
