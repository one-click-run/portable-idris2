$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$files = @(
    "init.ps1",
    "Enter-PortableIdris2.ps1",
    "Launch-Idris2-LSP.ps1",
    "Open-PortableIdris2-VSCode.ps1",
    "scripts\build-toolchain.ps1",
    "scripts\build-full-toolchain.ps1",
    "scripts\reproduce-release.ps1",
    "scripts\test-installed-toolchain.ps1"
)

foreach ($file in $files) {
    $path = Join-Path $repoRoot $file
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Error "${file}: $_" }
        throw "PowerShell syntax validation failed for $file"
    }
    Write-Host "Syntax OK: $file"
}

& node --check (Join-Path $repoRoot "scripts\test-lsp-hover.js")
if ($LASTEXITCODE -ne 0) { throw "JavaScript syntax validation failed for scripts\test-lsp-hover.js" }
Write-Host "Syntax OK: scripts\test-lsp-hover.js"

$init = Get-Content -LiteralPath (Join-Path $repoRoot "init.ps1") -Raw
foreach ($required in @("Get-FileHash", "SHA-256", "browser_download_url", "Enter-PortableIdris2.ps1", "--continue-at", "--retry-all-errors", '$Archive', '$localArchive')) {
    if (-not $init.Contains($required)) {
        throw "init.ps1 is missing required installer behavior: $required"
    }
}
foreach ($required in @("Expand-ToolchainArchive", "tar.exe", "Checking the extracted toolchain", '$installationComplete')) {
    if (-not $init.Contains($required)) {
        throw "init.ps1 is missing resilient extraction behavior: $required"
    }
}
foreach ($required in @('$vscodeLauncher', 'Open-PortableIdris2-VSCode.ps1')) {
    if (-not $init.Contains($required)) { throw "init.ps1 is missing the VS Code entry point: $required" }
}
$vscodeEntry = Get-Content -LiteralPath (Join-Path $repoRoot "Open-PortableIdris2-VSCode.ps1") -Raw
foreach ($required in @("Portable-Idris2.code-workspace", "ONE_CLICK_RUN_VSCODE", "--extensions-dir", "--user-data-dir", "extensions.autoUpdate")) {
    if (-not $vscodeEntry.Contains($required)) { throw "VS Code entry point is missing prerequisite or isolation behavior: $required" }
}
foreach ($required in @('$settingsPath', 'if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf))')) {
    if (-not $vscodeEntry.Contains($required)) { throw "VS Code entry point must initialize isolated settings only when they are missing: $required" }
}
foreach ($required in @('OCR_VSCODE_USER_DATA', 'To reset this isolated VS Code profile')) {
    if (-not $init.Contains($required)) { throw "Generated VS Code CMD must explain the isolated profile path and reset procedure: $required" }
}
if ($vscodeEntry.Contains('.vscode\settings.json')) { throw "VS Code entry point must not modify folder settings." }
$extensionManifest = Get-Content -LiteralPath (Join-Path $repoRoot "vscode-extensions\manifest.json") -Raw | ConvertFrom-Json
if (@($extensionManifest.extensions).Count -ne 1) { throw "Idris 2 Full release must pin exactly one client VSIX." }
if ($extensionManifest.extensions[0].id -ne 'bamboo.idris2-lsp') { throw "Idris 2 VSIX manifest has the wrong extension ID." }
foreach ($extension in $extensionManifest.extensions) {
    if ($extension.sha256 -notmatch '^[0-9a-f]{64}$' -or $extension.downloadUrl -notlike 'https://github.com/one-click-run/portable-idris2/releases/*') {
        throw "Invalid self-hosted VSIX metadata for $($extension.id)."
    }
}
if ($init -match '(?m)^\s*Expand-Archive\b') {
    throw "init.ps1 must not use the unreliable Windows PowerShell Expand-Archive path."
}

$launcher = Get-Content -LiteralPath (Join-Path $repoRoot "Enter-PortableIdris2.ps1") -Raw
foreach ($required in @("IDRIS2_PREFIX", "CHEZ", "XDG_CACHE_HOME", '$PSScriptRoot')) {
    if (-not $launcher.Contains($required)) {
        throw "Portable launcher is missing required isolation behavior: $required"
    }
}
foreach ($forbidden in @("Invoke-WebRequest", "Invoke-RestMethod", "curl.exe", "pack package-path", "pack libs-path", "pack data-path")) {
    if ($launcher.Contains($forbidden)) {
        throw "Portable launcher contains forbidden runtime network behavior: $forbidden"
    }
}

foreach ($requiredFile in @("OFFLINE-GUARANTEE.md", "BUILDING.md", "REPRODUCING.md")) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $requiredFile))) {
        throw "Missing release documentation: $requiredFile"
    }
}
foreach ($requiredFile in @(
    "Launch-Idris2-LSP.cmd",
    "native\Launch-Idris2-LSP.c",
    "scripts\test-lsp-hover.js",
    "vscode-extensions\manifest.json",
    "examples\hello\hello.ipkg",
    "vscode\idris2\extensions.json"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $requiredFile))) {
        throw "Missing VS Code integration file: $requiredFile"
    }
}

Write-Host "All repository tests passed." -ForegroundColor Green

