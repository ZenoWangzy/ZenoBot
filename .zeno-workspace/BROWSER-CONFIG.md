# Chrome Browser Config for OpenClaw

OpenClaw `user` profile 让 Agent 直接操控本机已登录的真实 Chrome（复用 Cookie / 登录态）。

## 背景：Chrome 146 安全限制

Chrome 146+ 拒绝对**默认** user-data-dir 开启 remote debugging。
解决方案：用非默认路径 `~/chrome-openclaw`，复制登录文件过去。

## openclaw.json 配置

在 `~/.openclaw/openclaw.json` 的 `browser` 节点加入：

```json
{
  "browser": {
    "enabled": true,
    "defaultProfile": "user",
    "profiles": {
      "user": {
        "driver": "existing-session",
        "attachOnly": true,
        "color": "#00AA00",
        "userDataDir": "<填写下方对应平台路径>"
      }
    }
  }
}
```

| 平台    | userDataDir                             |
| ------- | --------------------------------------- |
| macOS   | `/Users/<你的用户名>/chrome-openclaw`   |
| Windows | `C:\Users\<你的用户名>\chrome-openclaw` |

## 一次性初始化（每台机器只做一次）

### macOS

```bash
# 1. 完全退出 Chrome
pkill -9 "Google Chrome"

# 2. 创建新的 chrome-openclaw 目录，复制登录数据
CHROME_SRC="$HOME/Library/Application Support/Google/Chrome"
CHROME_DST="$HOME/chrome-openclaw"
mkdir -p "$CHROME_DST"
cp "$CHROME_SRC/Local State" "$CHROME_DST/"

for p in "Profile 1" "Profile 2" "Profile 3"; do
  mkdir -p "$CHROME_DST/$p"
  for f in Cookies "Login Data" Preferences; do
    [ -f "$CHROME_SRC/$p/$f" ] && cp "$CHROME_SRC/$p/$f" "$CHROME_DST/$p/"
  done
  [ -d "$CHROME_SRC/$p/Local Storage" ] && cp -r "$CHROME_SRC/$p/Local Storage" "$CHROME_DST/$p/"
done
```

### Windows（PowerShell，管理员运行）

```powershell
# 1. 完全退出 Chrome
taskkill /F /IM chrome.exe /T

# 2. 创建新的 chrome-openclaw 目录，复制登录数据
$ChromeSrc = "$env:LOCALAPPDATA\Google\Chrome\User Data"
$ChromeDst = "$env:USERPROFILE\chrome-openclaw"
New-Item -ItemType Directory -Force -Path $ChromeDst

Copy-Item "$ChromeSrc\Local State" "$ChromeDst\"

foreach ($p in @("Profile 1", "Profile 2", "Profile 3", "Default")) {
  if (Test-Path "$ChromeSrc\$p") {
    New-Item -ItemType Directory -Force -Path "$ChromeDst\$p"
    foreach ($f in @("Cookies", "Login Data", "Preferences")) {
      if (Test-Path "$ChromeSrc\$p\$f") { Copy-Item "$ChromeSrc\$p\$f" "$ChromeDst\$p\" }
    }
    if (Test-Path "$ChromeSrc\$p\Local Storage") {
      Copy-Item -Recurse "$ChromeSrc\$p\Local Storage" "$ChromeDst\$p\"
    }
  }
}
```

## 日常启动

每次使用浏览器自动化前运行对应平台的启动脚本：

- **macOS**: `~/.zeno-workspace/scripts/chrome-debug-start.sh`
- **Windows**: `%USERPROFILE%\.zeno-workspace\scripts\chrome-debug-start.bat`

## 注意事项

- `DevToolsActivePort` 文件由启动脚本自动生成（Chrome 146 不再自动写）
- chrome-openclaw 的登录数据与主 Chrome 分离，两者不同步
- 若某个网站要求重新登录，在 chrome-openclaw 里登录一次即可永久保留
