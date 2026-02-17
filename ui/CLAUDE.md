[根目录](../CLAUDE.md) > **ui**

# ui 模块文档

## 模块职责

`ui/` 是 OpenClaw 的 Web 控制界面，提供：

- 聊天界面
- 配置管理
- 渠道管理
- 日志查看
- 控制面板

## 入口与启动

### 开发模式

```bash
pnpm ui:dev
```

### 构建

```bash
pnpm ui:build
```

### 入口文件

- **`src/main.ts`** - 主入口
- **`index.html`** - HTML 模板

## 对外接口

### 主要控制器

- `app.ts` - 主应用
- `navigation.ts` - 路由导航
- `controllers/chat.ts` - 聊天控制器
- `controllers/channels.ts` - 渠道控制器
- `controllers/config.ts` - 配置控制器
- `controllers/agents.ts` - 代理控制器

### 视图路由

- `/` - 聊天界面
- `/channels` - 渠道管理
- `/config` - 配置
- `/agents` - 代理管理
- `/logs` - 日志
- `/wizard` - 向导

## 关键依赖与配置

### 核心依赖

- 纯 JavaScript/TypeScript（无框架）
- 自定义组件系统
- Markdown 渲染
- 实时 WebSocket 连接

### 配置文件

- `package.json` - NPM 包配置
- `vite.config.ts` - Vite 构建配置（如果使用）

## 数据模型

### 主要类型

- `ChatMessage` - 聊天消息
- `ChannelStatus` - 渠道状态
- `AgentConfig` - 代理配置
- `ConfigValue` - 配置值

### 状态管理

- `app-view-state.ts` - 视图状态
- `app-scroll.ts` - 滚动状态
- `app-settings.ts` - 应用设置

## 测试与质量

### 测试框架

- Vitest + Playwright (浏览器测试)
- 截图测试：`src/ui/__screenshots__/`

### 测试命令

```bash
pnpm test:ui
```

## 子模块索引

| 子模块           | 职责       |
| ---------------- | ---------- |
| ui/app.ts        | 主应用逻辑 |
| ui/navigation.ts | 路由导航   |
| ui/controllers/  | 各种控制器 |
| ui/chat/         | 聊天功能   |
| ui/components/   | UI 组件    |
| ui/styles/       | 样式文件   |

## 功能特性

### 聊天功能

- 实时消息流
- Markdown 渲染
- 代码高亮
- 工具卡片显示
- 分组消息视图

### 配置管理

- 动态表单生成
- 配置验证
- 实时预览

### 渠道管理

- 渠道状态监控
- 添加/删除渠道
- 渠道测试

### 日志查看

- 实时日志流
- 日志过滤
- 日志搜索

## 常见问题 (FAQ)

### Q: 如何修改样式？

编辑 `src/styles/` 下的 CSS 文件。

### Q: 如何添加新页面？

在 `controllers/` 中添加新控制器，并在 `navigation.ts` 中注册路由。

### Q: 如何调试？

使用浏览器开发者工具，或使用 `pnpm ui:dev` 启动开发服务器。

## 相关文件清单

### 入口

- `src/main.ts`
- `index.html`

### 核心

- `src/ui/app.ts`
- `src/ui/navigation.ts`
- `src/ui/presenter.ts`

### 控制器

- `src/ui/controllers/chat.ts`
- `src/ui/controllers/channels.ts`
- `src/ui/controllers/config.ts`

### 样式

- `src/styles.css`
- `src/styles/chat.css`
- `src/styles/components.css`

## 变更记录 (Changelog)

### 2026-02-11 00:58:28

- 初始化 ui 模块文档
- 识别主要组件和控制器
