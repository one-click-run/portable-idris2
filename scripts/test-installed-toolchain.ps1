param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$data = Join-Path $rootPath "data"
$packState = Join-Path $data "pack-state"
$isFull = Test-Path -LiteralPath (Join-Path $packState "pack.toml")
$idrisPrefix = Join-Path $rootPath "idris2"

if ($isFull) {
    $managedIdris = Get-ChildItem -LiteralPath (Join-Path $packState "install") -Filter "idris2.cmd" -Recurse |
        Where-Object { $_.Directory.Name -eq "bin" } | Select-Object -First 1
    if (-not $managedIdris) { throw "The Pack-managed Idris 2 compiler is missing." }
    $idrisPrefix = $managedIdris.Directory.Parent.FullName
    $env:HOME = Join-Path $data "home"
    $env:PACK_USER_DIR = Join-Path $data "pack-config"
    $env:PACK_STATE_DIR = $packState
    $env:PACK_CACHE_DIR = Join-Path $data "pack-cache"
    $env:PACK_BIN_DIR = Join-Path $rootPath "bin"
    $env:GIT_CONFIG_GLOBAL = Join-Path $data "gitconfig"
    $env:MSYSTEM = "MINGW64"
    $env:MSYS2_PATH_TYPE = "inherit"
    $env:IDRIS2_CC = "gcc"
}

$env:IDRIS2_PREFIX = $idrisPrefix
$env:CHEZ = "scheme"
$env:SCHEME = "scheme"
$env:XDG_CACHE_HOME = Join-Path $data "xdg-cache"
$env:XDG_CONFIG_HOME = Join-Path $data "xdg-config"
$env:XDG_DATA_HOME = Join-Path $data "xdg-data"
$env:XDG_STATE_HOME = Join-Path $data "xdg-state"
$paths = @()
if ($isFull) { $paths += Join-Path $rootPath "bin" }
$paths += Join-Path $idrisPrefix "bin"
$paths += Join-Path $rootPath "chez\bin\ta6nt"
$paths += Join-Path $rootPath "runtime"
if ($isFull) {
    $paths += Join-Path $rootPath "msys2\mingw64\bin"
    $paths += Join-Path $rootPath "msys2\usr\bin"
}
$env:PATH = ($paths -join ';') + ";$env:PATH"

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rootPath "Enter-PortableIdris2.ps1") -Check
if ($LASTEXITCODE -ne 0) { throw "Portable environment self-check failed." }

Push-Location $rootPath
try {
    & idris2 ".\examples\hello\Main.idr" -o "ci-hello"
    if ($LASTEXITCODE -ne 0) { throw "Chez compilation failed." }
    $chezOutput = (& ".\build\exec\ci-hello.cmd").Trim()
    if ($chezOutput -ne "Hello from portable Idris 2!") { throw "Unexpected Chez output: $chezOutput" }

    if ($isFull) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rootPath "Open-PortableIdris2-VSCode.ps1") -Check
        if ($LASTEXITCODE -ne 0) { throw "VS Code integration check failed." }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $rootPath "Open-PortableIdris2-VSCode.ps1") -CheckExtensions
        if ($LASTEXITCODE -ne 0) { throw "Offline bundled extension installation failed." }

        & idris2 --cg refc ".\examples\hello\Main.idr" -o "ci-hello-refc"
        if ($LASTEXITCODE -ne 0) { throw "RefC compilation failed." }
        $refc = Get-ChildItem -LiteralPath ".\build\exec" -Filter "ci-hello-refc.exe" | Select-Object -First 1
        if (-not $refc) { throw "RefC executable was not produced." }
        $refcOutput = (& $refc.FullName).Trim()
        if ($refcOutput -ne "Hello from portable Idris 2!") { throw "Unexpected RefC output: $refcOutput" }

        & node (Join-Path $PSScriptRoot "test-lsp-hover.js") `
            (Join-Path $rootPath "Launch-Idris2-LSP.exe") `
            (Join-Path $rootPath "examples\hello") `
            (Join-Path $rootPath "examples\hello\Main.idr")
        if ($LASTEXITCODE -ne 0) { throw "Idris 2 LSP hover test failed." }
    }
} finally {
    Pop-Location
}

Write-Host "Installed Idris 2 toolchain acceptance test passed." -ForegroundColor Green
