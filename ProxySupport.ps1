function ConvertTo-LoopbackAddress {
    param([AllowNull()][string]$Address)

    if ([string]::IsNullOrWhiteSpace($Address) -or
        $Address -in @('0.0.0.0', '::', '[::]')) {
        return '127.0.0.1'
    }

    $candidate = $Address.Trim().Trim('[', ']')
    if ($candidate -ieq 'localhost') {
        return '127.0.0.1'
    }

    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($candidate, [ref]$parsed)) {
        return $null
    }

    if (-not [Net.IPAddress]::IsLoopback($parsed)) {
        return $null
    }

    return $parsed.ToString()
}

function Format-ProxyUriHost {
    param([Parameter(Mandatory)][string]$Address)

    if ($Address.Contains(':')) {
        return "[$Address]"
    }

    return $Address
}

function Test-Socks5Handshake {
    param(
        [Parameter(Mandatory)][string]$ProxyHost,
        [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
        [ValidateRange(100, 30000)][int]$TimeoutMilliseconds = 1500
    )

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $connectTask = $client.ConnectAsync($ProxyHost, $Port)
        if (-not $connectTask.Wait($TimeoutMilliseconds) -or -not $client.Connected) {
            return $false
        }

        $stream = $client.GetStream()
        $stream.ReadTimeout = $TimeoutMilliseconds
        $stream.WriteTimeout = $TimeoutMilliseconds

        [byte[]]$request = 5, 1, 0
        $stream.Write($request, 0, $request.Length)

        [byte[]]$response = 0, 0
        $received = 0
        while ($received -lt $response.Length) {
            $count = $stream.Read($response, $received, $response.Length - $received)
            if ($count -le 0) {
                return $false
            }
            $received += $count
        }

        return $response[0] -eq 5 -and $response[1] -eq 0
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Test-HttpProxyHandshake {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProxyHost,
        [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
        [ValidateRange(100, 30000)][int]$TimeoutMilliseconds = 700
    )

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $connectTask = $client.ConnectAsync($ProxyHost, $Port)
        if (-not $connectTask.Wait($TimeoutMilliseconds) -or -not $client.Connected) {
            return $false
        }

        $stream = $client.GetStream()
        $stream.ReadTimeout = $TimeoutMilliseconds
        $stream.WriteTimeout = $TimeoutMilliseconds
        $probe = [Text.Encoding]::ASCII.GetBytes("CONNECT 127.0.0.1:1 HTTP/1.1`r`nHost: 127.0.0.1:1`r`nConnection: close`r`n`r`n")
        $stream.Write($probe, 0, $probe.Length)

        [byte[]]$responsePrefix = 0, 0, 0, 0, 0
        $received = 0
        while ($received -lt $responsePrefix.Length) {
            $count = $stream.Read($responsePrefix, $received, $responsePrefix.Length - $received)
            if ($count -le 0) {
                return $false
            }
            $received += $count
        }

        $prefix = [Text.Encoding]::ASCII.GetString($responsePrefix)
        Write-Verbose "HTTP proxy probe returned prefix: $prefix"
        return $prefix -eq 'HTTP/'
    } catch {
        Write-Verbose "HTTP proxy probe failed: $($_.Exception.Message)"
        return $false
    } finally {
        $client.Dispose()
    }
}

function Read-ExactProxyBytes {
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Count
    )

    [byte[]]$buffer = New-Object byte[] $Count
    $received = 0
    while ($received -lt $Count) {
        $read = $Stream.Read($buffer, $received, $Count - $received)
        if ($read -le 0) {
            throw 'The proxy closed the connection unexpectedly.'
        }
        $received += $read
    }

    return ,$buffer
}

