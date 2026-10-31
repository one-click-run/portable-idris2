param(
    [switch]$Check
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$root = $PSScriptRoot

function Add-Path([string]$Path) {
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        $env:PATH = "$Path;$env:PATH"
    }
}

$idrisPrefix = Join-Path $root "idris2"
$chezRoot = Join-Path $root "chez"
$chezBin = Join-Path $chezRoot "bin\ta6nt"
$runtime = Join-Path $root "runtime"
$data = Join-Path $root "data"
$schemeExe = Join-Path $chezBin "scheme.exe"

$env:IDRIS2_PREFIX = $idrisPrefix
# Idris passes CHEZ to a command shell. A full path containing spaces is split
# by the upstream Chez backend, so resolve the bundled executable through the
# process-local PATH instead. This keeps arbitrary installation paths working.
$env:CHEZ = "scheme"
$env:SCHEME = "scheme"
$env:XDG_CACHE_HOME = Join-Path $data "xdg-cache"
$env:XDG_CONFIG_HOME = Join-Path $data "xdg-config"
$env:XDG_DATA_HOME = Join-Path $data "xdg-data"
$env:XDG_STATE_HOME = Join-Path $data "xdg-state"

@($data, $env:XDG_CACHE_HOME, $env:XDG_CONFIG_HOME, $env:XDG_DATA_HOME, $env:XDG_STATE_HOME) |
    ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }

Add-Path $runtime
Add-Path $chezBin
Add-Path (Join-Path $idrisPrefix "bin")

if ($Check) {
    foreach ($tool in @("idris2", "scheme")) {
        $resolved = Get-Command $tool -ErrorAction SilentlyContinue
        if (-not $resolved) {
            throw "Missing tool: $tool"
        }
        if (-not $resolved.Source.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            throw "$tool resolved outside the portable directory: $($resolved.Source)"
        }
        Write-Host ("{0}: {1}" -f $tool, $resolved.Source)
    }

    if (-not (Test-Path -LiteralPath $schemeExe)) {
        throw "Bundled Chez Scheme is missing: $schemeExe"
    }

    & idris2 --version
    if ($LASTEXITCODE -ne 0) { throw "idris2 --version failed." }
    & $schemeExe --version
    if ($LASTEXITCODE -ne 0) { throw "scheme --version failed." }
    exit 0
}

$host.UI.RawUI.WindowTitle = "Portable Idris 2"
Write-Host "Portable Idris 2 environment" -ForegroundColor Green
Write-Host (& idris2 --version)
Write-Host "Backend: Chez Scheme"
Write-Host "This folder can be moved; the current session does not modify the system PATH." -ForegroundColor DarkGray
& $env:ComSpec /K "prompt (portable-idris2) `$P`$G"

