param(
    [string]$DistDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$PackageName = 'MangaMeeyaCleanroom-Windows',
    [switch]$IncludeSample
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$OutputDir = Join-Path $DistDir $PackageName
$ZipPath = Join-Path $DistDir "$PackageName.zip"

if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}

New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutputDir 'app') | Out-Null

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MangaMeeyaCleanroom.ps1') -Destination (Join-Path $OutputDir 'app\MangaMeeyaCleanroom.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MangaMeeyaCleanroom.bat') -Destination (Join-Path $OutputDir 'app\MangaMeeyaCleanroom.bat')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'New-TestComic.ps1') -Destination (Join-Path $OutputDir 'app\New-TestComic.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Verify-WindowsPackage.ps1') -Destination (Join-Path $OutputDir 'app\Verify-WindowsPackage.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $OutputDir 'README.md')
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $OutputDir 'LICENSE')
Copy-Item -LiteralPath (Join-Path $repoRoot 'NOTICE') -Destination (Join-Path $OutputDir 'NOTICE')
Copy-Item -LiteralPath (Join-Path $repoRoot 'VERSION') -Destination (Join-Path $OutputDir 'VERSION') -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $repoRoot 'RELEASE-NOTES.md') -Destination (Join-Path $OutputDir 'RELEASE-NOTES.md') -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $repoRoot 'TEST-CHECKLIST.md') -Destination (Join-Path $OutputDir 'TEST-CHECKLIST.md') -ErrorAction SilentlyContinue

@'
@echo off
setlocal
cd /d "%~dp0app"
call MangaMeeyaCleanroom.bat %*
'@ | Set-Content -LiteralPath (Join-Path $OutputDir 'Start MangaMeeya Cleanroom.bat') -Encoding ASCII

@'
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(fso.BuildPath(base, "app"), "MangaMeeyaCleanroom.ps1")
args = ""
For i = 0 To WScript.Arguments.Count - 1
    args = args & " " & Quote(WScript.Arguments(i))
Next
shell.CurrentDirectory = fso.BuildPath(base, "app")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Quote(scriptPath) & args, 0, False

Function Quote(value)
    Quote = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
'@ | Set-Content -LiteralPath (Join-Path $OutputDir 'Start MangaMeeya Cleanroom.vbs') -Encoding ASCII

@'
@echo off
setlocal
cd /d "%~dp0app"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\New-TestComic.ps1" -OutputDir "..\sample"
call MangaMeeyaCleanroom.bat "..\sample\sample-folder"
'@ | Set-Content -LiteralPath (Join-Path $OutputDir 'Create Sample And Run.bat') -Encoding ASCII

@'
@echo off
setlocal
cd /d "%~dp0app"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\MangaMeeyaCleanroom.ps1" -SelfTest
'@ | Set-Content -LiteralPath (Join-Path $OutputDir 'Run Self Test.bat') -Encoding ASCII

if ($IncludeSample) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OutputDir 'app\New-TestComic.ps1') -OutputDir (Join-Path $OutputDir 'sample')
}

Compress-Archive -LiteralPath $OutputDir -DestinationPath $ZipPath -Force

$manifestPath = Join-Path $OutputDir 'PACKAGE-MANIFEST.txt'
$hashes = Get-ChildItem -LiteralPath $OutputDir -Recurse -File |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($OutputDir.Length).TrimStart('\')
        $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
        '{0}  {1}' -f $hash.Hash, $relative
    }
$hashes | Set-Content -LiteralPath $manifestPath -Encoding ASCII
Compress-Archive -LiteralPath $OutputDir -DestinationPath $ZipPath -Force

Write-Host "Built Windows package: $OutputDir"
Write-Host "Built zip package:     $ZipPath"
