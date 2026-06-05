#!/usr/bin/env pwsh
#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.

<#
.SYNOPSIS
    Builds a Windows release package with EXE, .env template, and config files.

.DESCRIPTION
    Compiles dev-bootstrap.ps1 into dev-bootstrap.exe using PS2EXE,
    prepares a distributable folder, and produces a ZIP + SHA256 file.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory,
    [switch]$IncludeUserConfig,
    [switch]$SkipModuleInstall,
    [switch]$SkipExeBuild,
    [string]$GitHubOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ReleaseVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VersionFilePath)

    if (-not (Test-Path -LiteralPath $VersionFilePath)) {
        throw "Version file not found: $VersionFilePath"
    }

    $raw = Get-Content -LiteralPath $VersionFilePath -Raw -Encoding utf8
    $json = $raw | ConvertFrom-Json -AsHashtable -Depth 5
    $version = if ($json.ContainsKey('version')) { [string]$json.version } else { '' }

    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Version file '$VersionFilePath' does not define a valid 'version' value."
    }

    return $version.Trim()
}

function Get-PS2EXECommand {
    [CmdletBinding()]
    param([switch]$NoInstall)

    $invokeCommand = Get-Command -Name Invoke-PS2EXE -ErrorAction SilentlyContinue
    if ($null -eq $invokeCommand) {
        $invokeCommand = Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue
    }

    if ($null -ne $invokeCommand) {
        return $invokeCommand.Name
    }

    if ($NoInstall) {
        throw 'PS2EXE is not installed. Install module ps2exe or rerun without -SkipModuleInstall.'
    }

    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name ps2exe -Scope CurrentUser -Force

    $invokeCommand = Get-Command -Name Invoke-PS2EXE -ErrorAction SilentlyContinue
    if ($null -eq $invokeCommand) {
        $invokeCommand = Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue
    }

    if ($null -eq $invokeCommand) {
        throw 'PS2EXE installation succeeded but invoke command was not found.'
    }

    return $invokeCommand.Name
}

function New-ReleaseLauncher {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $content = @'
@echo off
setlocal
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~dp0dev-bootstrap.exe' -Verb RunAs -WorkingDirectory '%~dp0' -ArgumentList '-PauseBeforeExit'"
  goto :end
)
"%~dp0dev-bootstrap.exe" -PauseBeforeExit %*
:end
endlocal
'@

    Set-Content -LiteralPath $Path -Value $content -Encoding ascii
}

if (-not $IsWindows) {
    throw 'Build-WindowsReleasePackage.ps1 must run on Windows.'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot 'artifacts'
}

$entryScriptPath = Join-Path $ProjectRoot 'dev-bootstrap.ps1'
$envExamplePath = Join-Path $ProjectRoot '.env.example'
$versionPath = Join-Path $ProjectRoot 'config' 'version.json'

if (-not (Test-Path -LiteralPath $entryScriptPath)) {
    throw "Entry script not found: $entryScriptPath"
}
if (-not (Test-Path -LiteralPath $envExamplePath)) {
    throw "Environment template not found: $envExamplePath"
}

$version = Get-ReleaseVersion -VersionFilePath $versionPath
$releaseBaseName = "dev-bootstrap-windows-v$version"
$stagingRoot = Join-Path $OutputDirectory $releaseBaseName
$zipPath = Join-Path $OutputDirectory "$releaseBaseName.zip"
$shaPath = "$zipPath.sha256"
$exePath = Join-Path $stagingRoot 'dev-bootstrap.exe'

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
if (Test-Path -LiteralPath $shaPath) {
    Remove-Item -LiteralPath $shaPath -Force
}

New-Item -Path $stagingRoot -ItemType Directory -Force | Out-Null

if (-not $SkipExeBuild) {
    $invokePs2ExeCommand = Get-PS2EXECommand -NoInstall:$SkipModuleInstall

    & $invokePs2ExeCommand `
        -inputFile $entryScriptPath `
        -outputFile $exePath `
        -x64 `
        -title 'dev-bootstrap' `
        -description 'POMINI dev-bootstrap'
}
else {
    Set-Content -LiteralPath $exePath -Value 'EXE build skipped by request.' -Encoding ascii
}

Copy-Item -LiteralPath $envExamplePath -Destination (Join-Path $stagingRoot '.env.example') -Force
Copy-Item -LiteralPath $envExamplePath -Destination (Join-Path $stagingRoot '.env') -Force

foreach ($path in @('config', 'src', 'scripts', 'docs')) {
    $source = Join-Path $ProjectRoot $path
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $stagingRoot $path) -Recurse -Force
    }
}

foreach ($file in @('README.md', 'LICENSE', 'CONTRIBUTING.md', 'SECURITY.md')) {
    $sourceFile = Join-Path $ProjectRoot $file
    if (Test-Path -LiteralPath $sourceFile) {
        Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $stagingRoot $file) -Force
    }
}

if (-not $IncludeUserConfig) {
    $userConfigPath = Join-Path $stagingRoot 'config' 'config.json'
    if (Test-Path -LiteralPath $userConfigPath) {
        Remove-Item -LiteralPath $userConfigPath -Force
    }
}

$backupFiles = Get-ChildItem -LiteralPath $stagingRoot -Recurse -File |
    Where-Object { $_.Name -match '\.bak(\.|$)' }
foreach ($backupFile in $backupFiles) {
    Remove-Item -LiteralPath $backupFile.FullName -Force
}

New-ReleaseLauncher -Path (Join-Path $stagingRoot 'dev-bootstrap-launcher.cmd')

Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $zipPath -Force
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
"$hash  $([System.IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath $shaPath -Encoding ascii

Write-Host "Release package folder: $stagingRoot" -ForegroundColor Green
Write-Host "Release ZIP          : $zipPath" -ForegroundColor Green
Write-Host "SHA256 file          : $shaPath" -ForegroundColor Green
Write-Host "SHA256               : $hash"

if (-not [string]::IsNullOrWhiteSpace($GitHubOutputPath)) {
    Add-Content -LiteralPath $GitHubOutputPath -Value "zip_path=$zipPath"
    Add-Content -LiteralPath $GitHubOutputPath -Value "zip_name=$([System.IO.Path]::GetFileName($zipPath))"
    Add-Content -LiteralPath $GitHubOutputPath -Value "sha_path=$shaPath"
    Add-Content -LiteralPath $GitHubOutputPath -Value "sha_name=$([System.IO.Path]::GetFileName($shaPath))"
    Add-Content -LiteralPath $GitHubOutputPath -Value "sha256=$hash"
    Add-Content -LiteralPath $GitHubOutputPath -Value "version=$version"
}
