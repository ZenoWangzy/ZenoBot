[根目录](../../CLAUDE.md) > [src](../) > **security**

# Security

## 模块职责

Security 模块负责 OpenClaw 的安全相关功能，包括：

1. **令牌管理** - 生成和验证认证令牌
2. **加密** - 敏感数据的加密和解密
3. **访问控制** - 权限和角色管理
4. **审计日志** - 安全相关事件的记录

## 入口与启动

- 主入口：`index.ts`
- 安全配置通过 `src/config/` 管理

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | 安全导出 |
| `tokens.ts` | 令牌管理 |
| `crypto.ts` | 加密工具 |
| `access.ts` | 访问控制 |

## 关键依赖与配置

### 安全配置

```json
{
  "security": {
    "tokenExpiry": 3600,
    "maxLoginAttempts": 5,
    "encryptionKey": "..."
  }
}
```

### 凭证存储

- Web 凭证：`~/.openclaw/credentials/`
- 令牌：`~/.openclaw/tokens/`

## 测试与质量

- 测试文件：`*.test.ts`
- 安全测试：`*.security.test.ts`

## 相关文件清单

```
src/security/
├── index.ts           # 安全导出
├── tokens.ts          # 令牌管理
├── crypto.ts          # 加密工具
├── access.ts          # 访问控制
├── audit.ts           # 审计日志
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
