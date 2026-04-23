[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "install-headless", "uninstall", "uninstall-headless", "status", "run", "help")]
    [string]$Action = "help",

    [Parameter()]
    [ValidateRange(1, 60)]
    [int]$IntervalMinutes = 2,

    [Parameter()]
    [string]$TaskName = "OpenClaw Gateway Watchdog",

    [Parameter()]
    [ValidateRange(1, 20)]
    [int]$ClaudeFailureThreshold = 3,

    [Parameter()]
    [ValidateRange(30, 3600)]
    [int]$ClaudeTimeoutSeconds = 300,

    [Parameter()]
    [ValidateRange(1, 1440)]
    [int]$ClaudeCooldownMinutes = 30,

    [Parameter()]
    [ValidateRange(5, 120)]
    [int]$PostRepairWaitSeconds = 15,

    [Parameter()]
    [switch]$NoClaude,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Headless,

    [Parameter()]
    [string]$OpenClawHome = $env:USERPROFILE,

    [Parameter()]
    [string]$OpenClawCommandPath,

    [Parameter()]
    [string]$ClaudeCommandPath,

    [Parameter()]
    [string]$HeadlessTaskBaseName = "OpenClaw Gateway Headless"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:ScriptPath = $MyInvocation.MyCommand.Path
$Script:ScriptDir = Split-Path -Parent $Script:ScriptPath
$defaultStateRoot = Join-Path $env:USERPROFILE ".openclaw\watchdog"
$Script:StateRoot = if ($env:OPENCLAW_WATCHDOG_STATE_DIR) {
    $env:OPENCLAW_WATCHDOG_STATE_DIR
} else {
    $defaultStateRoot
}
$Script:StatePath = Join-Path $Script:StateRoot "state.json"
$Script:LockPath = Join-Path $Script:StateRoot "watchdog.lock"
$Script:LogPath = Join-Path $Script:StateRoot "watchdog.log"
$Script:OpenClawCommand = $null
$Script:ClaudeCommand = $null
$Script:EffectiveOpenClawHome = if ($env:OPENCLAW_HOME) { $env:OPENCLAW_HOME } else { $OpenClawHome }

if ($Action -eq "install-headless" -or $Action -eq "uninstall-headless") {
    $Headless = $true
}

function Get-HeadlessGatewayTaskName {
    return "$HeadlessTaskBaseName Gateway"
}

function Get-HeadlessWatchdogTaskName {
    return "$HeadlessTaskBaseName Watchdog"
}

function Get-HeadlessStateDir {
    return Join-Path $Script:EffectiveOpenClawHome ".openclaw"
}

function Get-HeadlessWatchdogDir {
    return Join-Path (Get-HeadlessStateDir) "watchdog"
}

function Get-HeadlessGatewayWrapperPath {
    return Join-Path (Get-HeadlessWatchdogDir) "openclaw-headless-gateway.cmd"
}

function Get-HeadlessWatchdogWrapperPath {
    return Join-Path (Get-HeadlessWatchdogDir) "openclaw-headless-watchdog.cmd"
}

function Ensure-StateRoot {
    New-Item -ItemType Directory -Path $Script:StateRoot -Force | Out-Null
}

function Log {
    param([string]$Message)

    Ensure-StateRoot
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Add-Content -Path $Script:LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-DefaultState {
    return @{
        consecutiveGatewayFailures = 0
        consecutiveDiscordFailures = 0
        lastClaudeAt = $null
        lastClaudeReason = $null
        lastRunAt = $null
        lastHealthyAt = $null
    }
}

function Load-State {
    Ensure-StateRoot
    if (-not (Test-Path $Script:StatePath)) {
        return Get-DefaultState
    }

    try {
        $raw = Get-Content -Path $Script:StatePath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return Get-DefaultState
        }
        $parsed = $raw | ConvertFrom-Json
        $state = Get-DefaultState
        foreach ($property in $parsed.PSObject.Properties) {
            $state[$property.Name] = $property.Value
        }
        return $state
    } catch {
        Log "State file unreadable, resetting it: $_"
        return Get-DefaultState
    }
}

