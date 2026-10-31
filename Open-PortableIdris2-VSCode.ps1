param(
    [switch]$Check,
    [string]$CodePath = $env:ONE_CLICK_RUN_VSCODE,
    [switch]$InstallMissingExtension
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$data = Join-Path $root "data"
$extensionId = "bamboo.idris2-lsp"

function Find-VSCode([string]$RequestedPath) {
    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "ONE_CLICK_RUN_VSCODE does not point to a file: $RequestedPath"
        }
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }
    foreach ($commandName in @("code.cmd", "code.exe")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command) { return $(if ($command.Source) { $command.Source } else { $command.Path }) }
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\Code.exe"),
        (Join-Path $env:ProgramFiles "Microsoft VS Code\bin\code.cmd"),
        (Join-Path $env:ProgramFiles "Microsoft VS Code\Code.exe")
    )
    $match = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if ($match) { return $match }
    throw "Microsoft Visual Studio Code was not found. Install VS Code, or set ONE_CLICK_RUN_VSCODE to code.cmd or Code.exe."
}

function Test-OrInstallExtension([string]$VSCode, [string]$Extension) {
    $installed = @(& $VSCode --list-extensions 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "VS Code could not list installed extensions (exit code $LASTEXITCODE)." }
    if ($installed -contains $Extension) { return }

    Write-Warning "Required VS Code extension '$Extension' is not installed."
    $install = $InstallMissingExtension
    if (-not $install -and [Environment]::UserInteractive) {
        $answer = Read-Host "Install it now from the VS Code Marketplace? This requires network access. [y/N]"
        $install = $answer -match '^(?i:y|yes)$'
    }
    if (-not $install) {
        throw "The required extension is missing. Install it with: `"$VSCode`" --install-extension $Extension"
    }
    & $VSCode --install-extension $Extension
    if ($LASTEXITCODE -ne 0) { throw "VS Code failed to install extension '$Extension' (exit code $LASTEXITCODE)." }
    $installed = @(& $VSCode --list-extensions 2>&1)
    if ($LASTEXITCODE -ne 0 -or $installed -notcontains $Extension) {
        throw "VS Code reported success, but extension '$Extension' is still unavailable."
    }
}

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
$mainFile = Join-Path $workspace "Main.idr"
$lspLauncher = Join-Path $root "Launch-Idris2-LSP.exe"
if (-not (Test-Path -LiteralPath $mainFile -PathType Leaf)) { throw "Bundled Idris 2 example is missing: $mainFile" }
if (-not (Test-Path -LiteralPath $lspLauncher -PathType Leaf)) { throw "Idris 2 LSP launcher is missing: $lspLauncher" }

# These settings belong only to this dedicated workspace. User settings and
# the example folder's normal .vscode settings are never modified.
$workspaceFile = Join-Path $root "Portable-Idris2.code-workspace"
$workspaceDefinition = [ordered]@{
    folders = @([ordered]@{ path = $workspace })
    settings = [ordered]@{
        "idris2-lsp.path" = $lspLauncher
        "idris2-lsp.logFile" = (Join-Path $data "idris2-lsp.log")
        "idris2-lsp.trace.server" = "messages"
    }
}
[IO.File]::WriteAllText($workspaceFile, (($workspaceDefinition | ConvertTo-Json -Depth 8) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
$writtenWorkspace = Get-Content -LiteralPath $workspaceFile -Raw | ConvertFrom-Json
if ($writtenWorkspace.settings.'idris2-lsp.path' -ne $lspLauncher) {
    throw "The dedicated VS Code workspace does not point at the bundled Idris 2 LSP launcher."
}
if ($Check) {
    Write-Host "VS Code Idris 2 workspace configuration OK: $workspaceFile" -ForegroundColor Green
    exit 0
}

$resolvedCode = Find-VSCode $CodePath
Test-OrInstallExtension $resolvedCode $extensionId
& $resolvedCode --new-window $workspaceFile
if ($LASTEXITCODE -ne 0) { throw "VS Code failed to start (exit code $LASTEXITCODE)." }
