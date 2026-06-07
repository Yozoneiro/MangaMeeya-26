param(
    [Parameter(Mandatory)]
    [string]$PackageDir,

    [switch]$RequireSample,

    [switch]$RunSmoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$package = (Resolve-Path -LiteralPath $PackageDir).ProviderPath

function Assert-Path {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Kind = 'Any'
    )

    if ($Kind -eq 'File') {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Missing file: $Path"
        }
    } elseif ($Kind -eq 'Directory') {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw "Missing directory: $Path"
        }
    } elseif (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing path: $Path"
    }
}

Assert-Path (Join-Path $package 'README.md') File
Assert-Path (Join-Path $package 'RELEASE-NOTES.md') File
Assert-Path (Join-Path $package 'TEST-CHECKLIST.md') File
Assert-Path (Join-Path $package 'LICENSE') File
Assert-Path (Join-Path $package 'NOTICE') File
Assert-Path (Join-Path $package 'Start MangaMeeya Cleanroom.bat') File
Assert-Path (Join-Path $package 'Start MangaMeeya Cleanroom.vbs') File
Assert-Path (Join-Path $package 'Create Sample And Run.bat') File
Assert-Path (Join-Path $package 'Run Self Test.bat') File
Assert-Path (Join-Path $package 'app') Directory
Assert-Path (Join-Path $package 'app\MangaMeeyaCleanroom.ps1') File
Assert-Path (Join-Path $package 'app\MangaMeeyaCleanroom.bat') File
Assert-Path (Join-Path $package 'app\New-TestComic.ps1') File

& (Join-Path $package 'Run Self Test.bat')
if ($LASTEXITCODE -ne 0) {
    throw 'Run Self Test.bat failed.'
}

if (-not $RequireSample) {
    if (Test-Path -LiteralPath (Join-Path $package 'sample')) {
        throw 'Clean package unexpectedly contains sample directory.'
    }
    if (Test-Path -LiteralPath (Join-Path $package 'portable-data')) {
        throw 'Clean package unexpectedly contains portable-data directory.'
    }
}

if ($RequireSample) {
    Assert-Path (Join-Path $package 'sample') Directory
    Assert-Path (Join-Path $package 'sample\sample-folder') Directory
    Assert-Path (Join-Path $package 'sample\sample.cbz') File
    Assert-Path (Join-Path $package 'sample\sample.cbt') File

    if ($RunSmoke) {
        $app = Join-Path $package 'app\MangaMeeyaCleanroom.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $app -SmokeTestPath (Join-Path $package 'sample\sample-folder') -SmokeOut (Join-Path $package 'sample\smoke-folder.png') -SmokeThumbnails
        if ($LASTEXITCODE -ne 0) { throw 'Folder smoke test failed.' }

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $app -SmokeTestPath (Join-Path $package 'sample\sample.cbz') -SmokeOut (Join-Path $package 'sample\smoke-cbz.png') -SmokeThumbnails
        if ($LASTEXITCODE -ne 0) { throw 'CBZ smoke test failed.' }

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $app -SmokeTestPath (Join-Path $package 'sample\sample.cbt') -SmokeOut (Join-Path $package 'sample\smoke-cbt.png') -SmokeThumbnails
        if ($LASTEXITCODE -ne 0) { throw 'CBT smoke test failed.' }
    }
}

Write-Host "VERIFY OK: $package"