function Save-State {
    param([hashtable]$State)

    Ensure-StateRoot
    $State | ConvertTo-Json -Depth 8 | Set-Content -Path $Script:StatePath -Encoding UTF8
}

function Acquire-Lock {
    Ensure-StateRoot
    if (Test-Path $Script:LockPath) {
        try {
            $age = (Get-Date) - (Get-Item $Script:LockPath).LastWriteTime
            if ($age.TotalMinutes -lt 10) {
                Log "Another watchdog run is still active; skipping this tick."
                exit 0
            }
        } catch {
            # Ignore stale lock inspection failure and continue to replace it.
        }
        Remove-Item -Path $Script:LockPath -Force -ErrorAction SilentlyContinue
    }

    Set-Content -Path $Script:LockPath -Value $PID -Encoding UTF8
}

function Release-Lock {
    Remove-Item -Path $Script:LockPath -Force -ErrorAction SilentlyContinue
}

function Resolve-OpenClawCommand {
    if ($null -ne $Script:OpenClawCommand) {
        return $Script:OpenClawCommand
    }

    $override = $OpenClawCommandPath
    if ([string]::IsNullOrWhiteSpace($override)) {
        $override = $env:OPENCLAW_WATCHDOG_OPENCLAW_CMD
    }
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        $Script:OpenClawCommand = $override
        return $Script:OpenClawCommand
    }

    $cmd = Get-Command openclaw -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        throw "openclaw command not found in PATH."
    }

    $Script:OpenClawCommand = $cmd.Source
    return $Script:OpenClawCommand
}

function Resolve-ClaudeCommand {
    if ($null -ne $Script:ClaudeCommand) {
        return $Script:ClaudeCommand
    }

    $override = $ClaudeCommandPath
    if ([string]::IsNullOrWhiteSpace($override)) {
        $override = $env:OPENCLAW_WATCHDOG_CLAUDE_CMD
    }
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        $Script:ClaudeCommand = $override
        return $Script:ClaudeCommand
    }

    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        return $null
    }

    $Script:ClaudeCommand = $cmd.Source
    return $Script:ClaudeCommand
}

function Invoke-CommandCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $FilePath @Arguments 2>&1 | Out-String
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    return @{
        exitCode = $LASTEXITCODE
        output = $output.Trim()
    }
}

function Invoke-OpenClaw {
    param([string[]]$Arguments)

    $binary = Resolve-OpenClawCommand
    Log ("Running openclaw " + ($Arguments -join " "))
    return Invoke-CommandCapture -FilePath $binary -Arguments $Arguments
}

function Invoke-Schtasks {
    param(
        [string[]]$Arguments,
        [switch]$IgnoreErrors
    )

    Log ("Running schtasks " + ($Arguments -join " "))
    $result = Invoke-CommandCapture -FilePath "schtasks.exe" -Arguments $Arguments
    if (-not $IgnoreErrors -and $result.exitCode -ne 0) {
        throw "schtasks failed: $($result.output)"
    }
    return $result
}

function Get-GatewayStatus {
    $result = Invoke-OpenClaw -Arguments @("gateway", "status", "--json")
    if ($result.exitCode -ne 0) {
        throw "openclaw gateway status failed: $($result.output)"
    }

    try {
        return @{
            raw = $result.output
            parsed = ($result.output | ConvertFrom-Json)
        }
    } catch {
        throw "openclaw gateway status returned invalid JSON: $($result.output)"
    }
}

function Get-ChannelsStatusProbe {
    $result = Invoke-OpenClaw -Arguments @("channels", "status", "--probe")
    return @{
        exitCode = $result.exitCode
        raw = $result.output
    }
}

function Get-GatewayPort {
    param([object]$GatewayStatus)

    $port = $GatewayStatus.gateway.port
    if ($null -eq $port) {
        return 18789
    }
    return [int]$port
}

