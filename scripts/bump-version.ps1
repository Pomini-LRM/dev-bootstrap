#!/usr/bin/env pwsh
#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.

<#
.SYNOPSIS
    Bumps dev-bootstrap semantic version.

.DESCRIPTION
    Updates config/version.json by incrementing major, minor, or patch.
#>

[CmdletBinding()]
param(
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Part = 'patch',

    [switch]$PrintOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $projectRoot 'config' 'version.json'
$moduleManifestPath = Join-Path $projectRoot 'DevBootstrap.psd1'

function ConvertFrom-SemVerString {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Version)

    if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "Invalid semantic version '$Version'. Expected format: <major>.<minor>.<patch>."
    }

    return @{
        Major = [int]$Matches[1]
        Minor = [int]$Matches[2]
        Patch = [int]$Matches[3]
    }
}

function ConvertTo-SemVerString {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Parts)

    return "$($Parts.Major).$($Parts.Minor).$($Parts.Patch)"
}

function Get-CurrentVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Version = '0.0.0'; Date = '' }
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        $data = $raw | ConvertFrom-Json -AsHashtable -Depth 5
        if (-not $data.ContainsKey('version')) {
            throw 'Missing version property.'
        }

        $version = [string]$data.version
        $date = if ($data.ContainsKey('date')) { [string]$data.date } else { '' }
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw 'Version value is empty.'
        }

        return @{ Version = $version.Trim(); Date = $date }
    }
    catch {
        throw "Unable to read version file '$Path': $_"
    }
}

function Set-VersionFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Date
    )

    $payload = [ordered]@{ version = $Version; date = $Date }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Set-ModuleManifestVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Version
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $updated = [regex]::Replace($raw, "(?m)^\s*ModuleVersion\s*=\s*'.*?'", "    ModuleVersion        = '$Version'")
    Set-Content -LiteralPath $Path -Value $updated -Encoding utf8
}

 $current = Get-CurrentVersion -Path $versionPath
 $currentVersion = $current.Version
 $currentDate = $current.Date
 $parts = ConvertFrom-SemVerString -Version $currentVersion

switch ($Part) {
    'major' {
        $parts.Major++
        $parts.Minor = 0
        $parts.Patch = 0
    }
    'minor' {
        $parts.Minor++
        $parts.Patch = 0
    }
    'patch' {
        $parts.Patch++
    }
}

$newVersion = ConvertTo-SemVerString -Parts $parts

# (version and next-version printed below with date)

if ($PrintOnly) {
    return
}

$today = (Get-Date).ToString('yyyy-MM-dd')
$currentDateDisplay = if (-not [string]::IsNullOrWhiteSpace($currentDate)) { "($currentDate)" } else { '' }
Write-Host "Current version: $currentVersion $currentDateDisplay"
Write-Host "Next version   : $newVersion ($today)"

Set-VersionFile -Path $versionPath -Version $newVersion -Date $today
Write-Host "Updated version file: $versionPath" -ForegroundColor Green

Set-ModuleManifestVersion -Path $moduleManifestPath -Version $newVersion
if (Test-Path -LiteralPath $moduleManifestPath) {
    Write-Host "Updated module manifest: $moduleManifestPath" -ForegroundColor Green
}

