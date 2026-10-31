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

$coreIdrisPrefix = Join-Path $root "idris2"
$chezRoot = Join-Path $root "chez"
$chezBin = Join-Path $chezRoot "bin\ta6nt"
$runtime = Join-Path $root "runtime"
$data = Join-Path $root "data"
$schemeExe = Join-Path $chezBin "scheme.exe"
$packState = Join-Path $data "pack-state"
$packUser = Join-Path $data "pack-config"
$packCache = Join-Path $data "pack-cache"
$portableBin = Join-Path $root "bin"
$msysRoot = Join-Path $root "msys2"
$isFull = Test-Path -LiteralPath (Join-Path $packState "pack.toml")

$idrisPrefix = $coreIdrisPrefix
if ($isFull) {
    $managedIdris = Get-ChildItem -LiteralPath (Join-Path $packState "install") -Filter "idris2.cmd" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq "bin" } |
        Select-Object -First 1
    if (-not $managedIdris) {
        throw "The Pack-managed Idris 2 compiler is missing from the Full environment."
    }
    $idrisPrefix = $managedIdris.Directory.Parent.FullName
    $env:HOME = Join-Path $data "home"
    $env:PACK_USER_DIR = $packUser
    $env:PACK_STATE_DIR = $packState
    $env:PACK_CACHE_DIR = $packCache
    $env:PACK_BIN_DIR = $portableBin
    $env:GIT_CONFIG_GLOBAL = Join-Path $data "gitconfig"
    $env:MSYSTEM = "MINGW64"
    $env:MSYS2_PATH_TYPE = "inherit"
    $env:IDRIS2_CC = "gcc"
}

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

if ($isFull) {
    @($env:HOME, $packUser, $packState, $packCache, $portableBin) |
        ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
    Add-Path (Join-Path $msysRoot "usr\bin")
    Add-Path (Join-Path $msysRoot "mingw64\bin")
}

Add-Path $runtime
Add-Path $chezBin
Add-Path (Join-Path $idrisPrefix "bin")
if ($isFull) {
    Add-Path $portableBin
    $packagePath = (& pack package-path 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $packagePath) { $env:IDRIS2_PACKAGE_PATH = $packagePath }
    $libsPath = (& pack libs-path 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $libsPath) { $env:IDRIS2_LIBS = $libsPath }
    $dataPath = (& pack data-path 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $dataPath) { $env:IDRIS2_DATA = $dataPath }
}

if ($Check) {
    $tools = @("idris2", "scheme")
    if ($isFull) { $tools += @("pack", "idris2-lsp", "gcc", "git", "bash", "make") }
    foreach ($tool in $tools) {
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
    if ($isFull) {
        & pack help | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "pack help failed." }
        & git --version
        if ($LASTEXITCODE -ne 0) { throw "git --version failed." }
        & gcc --version | Select-Object -First 1
        if ($LASTEXITCODE -ne 0) { throw "gcc --version failed." }
    }
    exit 0
}

$host.UI.RawUI.WindowTitle = "Portable Idris 2"
Write-Host "Portable Idris 2 environment" -ForegroundColor Green
Write-Host (& idris2 --version)
Write-Host ("Edition: " + $(if ($isFull) { "Full (Pack, LSP, RefC/MinGW)" } else { "Core" }))
Write-Host "Default backend: Chez Scheme"
Write-Host "This folder can be moved; the current session does not modify the system PATH." -ForegroundColor DarkGray
& $env:ComSpec /K "prompt (portable-idris2) `$P`$G"