function Ensure-HeadlessWrapper {
    param(
        [ValidateSet("gateway", "watchdog")]
        [string]$Kind,

        [object]$GatewayStatus
    )

    $watchdogDir = Get-HeadlessWatchdogDir
    $stateDir = Get-HeadlessStateDir
    $configPath = Join-Path $stateDir "openclaw.json"
    $wrapperPath = if ($Kind -eq "gateway") {
        Get-HeadlessGatewayWrapperPath
    } else {
        Get-HeadlessWatchdogWrapperPath
    }
    $openclawPath = Resolve-OpenClawCommand
    $claudePath = Resolve-ClaudeCommand
    $gatewayPort = Get-GatewayPort -GatewayStatus $GatewayStatus
    $watchdogTaskName = Get-HeadlessWatchdogTaskName
    $gatewayTaskName = Get-HeadlessGatewayTaskName

    $lines = @(
        "@echo off",
        "setlocal",
        "set `"USERPROFILE=$Script:EffectiveOpenClawHome`"",
        "set `"HOME=$Script:EffectiveOpenClawHome`"",
        "set `"OPENCLAW_HOME=$Script:EffectiveOpenClawHome`"",
        "set `"OPENCLAW_STATE_DIR=$stateDir`"",
        "set `"OPENCLAW_CONFIG_PATH=$configPath`"",
        "set `"OPENCLAW_WATCHDOG_STATE_DIR=$watchdogDir`"",
        "set `"OPENCLAW_WATCHDOG_OPENCLAW_CMD=$openclawPath`""
    )
    if (-not [string]::IsNullOrWhiteSpace($claudePath)) {
        $lines += "set `"OPENCLAW_WATCHDOG_CLAUDE_CMD=$claudePath`""
    }
    $openclawDir = Split-Path -Parent $openclawPath
    $lines += "set `"PATH=$openclawDir;%PATH%`""

    if ($Kind -eq "gateway") {
        $lines += "`"$openclawPath`" gateway --port $gatewayPort"
    } else {
        $taskArg = "-NoProfile -ExecutionPolicy Bypass -File `"$Script:ScriptPath`" run -Headless -TaskName `"$watchdogTaskName`" -HeadlessTaskBaseName `"$HeadlessTaskBaseName`" -IntervalMinutes $IntervalMinutes -ClaudeFailureThreshold $ClaudeFailureThreshold -ClaudeTimeoutSeconds $ClaudeTimeoutSeconds -ClaudeCooldownMinutes $ClaudeCooldownMinutes -PostRepairWaitSeconds $PostRepairWaitSeconds -OpenClawHome `"$Script:EffectiveOpenClawHome`" -OpenClawCommandPath `"$openclawPath`""
        if (-not [string]::IsNullOrWhiteSpace($claudePath)) {
            $taskArg += " -ClaudeCommandPath `"$claudePath`""
        }
        if ($NoClaude) {
            $taskArg += " -NoClaude"
        }
        $lines += "PowerShell.exe $taskArg"
    }

    if ($DryRun) {
        Log "DRY RUN: would write $Kind wrapper to $wrapperPath"
        return $wrapperPath
    }

    New-Item -ItemType Directory -Path $watchdogDir -Force | Out-Null
    Set-Content -Path $wrapperPath -Value ($lines -join "`r`n") -Encoding ASCII
    return $wrapperPath
}

function Stop-HeadlessGatewayProcess {
    param([object]$GatewayStatus)

    $listeners = @($GatewayStatus.port.listeners)
    foreach ($listener in $listeners) {
        if ($null -eq $listener.pid) {
            continue
        }
        $pid = [int]$listener.pid
        if ($DryRun) {
            Log "DRY RUN: would stop headless gateway pid $pid"
            continue
        }
        try {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            Log "Stopped headless gateway pid $pid"
        } catch {
            Log "Failed to stop headless gateway pid ${pid}: $_"
        }
    }
}

function Invoke-HeadlessGatewayTask {
    param(
        [ValidateSet("start", "restart")]
        [string]$Mode,

        [object]$GatewayStatus
    )

    $gatewayTask = Get-HeadlessGatewayTaskName
    if ($Mode -eq "restart") {
        Stop-HeadlessGatewayProcess -GatewayStatus $GatewayStatus
        if (-not $DryRun) {
            Invoke-Schtasks -Arguments @("/End", "/TN", $gatewayTask) -IgnoreErrors | Out-Null
        }
    }

    if ($DryRun) {
        Log "DRY RUN: would run headless gateway task '$gatewayTask'"
        return
    }
    Invoke-Schtasks -Arguments @("/Run", "/TN", $gatewayTask) -IgnoreErrors | Out-Null
}

function Test-DiscordHealthy {
    param([string]$ProbeOutput)

    if ([string]::IsNullOrWhiteSpace($ProbeOutput)) {
        return $false
    }
    if ($ProbeOutput -match "(?im)Gateway not reachable") {
        return $false
    }
    return $ProbeOutput -match "(?im)^\s*-\s*Discord[^\r\n]*:\s.*\b(connected|ready)\b"
}

function Test-GatewayHttpHealthy {
    param([int]$Port = 18789)

    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $body = $response.Content | ConvertFrom-Json
        return ($body.ok -eq $true)
    } catch {
        return $false
    }
}

function Invoke-RepairCommand {
    param(
        [string[]]$Arguments,
        [string]$Reason
    )

    if ($DryRun) {
        Log "DRY RUN: would run openclaw $($Arguments -join ' ') for $Reason"
        return @{
            exitCode = 0
            output = "dry-run"
        }
    }

    $result = Invoke-OpenClaw -Arguments $Arguments
    if ($result.exitCode -ne 0) {
        Log "Repair command failed for ${Reason}: $($result.output)"
    }
    return $result
}

function Wait-ForRepair {
    if ($DryRun) {
        return
    }
    Log "Waiting $PostRepairWaitSeconds second(s) for the gateway to settle."
    Start-Sleep -Seconds $PostRepairWaitSeconds
}

function Invoke-DeterministicGatewayRepair {
    param([object]$GatewayStatus)

    $serviceLoaded = [bool]$GatewayStatus.service.loaded
    $rpcOk = [bool]$GatewayStatus.rpc.ok

    if ($Headless) {
        if (-not $rpcOk) {
            Log "Headless mode: gateway RPC probe failed; restarting the headless gateway task."
            Invoke-HeadlessGatewayTask -Mode "restart" -GatewayStatus $GatewayStatus
            Wait-ForRepair
            return "headless-restart"
        }
        return "none"
    }

    if (-not $serviceLoaded) {
        Log "Gateway service is missing; installing it."
        Invoke-RepairCommand -Arguments @("gateway", "install") -Reason "missing gateway service" | Out-Null
        Wait-ForRepair
        return "install"
    }

    if (-not $rpcOk) {
        Log "Gateway service exists but RPC probe failed; restarting it."
        Invoke-RepairCommand -Arguments @("gateway", "restart") -Reason "failed gateway rpc probe" | Out-Null
        Wait-ForRepair
        return "restart"
    }

    return "none"
}

function Invoke-DeterministicDiscordRepair {
    if ($Headless) {
        Log "Headless mode: Discord is unhealthy; restarting the headless gateway task once."
        $gatewayStatus = (Get-GatewayStatus).parsed
        Invoke-HeadlessGatewayTask -Mode "restart" -GatewayStatus $gatewayStatus
        Wait-ForRepair
        return
    }

    Log "Gateway is up but Discord is not connected/ready; restarting gateway once."
    Invoke-RepairCommand -Arguments @("gateway", "restart") -Reason "discord unhealthy" | Out-Null
    Wait-ForRepair
}

function Get-DiagnosticsSnapshot {
    param(
        [object]$GatewayStatus,
        [string]$ChannelsOutput,
        [hashtable]$State
    )

    $latestLogs = ""
    try {
        $logDir = Join-Path $env:USERPROFILE ".openclaw\logs"
        if (Test-Path $logDir) {
            $latest = Get-ChildItem -Path $logDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 2
            if ($latest) {
                $chunks = @()
                foreach ($file in $latest) {
                    $tail = Get-Content -Path $file.FullName -Tail 40 -ErrorAction SilentlyContinue | Out-String
                    $chunks += "### $($file.Name)`n$tail"
                }
                $latestLogs = $chunks -join "`n"
            }
        }
    } catch {
        $latestLogs = "Unable to read logs: $_"
    }

    return @"
