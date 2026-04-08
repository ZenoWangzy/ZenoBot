[根目录](../../CLAUDE.md) > [src](../) > **browser**

# Browser

## 模块职责

Browser 模块负责浏览器自动化和集成，包括：

1. **CDP 协议** - Chrome DevTools Protocol 集成
2. **浏览器桥接** - 与浏览器的通信桥接
3. **代理支持** - 浏览器代理配置
4. **认证管理** - 浏览器认证注册

## 入口与启动

- 主入口：`bridge-server.ts`
- CDP 集成：`cdp.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `bridge-server.ts` | 桥接服务器 |
| `cdp.ts` | CDP 协议实现 |
| `cdp-proxy-bypass.ts` | 代理绕过 |
| `browser-utils.ts` | 浏览器工具 |

### CDP 相关

| 模块 | 职责 |
|------|------|
| `cdp.helpers.ts` | CDP 辅助函数 |
| `cdp-timeouts.ts` | CDP 超时处理 |

## 关键依赖与配置

### 依赖

- `playwright-core` - Playwright 核心库

### 配置

```json
{
  "browser": {
    "enabled": true,
    "headless": true,
    "proxy": {
      "enabled": false,
      "server": "..."
    }
  }
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖 CDP、桥接、代理

## 相关文件清单

```
src/browser/
├── bridge-server.ts               # 桥接服务器
├── bridge-auth-registry.ts        # 认证注册
├── cdp.ts                         # CDP 实现
├── cdp.helpers.ts                 # CDP 辅助
├── cdp-proxy-bypass.ts            # 代理绕过
├── cdp-timeouts.ts                # 超时处理
├── browser-utils.ts               # 浏览器工具
└── *.test.ts                      # 测试
```

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
