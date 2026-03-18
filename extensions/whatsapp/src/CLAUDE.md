[根目录](../../CLAUDE.md) > [src](../) > **whatsapp**

# WhatsApp

## 模块职责

WhatsApp 模块是 WhatsApp Web 通道的实现（基于 Baileys），负责：

1. **连接管理** - WhatsApp Web 连接的建立和维护
2. **消息收发** - 发送和接收 WhatsApp 消息
3. **媒体处理** - 图片、视频、文档等媒体消息
4. **状态同步** - 同步在线状态和已读回执

## 入口与启动

- 主入口：`index.ts`
- 连接通过二维码扫描建立

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | WhatsApp 导出 |
| `connection.ts` | 连接管理 |
| `messages.ts` | 消息处理 |
| `media.ts` | 媒体处理 |

## 关键依赖与配置

### 依赖

- `@whiskeysockets/baileys` - WhatsApp Web 协议实现

### 配置

```json
{
  "channels": {
    "whatsapp": {
      "enabled": true,
      "sessionPath": "~/.openclaw/sessions/whatsapp"
    }
  }
}
```

## 数据存储

- 会话数据：`~/.openclaw/sessions/whatsapp/`
- 认证状态：`~/.openclaw/sessions/whatsapp/auth/`

## 测试与质量

- 测试文件：`*.test.ts`
- Live 测试需要真实 WhatsApp 账号

## 相关文件清单

```
src/whatsapp/
├── index.ts           # WhatsApp 导出
├── connection.ts      # 连接管理
├── messages.ts        # 消息处理
├── media.ts           # 媒体处理
├── types.ts           # 类型定义
└── *.test.ts          # 测试
```

## 相关模块

- [src/web/](../web/CLAUDE.md) - Web 通道
- [extensions/whatsapp](../../extensions/whatsapp/) - WhatsApp 插件

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
