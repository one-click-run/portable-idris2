param([switch]$Check)

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
$env:XDG_CACHE_HOME = Join-Path $data "xdg-cache"
$env:XDG_CONFIG_HOME = Join-Path $data "xdg-config"
$env:XDG_DATA_HOME = Join-Path $data "xdg-data"
$env:XDG_STATE_HOME = Join-Path $data "xdg-state"
$env:PATH = "$(Join-Path $root 'bin');$($managedIdris.Directory.FullName);$(Join-Path $root 'chez\bin\ta6nt');$(Join-Path $root 'runtime');$(Join-Path $root 'msys2\mingw64\bin');$(Join-Path $root 'msys2\usr\bin');$env:PATH"

$workspace = Join-Path $root "examples\hello"
$lspLauncher = Join-Path $root "Launch-Idris2-LSP.exe"
if (-not (Test-Path -LiteralPath $lspLauncher -PathType Leaf)) { throw "Idris 2 LSP launcher is missing: $lspLauncher" }
$settingsPath = Join-Path $workspace ".vscode\settings.json"
$settings = [ordered]@{
    "idris2-lsp.path" = $lspLauncher
    "idris2-lsp.logFile" = (Join-Path $data "idris2-lsp.log")
    "idris2-lsp.trace.server" = "messages"
}
[IO.File]::WriteAllText($settingsPath, (($settings | ConvertTo-Json) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$writtenSettings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
if ($writtenSettings.'idris2-lsp.path' -ne $lspLauncher) {
    throw "VS Code settings do not point at the bundled Idris 2 LSP launcher."
}
if ($Check) {
    Write-Host "VS Code Idris 2 LSP configuration OK: $lspLauncher" -ForegroundColor Green
    exit 0
}

$code = Get-Command code.cmd -ErrorAction SilentlyContinue
if (-not $code) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"),
        (Join-Path $env:ProgramFiles "Microsoft VS Code\bin\code.cmd")
    )
    $codePath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($codePath) { $code = Get-Item -LiteralPath $codePath }
}
if (-not $code) { throw "Microsoft Visual Studio Code was not found. Install VS Code and try again." }

$codePath = if ($code.Source) { $code.Source } else { $code.FullName }
$extensions = @(& $codePath --list-extensions)
if ($extensions -notcontains "bamboo.idris2-lsp") {
    Write-Warning "The VS Code extension bamboo.idris2-lsp is not installed. The example will open, but LSP integration will be unavailable."
}
& $codePath --new-window $workspace
if ($LASTEXITCODE -ne 0) { throw "VS Code failed to start (exit code $LASTEXITCODE)." }