OpenClaw watchdog on Windows needs remediation.

Goal:
- Restore the local OpenClaw gateway
- Restore Discord to connected/ready
- Prefer deterministic commands over exploratory changes
- Avoid destructive actions and do not modify unrelated files

Current state:
$($State | ConvertTo-Json -Depth 8)

Gateway status JSON:
$($GatewayStatus | ConvertTo-Json -Depth 8)

channels status --probe:
$ChannelsOutput

Recent logs:
$latestLogs

Preferred repair order:
1. `openclaw gateway status`
2. `openclaw channels status --probe`
3. If service is missing, run `openclaw gateway install`
4. If RPC probe fails, run `openclaw gateway restart`
5. If config/service mismatch appears, run `openclaw doctor`
6. Re-check until gateway RPC is healthy and Discord is connected/ready
"@
}

function Invoke-ClaudeRepair {
    param(
        [string]$Reason,
        [object]$GatewayStatus,
        [string]$ChannelsOutput,
        [hashtable]$State
    )

    if ($NoClaude) {
        Log "Claude escalation is disabled; skipping escalation for $Reason."
        return
    }

    $claude = Resolve-ClaudeCommand
    if ([string]::IsNullOrWhiteSpace($claude)) {
        Log "Claude CLI is not installed; skipping escalation for $Reason."
        return
    }

    if ($State.lastClaudeAt) {
        try {
            $lastClaudeAt = [datetime]$State.lastClaudeAt
            if (((Get-Date) - $lastClaudeAt).TotalMinutes -lt $ClaudeCooldownMinutes) {
                Log "Claude escalation cooldown is active; skipping escalation for $Reason."
                return
            }
        } catch {
            # Ignore malformed timestamp and continue.
        }
    }

    $prompt = Get-DiagnosticsSnapshot -GatewayStatus $GatewayStatus -ChannelsOutput $ChannelsOutput -State $State
    Log "Escalating to Claude Code CLI for $Reason."

    if ($DryRun) {
        Log "DRY RUN: would run claude -p <diagnostics prompt>"
        return
    }

    $job = Start-Job -ScriptBlock {
        param($commandPath, $promptText)
        & $commandPath -p $promptText 2>&1 | Out-String
    } -ArgumentList $claude, $prompt

    $completed = Wait-Job -Job $job -Timeout $ClaudeTimeoutSeconds
    if ($null -eq $completed) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
        Log "Claude Code CLI timed out after $ClaudeTimeoutSeconds second(s)."
        return
    }

    try {
        $result = Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-String
        $preview = $result.Trim()
        if ($preview.Length -gt 300) {
            $preview = $preview.Substring(0, 300)
        }
        Log "Claude Code CLI completed. Preview: $preview"
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $State.lastClaudeAt = (Get-Date).ToString("o")
    $State.lastClaudeReason = $Reason
}

