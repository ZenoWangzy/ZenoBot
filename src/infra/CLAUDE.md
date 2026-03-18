[根目录](../../CLAUDE.md) > [src](../) > **infra**

# Infrastructure

## 模块职责

Infrastructure 模块提供 OpenClaw 的底层基础设施支持，包括：

1. **网络发现** - mDNS/Bonjour 服务发现
2. **进程管理** - 子进程执行和安全
3. **文件系统** - 文件操作和锁定
4. **网络通信** - HTTP、WebSocket、TLS
5. **系统信息** - OS、设备、环境
6. **认证管理** - 配对令牌、设备认证

## 入口与启动

基础设施模块是被动加载的，按需导入使用。

## 对外接口

### 网络发现

| 模块 | 职责 |
|------|------|
| `bonjour.ts` | Bonjour/mDNS 服务发现 |
| `bonjour-discovery.ts` | 发现实现 |
| `tailscale.ts` | Tailscale 集成 |
| `widearea-dns.ts` | 广域 DNS |

### 进程与执行

| 模块 | 职责 |
|------|------|
| `exec-safe-bin-policy.ts` | 安全执行策略 |
| `exec-host.ts` | 执行主机 |
| `exec-obfuscation-detect.ts` | 混淆检测 |
| `node-shell.ts` | Node shell |

### 文件系统

| 模块 | 职责 |
|------|------|
| `file-lock.ts` | 文件锁定 |
| `json-file.ts` | JSON 文件操作 |
| `archive-path.ts` | 归档处理 |
| `home-dir.ts` | 主目录 |

### 网络通信

| 模块 | 职责 |
|------|------|
| `fetch.ts` | HTTP 获取 |
| `tls/gateway.ts` | TLS 网关 |
| `ports-lsof.ts` | 端口检测 |
| `outbound/` | 出站请求 |

### 系统信息

| 模块 | 职责 |
|------|------|
| `os-summary.ts` | OS 摘要 |
| `machine-name.ts` | 机器名 |
| `device-identity.ts` | 设备标识 |
| `env.ts` | 环境变量 |

### 认证

| 模块 | 职责 |
|------|------|
| `pairing-token.ts` | 配对令牌 |
| `device-pairing.ts` | 设备配对 |

### 其他

| 模块 | 职责 |
|------|------|
| `retry.ts` | 重试逻辑 |
| `backoff.ts` | 退避策略 |
| `dedupe.ts` | 去重 |
| `abort-signal.ts` | 中止信号 |
| `heartbeat-*.ts` | 心跳 |
| `format-time/` | 时间格式化 |

## 关键依赖与配置

### 外部依赖

- `@homebridge/ciao` - mDNS
- `node-fetch` - HTTP

### 环境变量

- `OPENCLAW_HOME` - 配置目录（默认 `~/.openclaw`）

## 相关文件清单

```
src/infra/
├── bonjour.ts              # Bonjour 发现
├── bonjour-discovery.ts    # 发现实现
├── tailscale.ts            # Tailscale
├── widearea-dns.ts         # DNS
├── exec-safe-bin-policy.ts # 执行策略
├── exec-host.ts            # 执行主机
├── file-lock.ts            # 文件锁
├── json-file.ts            # JSON 文件
├── fetch.ts                # HTTP 获取
├── tls/                    # TLS
├── ports-lsof.ts           # 端口
├── outbound/               # 出站
├── os-summary.ts           # OS
├── device-identity.ts      # 设备
├── pairing-token.ts        # 配对
├── retry.ts                # 重试
├── backoff.ts              # 退避
├── abort-signal.ts         # 中止
├── heartbeat-*.ts          # 心跳
├── format-time/            # 时间格式
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
