$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$files = @(
    "init.ps1",
    "Enter-PortableIdris2.ps1",
    "scripts\build-toolchain.ps1",
    "scripts\build-full-toolchain.ps1",
    "scripts\reproduce-release.ps1"
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
foreach ($required in @("Get-FileHash", "SHA-256", "browser_download_url", "Enter-PortableIdris2.ps1", "--continue-at", "--retry-all-errors", '$Archive', '$localArchive')) {
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

Write-Host "All repository tests passed." -ForegroundColor Green