function Invoke-WatchdogRun {
    Acquire-Lock
    try {
        $state = Load-State
        $state.lastRunAt = (Get-Date).ToString("o")
        Save-State -State $state

        $gatewayStatus = Get-GatewayStatus
        $gatewayParsed = $gatewayStatus.parsed
        $serviceLoaded = [bool]$gatewayParsed.service.loaded
        $rpcOk = [bool]$gatewayParsed.rpc.ok
        $gatewayHealthy = if ($Headless) { $rpcOk } else { $serviceLoaded -and $rpcOk }

        if (-not $gatewayHealthy) {
            $repairAction = Invoke-DeterministicGatewayRepair -GatewayStatus $gatewayParsed
            $gatewayStatus = Get-GatewayStatus
            $gatewayParsed = $gatewayStatus.parsed
            $serviceLoaded = [bool]$gatewayParsed.service.loaded
            $rpcOk = [bool]$gatewayParsed.rpc.ok
            $gatewayHealthy = if ($Headless) { $rpcOk } else { $serviceLoaded -and $rpcOk }

            if (-not $gatewayHealthy) {
                $state.consecutiveGatewayFailures = [int]$state.consecutiveGatewayFailures + 1
                $state.consecutiveDiscordFailures = 0
                Log "Gateway is still unhealthy after deterministic repair ($repairAction). Failure count: $($state.consecutiveGatewayFailures)"
                if ([int]$state.consecutiveGatewayFailures -ge $ClaudeFailureThreshold) {
                    Invoke-ClaudeRepair -Reason "gateway unhealthy after deterministic repair" -GatewayStatus $gatewayParsed -ChannelsOutput "" -State $state
                }
                Save-State -State $state
                return
            }

            Log "Gateway recovered after deterministic repair ($repairAction)."
        }

        $state.consecutiveGatewayFailures = 0

        $channelsProbe = Get-ChannelsStatusProbe
        $discordHealthy = Test-DiscordHealthy -ProbeOutput $channelsProbe.raw
        Log ("Discord healthy check result: " + $discordHealthy)

        if (-not $discordHealthy) {
            $httpHealthy = Test-GatewayHttpHealthy -Port (Get-GatewayPort -GatewayStatus $gatewayParsed)
            Log ("HTTP health fallback check: " + $httpHealthy)
            if ($httpHealthy) {
                Log "Probe reported Gateway not reachable but HTTP health endpoint is OK. Skipping Discord repair to avoid unnecessary restart."
                $discordHealthy = $true
            } else {
                Invoke-DeterministicDiscordRepair
                $channelsProbe = Get-ChannelsStatusProbe
                $discordHealthy = Test-DiscordHealthy -ProbeOutput $channelsProbe.raw
            }
        }

        if ($discordHealthy) {
            $state.consecutiveDiscordFailures = 0
            $state.lastHealthyAt = (Get-Date).ToString("o")
            Log "Gateway RPC and Discord probe are healthy."
        } else {
            $state.consecutiveDiscordFailures = [int]$state.consecutiveDiscordFailures + 1
            Log "Discord is still not connected/ready after repair. Failure count: $($state.consecutiveDiscordFailures)"
            if ([int]$state.consecutiveDiscordFailures -ge $ClaudeFailureThreshold) {
                Invoke-ClaudeRepair -Reason "discord unhealthy after gateway restart" -GatewayStatus $gatewayParsed -ChannelsOutput $channelsProbe.raw -State $state
            }
        }

        Save-State -State $state
    } finally {
        Release-Lock
    }
}

