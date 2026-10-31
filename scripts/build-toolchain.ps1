param(
    [string]$IdrisVersion = "v0.8.0",
    [string]$ChezVersion = "v10.4.1",
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\dist"),
    [string]$Bash = "C:\msys64\usr\bin\bash.exe",
    [string]$Cygpath = "C:\msys64\usr\bin\cygpath.exe"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

function Convert-ToUnixPath([string]$Path) {
    $result = (& $Cygpath -u $Path).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $result) {
        throw "cygpath failed for $Path"
    }
    return $result
}

function Invoke-Bash([string]$Command, [string]$Description) {
    & $Bash -l -c $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Copy-UpstreamLicense([string]$SourceRoot, [string]$Destination, [string]$Prefix) {
    $license = Get-ChildItem -LiteralPath $SourceRoot -File |
        Where-Object { $_.Name -match '^(LICENSE|COPYING|NOTICE)(\.|$)' } |
        Select-Object -First 1
    if ($license) {
        Copy-Item -LiteralPath $license.FullName -Destination (Join-Path $Destination "$Prefix-$($license.Name)")
    }
}

function Copy-CanonicalPatch([string]$Source, [string]$Destination) {
    # The official Windows release used CRLF patch files. Canonicalize the
    # copy shipped in the archive so its recorded SHA-256 is independent of
    # the builder's core.autocrlf setting.
    $content = [IO.File]::ReadAllText($Source) -replace "`r?`n", "`r`n"
    [IO.File]::WriteAllText($Destination, $content, [Text.UTF8Encoding]::new($false))
}

function Copy-MingwDependencies([string[]]$Roots, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $pending = [Collections.Generic.Queue[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $Roots) {
        if (Test-Path -LiteralPath $root) { $pending.Enqueue($root) }
    }

    while ($pending.Count -gt 0) {
        $binary = $pending.Dequeue()
        $unixBinary = Convert-ToUnixPath $binary
        $output = & $Bash -l -c "ldd '$unixBinary' 2>/dev/null || true"
        foreach ($line in @($output)) {
            $match = [regex]::Match($line, '=>\s+(/mingw64/[^ ]+\.dll)', 'IgnoreCase')
            if (-not $match.Success) { continue }
            $unixDependency = $match.Groups[1].Value
            $windowsDependency = (& $Cygpath -w $unixDependency).Trim()
            if (-not $windowsDependency -or -not $seen.Add($windowsDependency)) { continue }
            $target = Join-Path $Destination ([IO.Path]::GetFileName($windowsDependency))
            Copy-Item -LiteralPath $windowsDependency -Destination $target -Force
            $pending.Enqueue($target)
        }
    }
}

if (-not (Test-Path -LiteralPath $Bash) -or -not (Test-Path -LiteralPath $Cygpath)) {
    throw "MSYS2 bash and cygpath are required to build the toolchain."
}
if ($IdrisVersion -notmatch '^v?[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "IdrisVersion must be a release tag such as v0.8.0."
}
if ($ChezVersion -notmatch '^v?[0-9]+\.[0-9]+\.[0-9]+$') {
    throw "ChezVersion must be a release tag such as v10.4.1."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$buildRoot = Join-Path $repoRoot ".build"
$resolvedBuildRoot = [IO.Path]::GetFullPath($buildRoot)
if (-not $resolvedBuildRoot.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe build directory: $resolvedBuildRoot"
}
if (Test-Path -LiteralPath $buildRoot) {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}

$idrisSource = Join-Path $buildRoot "Idris2"
$chezSource = Join-Path $buildRoot "ChezScheme"
$installedIdris = Join-Path $buildRoot "installed-idris2"
$payload = Join-Path $buildRoot "payload"
$licenses = Join-Path $payload "third-party-licenses"
New-Item -ItemType Directory -Path $buildRoot, $installedIdris, $payload, $licenses, $OutputDirectory -Force | Out-Null

Write-Host "Cloning Idris 2 $IdrisVersion"
& git -c core.autocrlf=false clone --depth 1 --branch $IdrisVersion https://github.com/idris-lang/Idris2.git $idrisSource
if ($LASTEXITCODE -ne 0) { throw "Could not clone Idris 2 $IdrisVersion." }
$idrisPatchPath = Join-Path $repoRoot "patches\idris2-windows-data-directories.patch"
Invoke-Native {
    git -C $idrisSource apply --ignore-space-change --whitespace=nowarn $idrisPatchPath
} "Applying the audited Idris 2 Windows data-directory patch"

Write-Host "Cloning Chez Scheme $ChezVersion"
& git -c core.autocrlf=false clone --depth 1 --branch $ChezVersion https://github.com/cisco/ChezScheme.git $chezSource
if ($LASTEXITCODE -ne 0) { throw "Could not clone Chez Scheme $ChezVersion." }

$chezUnix = Convert-ToUnixPath $chezSource
$idrisUnix = Convert-ToUnixPath $idrisSource
$prefixUnix = Convert-ToUnixPath $installedIdris

$env:MSYSTEM = "MINGW64"
$env:MSYS2_PATH_TYPE = "inherit"
Invoke-Bash "cd '$chezUnix' && ./configure --threads && make -j2" "Chez Scheme build"
$chezBuild = Join-Path $chezSource "ta6nt"
$scheme = Join-Path $chezBuild "bin\ta6nt\scheme.exe"
if (-not (Test-Path -LiteralPath $scheme)) {
    throw "Chez Scheme build did not produce $scheme"
}

$env:SCHEME = "scheme"
$env:CC = "gcc"
$env:PATH = "$(Split-Path -Parent $scheme);C:\msys64\mingw64\bin;$env:PATH"
Invoke-Bash "cd '$idrisUnix' && PREFIX='$prefixUnix' SCHEME=scheme CC=gcc make bootstrap -j2" "Idris 2 bootstrap"
Invoke-Bash "cd '$idrisUnix' && PREFIX='$prefixUnix' SCHEME=scheme CC=gcc make install" "Idris 2 install"

Copy-Item -LiteralPath $installedIdris -Destination (Join-Path $payload "idris2") -Recurse
Copy-Item -LiteralPath $chezBuild -Destination (Join-Path $payload "chez") -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot "Enter-PortableIdris2.ps1") -Destination $payload
Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination $payload
Copy-Item -LiteralPath (Join-Path $repoRoot "THIRD_PARTY_NOTICES.md") -Destination $payload
Copy-Item -LiteralPath (Join-Path $repoRoot "OFFLINE-GUARANTEE.md") -Destination $payload
Copy-Item -LiteralPath (Join-Path $repoRoot "REPRODUCING.md") -Destination $payload
Copy-Item -LiteralPath (Join-Path $repoRoot "examples") -Destination $payload -Recurse
$payloadPatchDir = Join-Path $payload "patches"
New-Item -ItemType Directory -Path $payloadPatchDir -Force | Out-Null
$payloadIdrisPatch = Join-Path $payloadPatchDir "idris2-windows-data-directories.patch"
Copy-CanonicalPatch $idrisPatchPath $payloadIdrisPatch
Copy-UpstreamLicense $idrisSource $licenses "Idris2"
Copy-UpstreamLicense $chezSource $licenses "ChezScheme"

$runtimeRoots = @($scheme)
$runtimeRoots += Get-ChildItem -LiteralPath (Join-Path $payload "idris2") -Recurse -File |
    Where-Object { $_.Extension -in @('.exe', '.dll') } |
    Select-Object -ExpandProperty FullName
Copy-MingwDependencies $runtimeRoots (Join-Path $payload "runtime")

$idrisCommit = (git -C $idrisSource rev-parse HEAD).Trim()
$chezCommit = (git -C $chezSource rev-parse HEAD).Trim()
$manifest = [ordered]@{
    schema = "https://one-click-run.github.io/source-manifest/v1"
    project = "one-click-run/portable-idris2"
    platform = "windows-x86_64"
    edition = "core"
    offlineRuntime = $true
    repositoryCommit = $(if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { (git -C $repoRoot rev-parse HEAD).Trim() })
    components = @(
        [ordered]@{ name = "Idris2"; version = $IdrisVersion; commit = $idrisCommit; source = "https://github.com/idris-lang/Idris2.git"; license = "BSD-3-Clause" },
        [ordered]@{ name = "ChezScheme"; version = $ChezVersion; commit = $chezCommit; source = "https://github.com/cisco/ChezScheme.git"; license = "Apache-2.0" }
    )
    patches = @([ordered]@{
        path = "patches/idris2-windows-data-directories.patch"
        sha256 = (Get-FileHash -LiteralPath $payloadIdrisPatch -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}
[IO.File]::WriteAllText((Join-Path $payload "SOURCE-MANIFEST.json"), ($manifest | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))
$spdxPackages = @($manifest.components | ForEach-Object {
    [ordered]@{
        SPDXID = "SPDXRef-Package-" + ($_.name -replace '[^A-Za-z0-9.-]', '-')
        name = $_.name
        versionInfo = $_.version
        downloadLocation = $_.source
        filesAnalyzed = $false
        licenseConcluded = $_.license
        licenseDeclared = $_.license
        copyrightText = "NOASSERTION"
        externalRefs = @([ordered]@{ referenceCategory = "OTHER"; referenceType = "commit"; referenceLocator = $_.commit })
    }
})
$sbom = [ordered]@{
    spdxVersion = "SPDX-2.3"; dataLicense = "CC0-1.0"; SPDXID = "SPDXRef-DOCUMENT"
    name = "portable-idris2-core-$($IdrisVersion.TrimStart('v'))-windows-x86_64"
    documentNamespace = "https://github.com/one-click-run/portable-idris2/releases/tag/toolchain/spdx/core-$idrisCommit"
    creationInfo = [ordered]@{ created = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"); creators = @("Tool: one-click-run portable-idris2 build-toolchain.ps1") }
    packages = $spdxPackages
}
[IO.File]::WriteAllText((Join-Path $payload "SBOM.spdx.json"), ($sbom | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $payload "Enter-PortableIdris2.ps1") -Check
if ($LASTEXITCODE -ne 0) {
    throw "The unpacked portable environment failed its smoke test."
}

$resolvedVersion = $IdrisVersion.TrimStart('v')
$assetName = "portable-idris2-$resolvedVersion-windows-x86_64.zip"
$archive = Join-Path $OutputDirectory $assetName
if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}

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
$checksumPath = "$archive.sha256"
[IO.File]::WriteAllText($checksumPath, "$hash  $assetName`n", [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $payload "SOURCE-MANIFEST.json") -Destination (Join-Path $OutputDirectory "$assetName.source-manifest.json") -Force
Copy-Item -LiteralPath (Join-Path $payload "SBOM.spdx.json") -Destination (Join-Path $OutputDirectory "$assetName.spdx.json") -Force
Write-Host "Created $archive"
Write-Host "Created $checksumPath"

