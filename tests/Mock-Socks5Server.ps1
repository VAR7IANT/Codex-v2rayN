param(
    [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
    [ValidateRange(1, 100)][int]$MaxConnections = 10
)

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
$listener.Start()
try {
    for ($handled = 0; $handled -lt $MaxConnections; $handled++) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 2000
            [byte[]]$request = 0, 0, 0
            $received = 0
            while ($received -lt $request.Length) {
                $count = $stream.Read($request, $received, $request.Length - $received)
                if ($count -le 0) { break }
                $received += $count
            }

            if ($received -eq 3 -and $request[0] -eq 5) {
                [byte[]]$response = 5, 0
                $stream.Write($response, 0, $response.Length)
            } elseif ($received -eq 3 -and $request[0] -eq 67 -and $request[1] -eq 79 -and $request[2] -eq 78) {
                $response = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 502 Bad Gateway`r`nConnection: close`r`nContent-Length: 0`r`n`r`n")
                $stream.Write($response, 0, $response.Length)
            }
        } finally {
            $client.Dispose()
        }
    }
} finally {
    $listener.Stop()
}