function Install-WatchdogTask {
    $userId = if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $env:USERNAME }
    $taskCommand = "PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Script:ScriptPath`" run -IntervalMinutes $IntervalMinutes -ClaudeFailureThreshold $ClaudeFailureThreshold -ClaudeTimeoutSeconds $ClaudeTimeoutSeconds -ClaudeCooldownMinutes $ClaudeCooldownMinutes -PostRepairWaitSeconds $PostRepairWaitSeconds"
    if ($NoClaude) {
        $taskCommand += " -NoClaude"
    }

    Log "Ensuring the OpenClaw gateway service is installed before watchdog registration."
    Invoke-RepairCommand -Arguments @("gateway", "install") -Reason "watchdog installation prerequisite" | Out-Null

    if ($DryRun) {
        Log "DRY RUN: would register Scheduled Task '$TaskName' for user $userId"
        return
    }

    try {
        Invoke-Schtasks -Arguments @("/Delete", "/F", "/TN", $TaskName) -IgnoreErrors | Out-Null
    } catch {
        Log "No prior watchdog task needed deletion."
    }

    $baseArgs = @(
        "/Create",
        "/F",
        "/SC",
        "MINUTE",
        "/MO",
        $IntervalMinutes.ToString(),
        "/TN",
        $TaskName,
        "/TR",
        $taskCommand,
        "/RL",
        "LIMITED"
    )
    try {
        Invoke-Schtasks -Arguments ($baseArgs + @("/RU", $userId, "/NP", "/IT")) | Out-Null
    } catch {
        Log "Primary schtasks registration failed, retrying with default current-user context."
        Invoke-Schtasks -Arguments $baseArgs | Out-Null
    }

    Log "Scheduled Task '$TaskName' installed."
    Log "Running an initial watchdog tick now."
    Invoke-Schtasks -Arguments @("/Run", "/TN", $TaskName) -IgnoreErrors | Out-Null
}

