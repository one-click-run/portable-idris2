param(
    [string]$SelectedAsset = $env:ONE_CLICK_RUN_PORTABLE_IDRIS2_SELECTED_ASSET,
    [string]$InstallName = $env:ONE_CLICK_RUN_PORTABLE_IDRIS2_INSTALL_NAME,
    [string]$Repository = $(if ($env:ONE_CLICK_RUN_PORTABLE_IDRIS2_REPOSITORY) { $env:ONE_CLICK_RUN_PORTABLE_IDRIS2_REPOSITORY } else { "one-click-run/portable-idris2" }),
    [string]$ReleaseTag = $(if ($env:ONE_CLICK_RUN_PORTABLE_IDRIS2_RELEASE_TAG) { $env:ONE_CLICK_RUN_PORTABLE_IDRIS2_RELEASE_TAG } else { "toolchain" }),
    [string]$Archive = $env:ONE_CLICK_RUN_PORTABLE_IDRIS2_ARCHIVE,
    [string]$Checksum = $env:ONE_CLICK_RUN_PORTABLE_IDRIS2_CHECKSUM,
    [switch]$Force = ($env:ONE_CLICK_RUN_PORTABLE_IDRIS2_FORCE -eq "1")
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Receive-File([string]$Uri, [string]$Destination) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source --fail --location --retry 8 --retry-delay 2 --retry-all-errors `
            --continue-at - --output $Destination $Uri
        if ($LASTEXITCODE -ne 0) {
            throw "curl failed to download $Uri (exit code $LASTEXITCODE)."
        }
        return
    }

    Invoke-WebRequest -Uri $Uri -Headers $headers -OutFile $Destination
}

function Select-Asset($Assets) {
    if ($SelectedAsset) {
        $match = @($Assets | Where-Object { $_.name -eq $SelectedAsset })
        if ($match.Count -ne 1) {
            throw "The release does not contain asset: $SelectedAsset"
        }
        return $match[0]
    }

    if (@($Assets).Count -eq 1) {
        return @($Assets)[0]
    }

    $grid = Get-Command Out-GridView -ErrorAction SilentlyContinue
    if ($grid -and [Environment]::UserInteractive) {
        return $Assets | Select-Object name, size, updated_at, browser_download_url |
            Out-GridView -Title "Select a portable-idris2 toolchain" -OutputMode Single
    }

    Write-Host "Available toolchains:"
    for ($i = 0; $i -lt @($Assets).Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), @($Assets)[$i].name)
    }
    $choice = Read-Host "Enter a number"
    $index = 0
    if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt @($Assets).Count) {
        throw "Invalid selection."
    }
    return @($Assets)[$index - 1]
}

if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64" -and $env:PROCESSOR_ARCHITEW6432 -ne "AMD64") {
    throw "Only Windows x86-64 is currently supported."
}

$installBase = (Get-Location).Path
$headers = @{ Accept = "application/vnd.github+json"; "User-Agent" = "one-click-run-portable-idris2" }
$localArchive = $null
$localChecksum = $null
if ($Archive) {
    $localArchive = (Resolve-Path -LiteralPath $Archive).Path
    if ((Split-Path -Leaf $localArchive) -notmatch '^portable-idris2-.*-windows-x86_64\.zip$') {
        throw "The local archive name is not a portable Idris 2 Windows x86-64 release asset."
    }
    if (-not $Checksum) { $Checksum = "$localArchive.sha256" }
    $localChecksum = (Resolve-Path -LiteralPath $Checksum).Path
    $asset = [pscustomobject]@{ name = (Split-Path -Leaf $localArchive) }
    Write-Step "Using the local release archive $($asset.name)"
} else {
    $apiUrl = "https://api.github.com/repos/$Repository/releases/tags/$ReleaseTag"
    Write-Step "Reading the $ReleaseTag release from $Repository"
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers
    $zipAssets = @($release.assets | Where-Object { $_.name -match '^portable-idris2-.*-windows-x86_64\.zip$' })
    if ($zipAssets.Count -eq 0) {
        throw "The release has no Windows x86-64 toolchain. A maintainer must run the Publish toolchain workflow first."
    }
    $asset = Select-Asset $zipAssets
    if (-not $asset) {
        Write-Host "No toolchain selected. Installation cancelled."
        return
    }
}

$versionLabel = $asset.name -replace '^portable-idris2-', '' -replace '-windows-x86_64\.zip$', ''
if (-not $InstallName) {
    $InstallName = $versionLabel
}
if ($InstallName -notmatch '^[A-Za-z0-9._-]+$') {
    throw "The install name may contain only letters, digits, dots, underscores, and hyphens."
}

$folderName = "OCR-portable-idris2-$InstallName"
$destination = Join-Path $installBase $folderName
$launcher = Join-Path $installBase "$folderName.cmd"
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $launcher)) {
    if (-not $Force) {
        throw "$folderName already exists. Choose another name or set ONE_CLICK_RUN_PORTABLE_IDRIS2_FORCE=1 to replace it."
    }
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    if (Test-Path -LiteralPath $launcher) {
        Remove-Item -LiteralPath $launcher -Force
    }
}

$checksumName = "$($asset.name).sha256"
if (-not $localArchive) {
    $checksumAsset = @($release.assets | Where-Object { $_.name -eq $checksumName })
    if ($checksumAsset.Count -ne 1) {
        throw "Missing checksum file $checksumName. Refusing to install an unverified toolchain."
    }
}

$work = Join-Path $installBase ".$folderName.installing"
$archive = Join-Path $work $asset.name
$checksumFile = Join-Path $work $checksumName
$staging = Join-Path $work "payload"
try {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
    New-Item -ItemType Directory -Path $work, $staging | Out-Null

    if ($localArchive) {
        Write-Step "Copying the verified local release files"
        Copy-Item -LiteralPath $localArchive -Destination $archive
        Copy-Item -LiteralPath $localChecksum -Destination $checksumFile
    } else {
        Write-Step "Downloading $($asset.name)"
        Receive-File -Uri $asset.browser_download_url -Destination $archive
        Receive-File -Uri $checksumAsset[0].browser_download_url -Destination $checksumFile
    }
    $checksumText = [IO.File]::ReadAllText($checksumFile)
    $expected = ([regex]::Match($checksumText, '(?i)\b[0-9a-f]{64}\b')).Value.ToLowerInvariant()
    if (-not $expected) {
        throw "Could not parse the SHA-256 checksum file."
    }
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "SHA-256 verification failed. Expected $expected but got $actual."
    }

    Write-Step "Extracting the toolchain"
    Expand-Archive -LiteralPath $archive -DestinationPath $staging
    if (-not (Test-Path -LiteralPath (Join-Path $staging "Enter-PortableIdris2.ps1"))) {
        throw "The toolchain archive has an invalid layout."
    }
    Move-Item -LiteralPath $staging -Destination $destination

    $launcherContent = @"
@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0$folderName\Enter-PortableIdris2.ps1"
"@
    [IO.File]::WriteAllText($launcher, $launcherContent, [Text.UTF8Encoding]::new($false))
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step "Installation complete"
Write-Host "Double-click $folderName.cmd to enter the portable Idris 2 environment." -ForegroundColor Green

