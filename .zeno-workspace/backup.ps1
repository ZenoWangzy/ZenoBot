# zenomacbot 自动备份脚本
# 每天 12:00 执行，同步数据到 GitHub

$workspacePath = "C:\Users\ZenoW\.openclaw\workspace"

cd $workspacePath

# 添加所有变更
git add .

# 检查是否有变更需要提交
$status = git status --porcelain
if ($status) {
    # Commit（带时间戳）
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $hostname = $env:COMPUTERNAME
    git commit -m "Auto backup [$hostname] - $timestamp"

    # Push 到 GitHub
    git push origin main

    Write-Host "Backup completed at $timestamp (from $hostname)" -ForegroundColor Green
} else {
    Write-Host "No changes to backup at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
}
