# Win 端 A2A Gateway 配置任务

> 这是给 Claude Code CLI 的自动化执行指令。请按顺序执行以下所有步骤。

## 背景

Mac 端的 OpenClaw A2A Gateway 已配置完成：

- Mac ngrok 公网 URL: `https://ungirlish-superabstract-oma.ngrok-free.dev`
- Mac A2A Token: `f5503eff41eb0c1b9e6f23b4e54fb1cc0e28aceb2e57de40`
- Mac Agent 名称: `ZenoBot-Mac`
- 协议: A2A v0.3.0

你的任务是在 Win 端完成对等配置，实现双向 A2A 通信。

---

## Step 1: 安装 A2A Gateway 插件

```powershell
# 确保目录存在
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.openclaw\workspace\plugins"

# 克隆插件
cd "$env:USERPROFILE\.openclaw\workspace\plugins"
git clone https://github.com/win4r/openclaw-a2a-gateway a2a-gateway
cd a2a-gateway

# 安装依赖（包括 grpc，缺少会导致插件加载失败）
npm install --omit=dev
npm install @grpc/grpc-js

# 注册插件到 OpenClaw
openclaw plugins install "$env:USERPROFILE\.openclaw\workspace\plugins\a2a-gateway"
```

**验证**: `openclaw plugins list` 应该能看到 `a2a-gateway`。

## Step 2: 生成 Win 端安全 Token

```powershell
# 生成随机 Token（如果没有 openssl，用 PowerShell 方式）
$WIN_TOKEN = -join ((48..57) + (97..102) | Get-Random -Count 48 | ForEach-Object {[char]$_})
Write-Host "Win A2A Token: $WIN_TOKEN"
```

**重要**: 记下这个 Token，后面要用，也要告诉 Mac 端。

## Step 3: 配置 A2A Gateway

```powershell
# Agent Card
openclaw config set plugins.entries.a2a-gateway.config.agentCard.name "ZenoBot-Win"
openclaw config set plugins.entries.a2a-gateway.config.agentCard.description "ZenoBot Windows Worker Agent"

# 服务器
openclaw config set plugins.entries.a2a-gateway.config.server.host "0.0.0.0"
openclaw config set plugins.entries.a2a-gateway.config.server.port 18800

# 安全认证（用 Step 2 生成的 Token）
openclaw config set plugins.entries.a2a-gateway.config.security.inboundAuth "bearer"
openclaw config set plugins.entries.a2a-gateway.config.security.token "$WIN_TOKEN"

# 路由到默认 agent
openclaw config set plugins.entries.a2a-gateway.config.routing.defaultAgentId "main"
```

## Step 4: 添加 Mac 为 Peer

```powershell
openclaw config set plugins.entries.a2a-gateway.config.peers '[{"name":"ZenoBot-Mac","agentCardUrl":"https://ungirlish-superabstract-oma.ngrok-free.dev/.well-known/agent-card.json","auth":{"type":"bearer","token":"f5503eff41eb0c1b9e6f23b4e54fb1cc0e28aceb2e57de40"}}]'
```

## Step 5: 重启网关

```powershell
openclaw gateway restart
```

## Step 6: 验证本地 A2A

```powershell
# 等待几秒让网关启动
Start-Sleep -Seconds 5

# 检查 Agent Card
curl -s http://localhost:18800/.well-known/agent-card.json
```

应该返回包含 `"name": "ZenoBot-Win"` 的 JSON。

## Step 7: 安装并启动 ngrok

```powershell
# 安装 ngrok（如果没装）
# 方式 A: winget
winget install ngrok.ngrok

# 方式 B: 手动下载 https://ngrok.com/download

# 配置 authtoken
ngrok config add-authtoken 3AtfeSnDIYRy4Au45jUgCv3PPsr_tMRzeoQRg4JVGbr78xxf

# 启动隧道（如果系统有代理，需要先关闭代理或清除环境变量）
$env:HTTP_PROXY = ""
$env:HTTPS_PROXY = ""
$env:ALL_PROXY = ""
ngrok http 18800
```

**重要**: ngrok 启动后会显示一个公网 URL（类似 `https://xxxxx.ngrok-free.app`）。

## Step 8: 回报信息

配置完成后，把以下两个信息告诉 Mac 端（用户）：

1. **Win ngrok 公网 URL**: `https://xxxxx.ngrok-free.app`（ngrok 启动后显示的）
2. **Win A2A Token**: Step 2 生成的 Token

Mac 端需要这两个值来把 Win 添加为 Peer，完成双向配对。

---

## 验证双向通信（Mac 端添加 Win Peer 后）

```powershell
# 从 Win 发消息给 Mac
node "$env:USERPROFILE\.openclaw\workspace\plugins\a2a-gateway\skill\scripts\a2a-send.mjs" --peer-url https://ungirlish-superabstract-oma.ngrok-free.dev --token f5503eff41eb0c1b9e6f23b4e54fb1cc0e28aceb2e57de40 --message "Hello from ZenoBot-Win!"
```

如果返回 Mac Agent 的回复，说明 A2A 双向通信成功。

---

## 故障排查

| 问题                                              | 解决                                                        |
| ------------------------------------------------- | ----------------------------------------------------------- |
| 插件加载失败 `Cannot find module '@grpc/grpc-js'` | 在插件目录执行 `npm install @grpc/grpc-js`                  |
| Agent Card 返回 404                               | 检查 `openclaw plugins list`，确认插件已加载                |
| ngrok 报 proxy 错误                               | 清除 `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY` 环境变量后重试  |
| 18800 端口连不上                                  | 执行 `openclaw gateway restart`                             |
| Peer 认证失败                                     | 确认 peer 配置里的 token 和对方的 `security.token` 完全一致 |
