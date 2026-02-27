[根目录](../../CLAUDE.md) > **src** > **canvas-host**

---

# Canvas-Host 模块

> Canvas A2UI 渲染服务器

---

## 变更记录 (Changelog)

### 2026-02-11
- 创建模块文档

---

## 模块职责

`src/canvas-host/` 负责：

- **A2UI 渲染**：基于 Agentic UI 协议的 Canvas 渲染
- **静态文件服务**：HTML/JS/CSS 资源
- **WebSocket 通信**：与 A2UI 客户端的实时通信

---

## 入口与启动

### 主要入口
- `src/canvas-host/server.ts` - Canvas 服务器

### 关键文件

| 文件 | 描述 |
|------|------|
| `src/canvas-host/server.ts` | Canvas 服务器 |
| `src/canvas-host/a2ui.ts` | A2UI 渲染器 |
| `src/canvas-host/a2ui/index.html` | HTML 入口 |

---

## 对外接口

### HTTP 端点
- `GET /canvas` - Canvas HTML 页面

### WebSocket
- `/canvas` - A2UI WebSocket 连接

---

## 关键依赖与配置

### 外部依赖
```json
{
  "express": "^5.2.1",
  "ws": "^8.19.0"
}
```

---

## 相关文件清单

```
src/canvas-host/
├── server.ts               # 服务器实现
├── a2ui.ts                 # A2UI 渲染器
└── a2ui/
    ├── index.html          # HTML 入口
    └── a2ui.bundle.js      # 打包的渲染器
```
