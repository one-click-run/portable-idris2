param(
    [Parameter(Mandatory = $true)]
    [string]$ServerCommand,
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,
    [string[]]$ServerArguments = @(),
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"
$server = (Resolve-Path -LiteralPath $ServerCommand).Path
$cwd = (Resolve-Path -LiteralPath $WorkingDirectory).Path

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $env:ComSpec
$escapedServer = $server.Replace('"', '""')
$argumentText = (($ServerArguments | ForEach-Object { '"' + $_.Replace('"', '""') + '"' }) -join ' ')
$startInfo.Arguments = "/d /s /c `"`"$escapedServer`" $argumentText`""
$startInfo.WorkingDirectory = $cwd
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $false
$startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)

$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) { throw "Could not start LSP server: $server" }

function Send-LspMessage($Message) {
    $json = $Message | ConvertTo-Json -Compress -Depth 20
    $length = [Text.Encoding]::UTF8.GetByteCount($json)
    $process.StandardInput.Write("Content-Length: $length`r`n`r`n$json")
    $process.StandardInput.Flush()
}

function Wait-Task($Task, [string]$Description) {
    if (-not $Task.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
        throw "Timed out while $Description."
    }
    return $Task.Result
}

function Read-LspMessage {
    $contentLength = $null
    while ($true) {
        $line = Wait-Task ($process.StandardOutput.ReadLineAsync()) "reading an LSP header"
        if ($null -eq $line) { throw "LSP server closed stdout before replying." }
        if ($line -match '^Content-Length:\s*(\d+)\s*$') {
            $contentLength = [int]$Matches[1]
        } elseif ($line.Length -eq 0 -and $null -ne $contentLength) {
            break
        }
    }

    $buffer = [char[]]::new($contentLength)
    $offset = 0
    while ($offset -lt $contentLength) {
        $task = $process.StandardOutput.ReadAsync($buffer, $offset, $contentLength - $offset)
        $read = Wait-Task $task "reading an LSP body"
        if ($read -le 0) { throw "LSP server closed stdout during a response." }
        $offset += $read
    }
    return (-join $buffer) | ConvertFrom-Json
}

function Read-Response([int]$Id) {
    while ($true) {
        $message = Read-LspMessage
        if ($null -ne $message.id -and [int]$message.id -eq $Id) { return $message }
    }
}

try {
    $rootUri = ([Uri]$cwd).AbsoluteUri
    Send-LspMessage ([ordered]@{
        jsonrpc = "2.0"; id = 1; method = "initialize"
        params = [ordered]@{ processId = $null; rootUri = $rootUri; capabilities = @{} }
    })
    $initialize = Read-Response 1
    if ($initialize.error -or -not $initialize.result.capabilities) {
        throw "LSP initialize failed: $($initialize | ConvertTo-Json -Compress -Depth 10)"
    }
    Write-Host "LSP initialize OK: $server" -ForegroundColor Green

    Send-LspMessage ([ordered]@{ jsonrpc = "2.0"; method = "initialized"; params = @{} })
    Send-LspMessage ([ordered]@{ jsonrpc = "2.0"; id = 2; method = "shutdown"; params = $null })
    $shutdown = Read-Response 2
    if ($shutdown.error) { throw "LSP shutdown failed: $($shutdown.error.message)" }
    Send-LspMessage ([ordered]@{ jsonrpc = "2.0"; method = "exit"; params = $null })
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(10000)) { throw "LSP server did not exit after shutdown." }
    if ($process.ExitCode -ne 0) { throw "LSP server exited with code $($process.ExitCode)." }
    Write-Host "LSP shutdown OK." -ForegroundColor Green
} finally {
    if (-not $process.HasExited) { $process.Kill() }
    $process.Dispose()
}