function Test-HttpsThroughSocks5 {
    param(
        [Parameter(Mandatory)][string]$ProxyHost,
        [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
        [Parameter(Mandatory)][string]$TargetHost,
        [ValidateRange(1, 65535)][int]$TargetPort = 443,
        [string]$TargetPath = '/',
        [ValidateRange(1000, 30000)][int]$TimeoutMilliseconds = 12000
    )

    $client = [Net.Sockets.TcpClient]::new()
    $ssl = $null
    $reader = $null
    try {
        $connectTask = $client.ConnectAsync($ProxyHost, $Port)
        if (-not $connectTask.Wait($TimeoutMilliseconds) -or -not $client.Connected) {
            throw "Could not connect to SOCKS5 endpoint $ProxyHost`:$Port."
        }

        $stream = $client.GetStream()
        $stream.ReadTimeout = $TimeoutMilliseconds
        $stream.WriteTimeout = $TimeoutMilliseconds

        [byte[]]$greeting = 5, 1, 0
        $stream.Write($greeting, 0, $greeting.Length)
        $greetingReply = Read-ExactProxyBytes -Stream $stream -Count 2
        if ($greetingReply[0] -ne 5) {
            throw 'The endpoint returned an invalid SOCKS5 protocol version.'
        }
        if ($greetingReply[1] -ne 0) {
            throw ('The endpoint selected unsupported SOCKS5 authentication method 0x{0:X2}.' -f $greetingReply[1])
        }

        $hostBytes = [Text.Encoding]::ASCII.GetBytes($TargetHost)
        if ($hostBytes.Length -gt 255) {
            throw 'The target hostname is too long for a SOCKS5 domain request.'
        }

        [byte[]]$request = New-Object byte[] (7 + $hostBytes.Length)
        $request[0] = 5
        $request[1] = 1
        $request[2] = 0
        $request[3] = 3
        $request[4] = [byte]$hostBytes.Length
        [Array]::Copy($hostBytes, 0, $request, 5, $hostBytes.Length)
        $request[$request.Length - 2] = [byte](($TargetPort -shr 8) -band 255)
        $request[$request.Length - 1] = [byte]($TargetPort -band 255)
        $stream.Write($request, 0, $request.Length)

        $replyHeader = Read-ExactProxyBytes -Stream $stream -Count 4
        if ($replyHeader[0] -ne 5 -or $replyHeader[1] -ne 0) {
            throw "The SOCKS5 proxy could not connect to $TargetHost`:$TargetPort (reply $($replyHeader[1]))."
        }

        $addressLength = switch ($replyHeader[3]) {
            1 { 4 }
            3 { (Read-ExactProxyBytes -Stream $stream -Count 1)[0] }
            4 { 16 }
            default { throw 'The SOCKS5 proxy returned an unknown address type.' }
        }
        if ($addressLength -gt 0) {
            [void](Read-ExactProxyBytes -Stream $stream -Count $addressLength)
        }
        [void](Read-ExactProxyBytes -Stream $stream -Count 2)

        $ssl = [Net.Security.SslStream]::new($stream, $false)
        $ssl.ReadTimeout = $TimeoutMilliseconds
        $ssl.WriteTimeout = $TimeoutMilliseconds
        $ssl.AuthenticateAsClient(
            $TargetHost,
            $null,
            [Security.Authentication.SslProtocols]::Tls12,
            $true
        )

        $requestText = "HEAD $TargetPath HTTP/1.1`r`nHost: $TargetHost`r`nConnection: close`r`nUser-Agent: Codex-Gateway-Health-Check`r`n`r`n"
        $requestBytes = [Text.Encoding]::ASCII.GetBytes($requestText)
        $ssl.Write($requestBytes, 0, $requestBytes.Length)
        $ssl.Flush()

        $reader = [IO.StreamReader]::new($ssl, [Text.Encoding]::ASCII, $false, 1024, $true)
        $statusLine = $reader.ReadLine()
        if ($statusLine -notmatch '^HTTP/\S+\s+(\d{3})\b') {
            throw "The HTTPS endpoint returned an invalid status line: $statusLine"
        }

        return [int]$Matches[1]
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($ssl) { $ssl.Dispose() }
        $client.Dispose()
    }
}
