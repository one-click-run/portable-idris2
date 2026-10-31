$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$data = Join-Path $root "data"
$packState = Join-Path $data "pack-state"
$managedIdris = Get-ChildItem -LiteralPath (Join-Path $packState "install") -Filter "idris2.cmd" -Recurse |
    Where-Object { $_.Directory.Name -eq "bin" } | Select-Object -First 1
if (-not $managedIdris) { throw "The Pack-managed Idris 2 compiler is missing." }

$env:IDRIS2_PREFIX = $managedIdris.Directory.Parent.FullName
$env:CHEZ = "scheme"
$env:SCHEME = "scheme"
$env:HOME = Join-Path $data "home"
$env:PACK_USER_DIR = Join-Path $data "pack-config"
$env:PACK_STATE_DIR = $packState
$env:PACK_CACHE_DIR = Join-Path $data "pack-cache"
$env:PACK_BIN_DIR = Join-Path $root "bin"
$env:GIT_CONFIG_GLOBAL = Join-Path $data "gitconfig"
$env:XDG_CACHE_HOME = Join-Path $data "xdg-cache"
$env:XDG_CONFIG_HOME = Join-Path $data "xdg-config"
$env:XDG_DATA_HOME = Join-Path $data "xdg-data"
$env:XDG_STATE_HOME = Join-Path $data "xdg-state"
$env:ONE_CLICK_RUN_OFFLINE_RUNTIME = "1"
$env:MSYSTEM = "MINGW64"
$env:MSYS2_PATH_TYPE = "inherit"
$env:IDRIS2_CC = "gcc"
$env:PATH = "$(Join-Path $root 'bin');$($managedIdris.Directory.FullName);$(Join-Path $root 'chez\bin\ta6nt');$(Join-Path $root 'runtime');$(Join-Path $root 'msys2\mingw64\bin');$(Join-Path $root 'msys2\usr\bin');$env:PATH"

$server = Join-Path $root "bin\idris2-lsp.cmd"
if (-not (Test-Path -LiteralPath $server)) { throw "Bundled Idris 2 LSP is missing." }
& $server @args
exit $LASTEXITCODE
