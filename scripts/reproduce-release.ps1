param(
    [ValidateSet("Core", "Full")]
    [string]$Edition = "Full",
    [string]$MsysRoot = "C:\msys64",
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\dist")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$common = @{
    IdrisVersion = "v0.8.0"
    ChezVersion = "v10.4.1"
    OutputDirectory = $OutputDirectory
}

if ($Edition -eq "Core") {
    & (Join-Path $PSScriptRoot "build-toolchain.ps1") @common `
        -Bash (Join-Path $MsysRoot "usr\bin\bash.exe") `
        -Cygpath (Join-Path $MsysRoot "usr\bin\cygpath.exe")
} else {
    & (Join-Path $PSScriptRoot "build-full-toolchain.ps1") @common `
        -PackCollection "nightly-251031" `
        -PackCommit "cb842e66c7e9834fae9cdf05ba33ca64fbec949f" `
        -PackDbCommit "69ddc094a218941bba5516828c2ee1dfdcc640f5" `
        -MsysRoot $MsysRoot
}

if ($LASTEXITCODE -ne 0) { throw "Release reproduction failed with exit code $LASTEXITCODE." }
