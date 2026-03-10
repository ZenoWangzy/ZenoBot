# zenomacbot 智能备份脚本
# 自动拉取 -> 智能合并 -> 推送

$ErrorActionPreference = "Continue"

$workspacePath = "C:\Users\ZenoW\.openclaw\workspace"
$hostname = $env:COMPUTERNAME
$instanceType = if ($hostname -match "MacBook|MBP|iMac|mac-") { "mac" } else { "win" }
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$today = Get-Date -Format "yyyy-MM-dd"

cd $workspacePath

# Step 1: 拉取最新版本
Write-Host "[$timestamp] Step 1: Pulling latest version..." -ForegroundColor Cyan

$hasStash = $false
$stashResult = git stash push -m "Auto-stash before pull" 2>&1
if ($stashResult -notmatch "No local changes") {
    $hasStash = $true
}

git pull origin master --no-rebase 2>&1 | Out-Null

if ($hasStash) {
    git stash pop 2>&1 | Out-Null
}

Write-Host "[$timestamp] Pull completed" -ForegroundColor Green

# Step 2: 智能文件隔离
Write-Host "[$timestamp] Step 2: Isolating instance-specific files..." -ForegroundColor Cyan

$dailyNote = "memory\$today.md"
$instanceDailyNote = "memory\$instanceType-$today.md"

if (Test-Path $dailyNote) {
    if (Test-Path $instanceDailyNote) {
        $dailyContent = Get-Content $dailyNote -Raw -Encoding UTF8
        $instanceContent = Get-Content $instanceDailyNote -Raw -Encoding UTF8

        if ($instanceContent -notmatch "## Windows Instance Updates" -and $instanceType -eq "win") {
            $mergedContent = $instanceContent + "`r`n`r`n## Windows Instance Updates`r`n" + $dailyContent
            Set-Content $instanceDailyNote $mergedContent -Encoding UTF8
        } elseif ($instanceContent -notmatch "## Mac Instance Updates" -and $instanceType -eq "mac") {
            $mergedContent = $instanceContent + "`r`n`r`n## Mac Instance Updates`r`n" + $dailyContent
            Set-Content $instanceDailyNote $mergedContent -Encoding UTF8
        }
    } else {
        Move-Item $dailyNote $instanceDailyNote -Force
    }
    Remove-Item $dailyNote -Force
}

Write-Host "[$timestamp] Daily note isolated to: $instanceDailyNote" -ForegroundColor Green

# Step 3: 提交和推送
Write-Host "[$timestamp] Step 3: Committing and pushing..." -ForegroundColor Cyan

git add .

$status = git status --porcelain
if ($status) {
    $commitMessage = "Auto backup [$instanceType] - $timestamp"
    git commit -m $commitMessage

    git push origin master 2>&1 | Out-Null

    Write-Host "[$timestamp] Backup completed successfully!" -ForegroundColor Green
    Write-Host "[$timestamp] Instance: $instanceType" -ForegroundColor Gray
    $commitHash = git rev-parse --short HEAD 2>$null
    Write-Host "[$timestamp] Commit: $commitHash" -ForegroundColor Gray
} else {
    Write-Host "[$timestamp] No changes to backup" -ForegroundColor Yellow
}

# Step 4: 同步日志
$syncLog = "memory\sync-$today.log"
$logEntry = "[$timestamp] [$instanceType] Backup completed"
Add-Content $syncLog $logEntry

Write-Host "[$timestamp] Sync log updated: $syncLog" -ForegroundColor Gray
