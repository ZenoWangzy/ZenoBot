[根目录](../../CLAUDE.md) > [src](../) > **secrets**

# Secrets

## 模块职责

Secrets 模块负责敏感信息的管理，包括：

1. **密钥存储** - 安全存储 API 密钥和令牌
2. **配置管理** - 敏感配置的处理
3. **审计** - 密钥使用和变更的审计
4. **认证配置** - 认证相关的配置管理

## 入口与启动

- 主入口：`apply.ts`
- 配置命令：`command-config.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `apply.ts` | 密钥应用 |
| `audit.ts` | 审计日志 |
| `command-config.ts` | 配置命令 |
| `config-io.ts` | 配置 IO |
| `configure.ts` | 配置逻辑 |

### 存储路径

| 模块 | 职责 |
|------|------|
| `auth-store-paths.ts` | 认证存储路径 |
| `auth-profiles-scan.ts` | 认证配置扫描 |

## 关键依赖与配置

### 存储位置

- 凭证：`~/.openclaw/credentials/`
- 认证配置：`~/.openclaw/auth/`

### 安全措施

- 敏感数据不记录到日志
- 配置文件权限限制
- 审计所有密钥访问

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖存储、审计、配置

## 相关文件清单

```
src/secrets/
├── apply.ts                       # 密钥应用
├── audit.ts                       # 审计
├── command-config.ts              # 配置命令
├── config-io.ts                   # 配置 IO
├── configure.ts                   # 配置逻辑
├── auth-store-paths.ts            # 存储路径
├── auth-profiles-scan.ts          # 配置扫描
└── *.test.ts                      # 测试
```

## 相关模块

- [src/security/](../security/CLAUDE.md) - 安全模块
- [src/config/](../config/CLAUDE.md) - 配置管理

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档
