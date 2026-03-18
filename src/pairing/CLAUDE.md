[根目录](../../CLAUDE.md) > [src](../) > **pairing**

# Pairing

## 模块职责

Pairing 模块负责设备配对和认证，包括：

1. **设备配对** - 处理新设备与 Gateway 的配对流程
2. **配对码生成** - 生成和验证配对码
3. **设备信任** - 管理已信任设备列表
4. **配对协议** - 实现安全的配对协议

## 入口与启动

- 主入口：`index.ts`
- 配对流程通过 Gateway 的认证层启动

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | 配对导出 |
| `types.ts` | 配对类型定义 |
| `pairing-code.ts` | 配对码生成 |
| `device-trust.ts` | 设备信任管理 |

## 关键依赖与配置

### 内部依赖

- `src/gateway/` - Gateway 服务器
- `src/config/` - 配置管理
- `src/security/` - 安全相关

### 配对数据

配对数据存储在 `~/.openclaw/devices/` 目录。

## 测试与质量

- 测试文件：`*.test.ts`
- E2E 测试：`*.e2e.test.ts`

## 相关文件清单

```
src/pairing/
├── index.ts           # 配对导出
├── types.ts           # 类型定义
├── pairing-code.ts    # 配对码
├── device-trust.ts    # 设备信任
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