function Install-HeadlessWatchdogTasks {
    $gatewayStatus = (Get-GatewayStatus).parsed
    $gatewayWrapper = Ensure-HeadlessWrapper -Kind "gateway" -GatewayStatus $gatewayStatus
    $watchdogWrapper = Ensure-HeadlessWrapper -Kind "watchdog" -GatewayStatus $gatewayStatus
    $gatewayTask = Get-HeadlessGatewayTaskName
    $watchdogTask = Get-HeadlessWatchdogTaskName
    $userId = if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $env:USERNAME }
    $onceAt = (Get-Date).AddMinutes(1)

    if ($DryRun) {
        Log "DRY RUN: would register headless gateway task '$gatewayTask'"
        Log "DRY RUN: would register headless watchdog task '$watchdogTask'"
        return
    }

    foreach ($task in @($gatewayTask, $watchdogTask)) {
        try {
            Invoke-Schtasks -Arguments @("/Delete", "/F", "/TN", $task) -IgnoreErrors | Out-Null
        } catch {
            Log "No prior headless task needed deletion: $task"
        }
    }

    try {
        Invoke-Schtasks -Arguments @(
            "/Create",
            "/F",
            "/SC",
            "ONCE",
            "/ST",
            $onceAt.ToString("HH:mm"),
            "/SD",
            $onceAt.ToString("yyyy/MM/dd"),
            "/TN",
            $gatewayTask,
            "/TR",
            $gatewayWrapper,
            "/RU",
            $userId,
            "/NP",
            "/RL",
            "LIMITED"
        ) | Out-Null

        Invoke-Schtasks -Arguments @(
            "/Create",
            "/F",
            "/SC",
            "MINUTE",
            "/MO",
            $IntervalMinutes.ToString(),
            "/TN",
            $watchdogTask,
            "/TR",
            $watchdogWrapper,
            "/RU",
            $userId,
            "/NP",
            "/RL",
            "LIMITED"
        ) | Out-Null
    } catch {
        throw "Headless task registration was denied by Windows. Re-run from an elevated shell, or use the WSL2 + systemd startup chain from docs/platforms/windows.md. Original error: $($_.Exception.Message)"
    }

    Log "Headless gateway task '$gatewayTask' installed."
    Log "Headless watchdog task '$watchdogTask' installed."
    if (-not [bool]$gatewayStatus.rpc.ok) {
        Log "Gateway is currently unhealthy; running the headless gateway task now."
        Invoke-Schtasks -Arguments @("/Run", "/TN", $gatewayTask) -IgnoreErrors | Out-Null
    } else {
        Log "Gateway is already healthy; skipping the immediate headless gateway start."
    }
    Log "Running the headless watchdog task now."
    Invoke-Schtasks -Arguments @("/Run", "/TN", $watchdogTask) -IgnoreErrors | Out-Null
}

function Uninstall-WatchdogTask {
    if ($DryRun) {
        Log "DRY RUN: would unregister Scheduled Task '$TaskName'"
        return
    }

    $result = Invoke-Schtasks -Arguments @("/Delete", "/F", "/TN", $TaskName) -IgnoreErrors
    if ($result.exitCode -eq 0) {
        Log "Scheduled Task '$TaskName' removed."
        return
    }
    Log "Scheduled Task '$TaskName' does not exist."
}

