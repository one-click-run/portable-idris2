param(
    [string]$IdrisVersion = "v0.8.0",
    [string]$ChezVersion = "v10.4.1",
    [string]$PackCollection = "nightly-251031",
    [string]$PackCommit = "cb842e66c7e9834fae9cdf05ba33ca64fbec949f",
    [string]$PackDbCommit = "69ddc094a218941bba5516828c2ee1dfdcc640f5",
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\dist"),
    [string]$MsysRoot = "C:\msys64"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

function Invoke-Native([scriptblock]$Command, [string]$Description) {
    & $Command | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Convert-ToUnixPath([string]$Path) {
    $result = (& $cygpath -u $Path).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $result) { throw "cygpath failed for $Path" }
    return $result
}

function Invoke-Bash([string]$Command, [string]$Description) {
    & $bash -l -c $Command | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE." }
}

function Get-CollectionPackage([string]$Name) {
    $pattern = "(?ms)^\[db\." + [regex]::Escape($Name) + "\]\s*(.*?)(?=^\[|\z)"
    $section = [regex]::Match($collectionText, $pattern)
    if (-not $section.Success) { throw "Package $Name is missing from collection $PackCollection." }
    $body = $section.Groups[1].Value
    $url = [regex]::Match($body, '(?m)^url\s*=\s*"([^"]+)"').Groups[1].Value
    $commit = [regex]::Match($body, '(?m)^commit\s*=\s*"([^"]+)"').Groups[1].Value
    $ipkg = [regex]::Match($body, '(?m)^ipkg\s*=\s*"([^"]+)"').Groups[1].Value
    if (-not $url -or -not $commit -or -not $ipkg) { throw "Incomplete package entry for $Name." }
    return [pscustomobject]@{ Name = $Name; Url = $url; Commit = $commit; Ipkg = $ipkg }
}

function Get-Source([string]$Name, [string]$Url, [string]$Commit) {
    $destination = Join-Path $packageSources $Name
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Invoke-Native { git -C $destination init } "git init for $Name"
    Invoke-Native { git -C $destination remote add origin $Url } "git remote for $Name"
    Invoke-Native { git -C $destination fetch --depth 1 origin $Commit } "git fetch for $Name"
    Invoke-Native { git -C $destination -c core.autocrlf=false checkout --detach FETCH_HEAD } "git checkout for $Name"
    return $destination
}

function Install-CollectionPackage([string]$Name) {
    $package = Get-CollectionPackage $Name
    $source = Get-Source $Name $package.Url $package.Commit
    $ipkgPath = Join-Path $source ($package.Ipkg -replace '/', '\')
    if (-not (Test-Path -LiteralPath $ipkgPath)) { throw "Missing $($package.Ipkg) for $Name." }
    Push-Location (Split-Path -Parent $ipkgPath)
    try {
        Invoke-Native { & $idrisCmd --install (Split-Path -Leaf $ipkgPath) } "Installing Pack dependency $Name"
    } finally {
        Pop-Location
    }
}

function Clear-DirectoryContents([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Get-ChildItem -LiteralPath $Path -Force | Remove-Item -Recurse -Force
    }
}

if ($PackCommit -notmatch '^[0-9a-f]{40}$' -or $PackDbCommit -notmatch '^[0-9a-f]{40}$') {
    throw "Pack and Pack DB must be pinned to full commit hashes."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$bash = Join-Path $MsysRoot "usr\bin\bash.exe"
$cygpath = Join-Path $MsysRoot "usr\bin\cygpath.exe"
if (-not (Test-Path -LiteralPath $bash) -or -not (Test-Path -LiteralPath $cygpath)) {
    throw "A complete MSYS2 environment is required at $MsysRoot."
}

# Build and package Core first. The Full payload extends the same tested tree,
# so both editions always contain the identical compiler and Chez runtime.
& (Join-Path $PSScriptRoot "build-toolchain.ps1") `
    -IdrisVersion $IdrisVersion `
    -ChezVersion $ChezVersion `
    -OutputDirectory $OutputDirectory `
    -Bash $bash `
    -Cygpath $cygpath
if ($LASTEXITCODE -ne 0) { throw "Core toolchain build failed." }

$buildRoot = Join-Path $repoRoot ".build"
$payload = Join-Path $buildRoot "payload"
$idrisSource = Join-Path $buildRoot "Idris2"
$packageSources = Join-Path $buildRoot "full-package-sources"
$packState = Join-Path $payload "data\pack-state"
$packUser = Join-Path $payload "data\pack-config"
$packCache = Join-Path $payload "data\pack-cache"
$portableBin = Join-Path $payload "bin"
New-Item -ItemType Directory -Path $packageSources, $packState, $packUser, $packCache, $portableBin -Force | Out-Null

$collectionUrl = "https://raw.githubusercontent.com/stefan-hoeck/idris2-pack-db/$PackDbCommit/collections/$PackCollection.toml"
$collectionFile = Join-Path $packState "db\$PackCollection.toml"
New-Item -ItemType Directory -Path (Split-Path -Parent $collectionFile) -Force | Out-Null
Invoke-WebRequest -Uri $collectionUrl -UseBasicParsing -OutFile $collectionFile
$collectionText = Get-Content -LiteralPath $collectionFile -Raw
$idrisSection = [regex]::Match($collectionText, '(?ms)^\[idris2\]\s*(.*?)(?=^\[|\z)')
$idrisCommit = [regex]::Match($idrisSection.Groups[1].Value, '(?m)^commit\s*=\s*"([0-9a-f]{40})"').Groups[1].Value
if (-not $idrisCommit) { throw "Could not read the Idris 2 commit from $PackCollection." }
$sourceCommit = (git -C $idrisSource rev-parse HEAD).Trim()
if ($sourceCommit -ne $idrisCommit) {
    throw "$PackCollection expects Idris 2 $idrisCommit, but $IdrisVersion resolved to $sourceCommit."
}

$compilerRoot = Join-Path $packState "install\$idrisCommit\idris2"
New-Item -ItemType Directory -Path (Split-Path -Parent $compilerRoot) -Force | Out-Null
Move-Item -LiteralPath (Join-Path $payload "idris2") -Destination $compilerRoot
$idrisCmd = Join-Path $compilerRoot "bin\idris2.cmd"
if (-not (Test-Path -LiteralPath $idrisCmd)) { throw "The Pack-managed compiler is missing $idrisCmd." }

$chezBin = Join-Path $payload "chez\bin\ta6nt"
$env:PATH = "$portableBin;$($compilerRoot)\bin;$chezBin;$(Join-Path $payload 'runtime');$(Join-Path $MsysRoot 'mingw64\bin');$(Join-Path $MsysRoot 'usr\bin');$env:PATH"
$env:IDRIS2_PREFIX = $compilerRoot
$env:CHEZ = "scheme"
$env:SCHEME = "scheme"
$env:CC = "gcc"
$env:IDRIS2_CC = "gcc"
$env:MSYSTEM = "MINGW64"
$env:MSYS2_PATH_TYPE = "inherit"

# Rebuild the compiler with itself and install source/API data required by LSP.
$idrisUnix = Convert-ToUnixPath $idrisSource
$prefixUnix = Convert-ToUnixPath $compilerRoot
$bootUnix = Convert-ToUnixPath $idrisCmd
Invoke-Bash "cd '$idrisUnix' && make clean && PREFIX='$prefixUnix' IDRIS2_BOOT='$bootUnix' IDRIS2_CG=chez SCHEME=scheme make all" "Idris 2 stage-three build"
Invoke-Bash "cd '$idrisUnix' && PREFIX='$prefixUnix' IDRIS2_BOOT='$bootUnix' IDRIS2_CG=chez SCHEME=scheme make install install-with-src-libs install-with-src-api" "Idris 2 source and API install"

# Bootstrap the Pack executable from the package commits pinned by the chosen
# collection. The order follows Pack's own installer for this release.
foreach ($dependency in @(
    "algebra", "ref1", "array", "bytestring", "getopts", "elab-util",
    "refined", "literal", "ilex-core", "ilex", "ilex-toml", "filepath"
)) {
    Install-CollectionPackage $dependency
}

$packSource = Get-Source "pack" "https://github.com/stefan-hoeck/idris2-pack" $PackCommit
Invoke-Native {
    git -C $packSource apply --whitespace=nowarn (Join-Path $repoRoot "patches\pack-windows-mkdir.patch")
} "Applying the audited Pack Windows compatibility patch"
Push-Location $packSource
try {
    Invoke-Native { & $idrisCmd --build pack.ipkg } "Building Pack"
} finally {
    Pop-Location
}
Copy-Item -Path (Join-Path $packSource "build\exec\*") -Destination $portableBin -Recurse -Force
$licenseDir = Join-Path $payload "third-party-licenses"
Copy-Item -LiteralPath (Join-Path $packSource "LICENSE") -Destination (Join-Path $licenseDir "Pack-LICENSE") -Force
foreach ($licensePackage in @("idris2-lsp", "lsp-lib")) {
    $package = Get-CollectionPackage $licensePackage
    $repoPath = $package.Url -replace '^https://github\.com/', '' -replace '\.git$', ''
    $licenseUrl = "https://raw.githubusercontent.com/$repoPath/$($package.Commit)/LICENSE"
    Invoke-WebRequest -Uri $licenseUrl -UseBasicParsing -OutFile (Join-Path $licenseDir "$licensePackage-LICENSE")
}
$packCmd = Join-Path $portableBin "pack.cmd"
if (-not (Test-Path -LiteralPath $packCmd)) { throw "Pack build did not produce pack.cmd." }

$stateConfig = @"
# Generated by one-click-run/portable-idris2.
collection = "$PackCollection"
"@
$userConfig = @"
[install]
with-src = true
safety-prompt = false
whitelist = [ "idris2-lsp" ]

[pack]
commit = "$PackCommit"

[idris2]
scheme = "scheme"
codegen = "chez"

[log]
package-path = "silence"
libs-path = "silence"
data-path = "silence"
app-path = "silence"
"@
[IO.File]::WriteAllText((Join-Path $packState "pack.toml"), $stateConfig, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $packUser "pack.toml"), $userConfig, [Text.UTF8Encoding]::new($false))

$env:HOME = Join-Path $payload "data\home"
$env:PACK_USER_DIR = $packUser
$env:PACK_STATE_DIR = $packState
$env:PACK_CACHE_DIR = $packCache
$env:PACK_BIN_DIR = $portableBin
New-Item -ItemType Directory -Path $env:HOME -Force | Out-Null

Invoke-Native { & $packCmd install-app idris2-lsp } "Installing idris2-lsp with Pack"
$lspOutput = @(& $packCmd app-path idris2-lsp) | Where-Object { $_ -and $_.Trim() }
if ($LASTEXITCODE -ne 0 -or $lspOutput.Count -eq 0) { throw "Pack did not report the idris2-lsp application path." }
$lspExecutable = $lspOutput[-1].Trim()
if (-not (Test-Path -LiteralPath $lspExecutable)) { throw "Pack reported a missing LSP executable: $lspExecutable" }
$lspDir = Split-Path -Parent $lspExecutable
foreach ($name in @("idris2-lsp", "idris2-lsp.cmd", "idris2-lsp_app")) {
    $existing = Join-Path $portableBin $name
    if (Test-Path -LiteralPath $existing) { Remove-Item -LiteralPath $existing -Recurse -Force }
}
Copy-Item -Path (Join-Path $lspDir "*") -Destination $portableBin -Recurse -Force

# Retain the complete, relocatable MSYS2 development environment for Git,
# package hooks, and the RefC backend. Remove only caches and transient homes.
$bundledMsys = Join-Path $payload "msys2"
Copy-Item -LiteralPath $MsysRoot -Destination $bundledMsys -Recurse
Clear-DirectoryContents (Join-Path $bundledMsys "var\cache\pacman\pkg")
Clear-DirectoryContents (Join-Path $bundledMsys "tmp")
Clear-DirectoryContents (Join-Path $bundledMsys "home")
Clear-DirectoryContents $packCache
Clear-DirectoryContents $packageSources

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $payload "Enter-PortableIdris2.ps1") -Check
if ($LASTEXITCODE -ne 0) { throw "The unpacked Full environment failed its self-check." }

$resolvedVersion = $IdrisVersion.TrimStart('v')
$assetName = "portable-idris2-full-$resolvedVersion-windows-x86_64.zip"
$archive = Join-Path $OutputDirectory $assetName
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
$sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
Push-Location $payload
try {
    if ($sevenZip) {
        & $sevenZip.Source a -tzip -mx=5 $archive ".\*"
        if ($LASTEXITCODE -ne 0) { throw "7-Zip failed." }
    } else {
        Compress-Archive -Path ".\*" -DestinationPath $archive -CompressionLevel Optimal
    }
} finally {
    Pop-Location
}

$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$archive.sha256", "$hash  $assetName`n", [Text.UTF8Encoding]::new($false))
Write-Host "Created $archive"
Write-Host "Created $archive.sha256"

