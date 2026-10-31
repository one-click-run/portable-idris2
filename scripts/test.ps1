$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$files = @(
    "init.ps1",
    "Enter-PortableIdris2.ps1",
    "scripts\build-toolchain.ps1"
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

$init = Get-Content -LiteralPath (Join-Path $repoRoot "init.ps1") -Raw
foreach ($required in @("Get-FileHash", "SHA-256", "browser_download_url", "Enter-PortableIdris2.ps1", "--continue-at", "--retry-all-errors")) {
    if (-not $init.Contains($required)) {
        throw "init.ps1 is missing required installer behavior: $required"
    }
}

$launcher = Get-Content -LiteralPath (Join-Path $repoRoot "Enter-PortableIdris2.ps1") -Raw
foreach ($required in @("IDRIS2_PREFIX", "CHEZ", "XDG_CACHE_HOME", '$PSScriptRoot')) {
    if (-not $launcher.Contains($required)) {
        throw "Portable launcher is missing required isolation behavior: $required"
    }
}

Write-Host "All repository tests passed." -ForegroundColor Green

