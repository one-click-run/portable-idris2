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

function Expand-ToolchainArchive([string]$ArchivePath, [string]$DestinationPath) {
    # Windows PowerShell 5.1's Expand-Archive can fail while cleaning entries
    # from large archives (PathNotFound in Microsoft.PowerShell.Archive). The
    # system bsdtar is both streaming and substantially more reliable here.
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tar) {
        & $tar.Source -xf $ArchivePath -C $DestinationPath
        if ($LASTEXITCODE -ne 0) {
            throw "tar failed to extract the verified toolchain archive (exit code $LASTEXITCODE)."
        }
        return
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $DestinationPath)
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
$vscodeLauncher = Join-Path $installBase "$folderName-VSCode.cmd"
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $launcher) -or (Test-Path -LiteralPath $vscodeLauncher)) {
    if (-not $Force) {
        throw "$folderName already exists. Choose another name or set ONE_CLICK_RUN_PORTABLE_IDRIS2_FORCE=1 to replace it."
    }
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    if (Test-Path -LiteralPath $launcher) {
        Remove-Item -LiteralPath $launcher -Force
    }
    if (Test-Path -LiteralPath $vscodeLauncher) {
        Remove-Item -LiteralPath $vscodeLauncher -Force
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
$installationComplete = $false
try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
    New-Item -ItemType Directory -Path $staging | Out-Null

    if ($localArchive) {
        Write-Step "Verifying the local release files"
        $archiveForInstall = $localArchive
        $checksumForInstall = $localChecksum
    } else {
        $cachedArchiveIsValid = $false
        if ((Test-Path -LiteralPath $archive) -and (Test-Path -LiteralPath $checksumFile)) {
            $cachedExpected = ([regex]::Match([IO.File]::ReadAllText($checksumFile), '(?i)\b[0-9a-f]{64}\b')).Value.ToLowerInvariant()
            if ($cachedExpected) {
                Write-Step "Checking the previously downloaded archive"
                $cachedActual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
                $cachedArchiveIsValid = ($cachedActual -eq $cachedExpected)
            }
        }
        if ($cachedArchiveIsValid) {
            Write-Step "Reusing the verified download $($asset.name)"
        } else {
            Write-Step "Downloading $($asset.name)"
            Receive-File -Uri $asset.browser_download_url -Destination $archive
            if (Test-Path -LiteralPath $checksumFile) {
                Remove-Item -LiteralPath $checksumFile -Force
            }
            Receive-File -Uri $checksumAsset[0].browser_download_url -Destination $checksumFile
        }
        $archiveForInstall = $archive
        $checksumForInstall = $checksumFile
    }
    $checksumText = [IO.File]::ReadAllText($checksumForInstall)
    $expected = ([regex]::Match($checksumText, '(?i)\b[0-9a-f]{64}\b')).Value.ToLowerInvariant()
    if (-not $expected) {
        throw "Could not parse the SHA-256 checksum file."
    }
    $actual = (Get-FileHash -LiteralPath $archiveForInstall -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "SHA-256 verification failed. Expected $expected but got $actual."
    }

    Write-Step "Extracting the toolchain"
    Expand-ToolchainArchive -ArchivePath $archiveForInstall -DestinationPath $staging
    if (-not (Test-Path -LiteralPath (Join-Path $staging "Enter-PortableIdris2.ps1"))) {
        throw "The toolchain archive has an invalid layout."
    }
    Write-Step "Checking the extracted toolchain"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $staging "Enter-PortableIdris2.ps1") -Check
    if ($LASTEXITCODE -ne 0) {
        throw "The extracted toolchain failed its self-check. Antivirus quarantine or an incomplete extraction may be responsible."
    }
    Move-Item -LiteralPath $staging -Destination $destination

    $launcherContent = @"
@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0$folderName\Enter-PortableIdris2.ps1"
"@
    [IO.File]::WriteAllText($launcher, $launcherContent, [Text.UTF8Encoding]::new($false))

    $vscodeEntry = Join-Path $destination "Open-PortableIdris2-VSCode.ps1"
    if (Test-Path -LiteralPath $vscodeEntry) {
        $vscodeLauncherContent = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0$folderName\Open-PortableIdris2-VSCode.ps1"
if errorlevel 1 pause
"@
        [IO.File]::WriteAllText($vscodeLauncher, $vscodeLauncherContent, [Text.UTF8Encoding]::new($false))
    }
    $installationComplete = $true
} finally {
    if ($installationComplete -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    } elseif (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        if (-not $localArchive -and (Test-Path -LiteralPath $archive)) {
            Write-Warning "Installation failed. The downloaded archive was kept at $archive so the next run can resume without starting over."
        }
    }
}

Write-Step "Installation complete"
Write-Host "Double-click $folderName.cmd to enter the portable Idris 2 environment." -ForegroundColor Green
if (Test-Path -LiteralPath $vscodeLauncher) {
    Write-Host "Double-click $folderName-VSCode.cmd to open the bundled example in VS Code." -ForegroundColor Green
}