function Uninstall-HeadlessWatchdogTasks {
    foreach ($task in @((Get-HeadlessGatewayTaskName), (Get-HeadlessWatchdogTaskName))) {
        $result = Invoke-Schtasks -Arguments @("/Delete", "/F", "/TN", $task) -IgnoreErrors
        if ($result.exitCode -eq 0) {
            Log "Scheduled Task '$task' removed."
        } else {
            Log "Scheduled Task '$task' does not exist."
        }
    }

    if ($DryRun) {
        Log "DRY RUN: would remove headless wrapper files."
        return
    }

    foreach ($path in @((Get-HeadlessGatewayWrapperPath), (Get-HeadlessWatchdogWrapperPath))) {
        Remove-Item -Path $path -Force -ErrorAction SilentlyContinue
    }
}

function Show-WatchdogStatus {
    Write-Host ""
    Write-Host "OpenClaw Watchdog"
    Write-Host "================="
    Write-Host "Script:" $Script:ScriptPath
    Write-Host "State file:" $Script:StatePath
    Write-Host "Log file:" $Script:LogPath
    Write-Host ""

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        Write-Host "Scheduled Task:" "missing"
    } else {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        Write-Host "Scheduled Task:" $task.TaskName
        Write-Host "Task state:" $task.State
        if ($info) {
            Write-Host "Last run time:" $info.LastRunTime
            Write-Host "Next run time:" $info.NextRunTime
            Write-Host "Last task result:" $info.LastTaskResult
        }
    }

    Write-Host ""
    try {
        $gatewayStatus = Get-GatewayStatus
        Write-Host "Gateway service loaded:" $gatewayStatus.parsed.service.loaded
        Write-Host "Gateway RPC OK:" $gatewayStatus.parsed.rpc.ok
        if (-not [bool]$gatewayStatus.parsed.rpc.ok) {
            Write-Host "Gateway RPC error:" $gatewayStatus.parsed.rpc.error
        }
    } catch {
        Write-Host "Gateway status error:" $_
    }

    Write-Host ""
    $state = Load-State
    Write-Host "State:"
    $state | ConvertTo-Json -Depth 8

    if ($Headless -or $Action -eq "install-headless" -or $Action -eq "uninstall-headless") {
        Write-Host ""
        foreach ($task in @((Get-HeadlessGatewayTaskName), (Get-HeadlessWatchdogTaskName))) {
            $headlessTask = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
            if ($null -eq $headlessTask) {
                Write-Host "Headless task ${task}:" "missing"
                continue
            }
            $info = Get-ScheduledTaskInfo -TaskName $task -ErrorAction SilentlyContinue
            Write-Host "Headless task:" $headlessTask.TaskName
            Write-Host "  state:" $headlessTask.State
            if ($info) {
                Write-Host "  last result:" $info.LastTaskResult
                Write-Host "  next run:" $info.NextRunTime
            }
        }
    }
}

function Show-Help {
    @"
OpenClaw watchdog for Windows

Usage:
  .\scripts\openclaw-monitor.ps1 install
  .\scripts\openclaw-monitor.ps1 install-headless
  .\scripts\openclaw-monitor.ps1 run
  .\scripts\openclaw-monitor.ps1 status
  .\scripts\openclaw-monitor.ps1 uninstall
  .\scripts\openclaw-monitor.ps1 uninstall-headless

Behavior:
  - Uses `openclaw gateway status --json` as the gateway source of truth
  - Uses `openclaw channels status --probe` to verify Discord is connected/ready
  - Installs/restarts the gateway deterministically first
  - Escalates to Claude Code CLI only after repeated failures
  - `install-headless` creates non-interactive Scheduled Tasks and pins `OPENCLAW_HOME`
    back to the selected user home so recovery works before login
"@ | Write-Host
}

try {
    switch ($Action) {
        "install" { Install-WatchdogTask }
        "install-headless" { Install-HeadlessWatchdogTasks }
        "uninstall" { Uninstall-WatchdogTask }
        "uninstall-headless" { Uninstall-HeadlessWatchdogTasks }
        "status" { Show-WatchdogStatus }
        "run" { Invoke-WatchdogRun }
        default { Show-Help }
    }
} catch {
    Log "Watchdog failed: $_"
    exit 1
}
