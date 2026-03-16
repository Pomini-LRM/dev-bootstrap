#!/usr/bin/env pwsh
#Requires -Version 7.0

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
        return '0.0.0'
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        $data = $raw | ConvertFrom-Json -AsHashtable -Depth 5
        if (-not $data.ContainsKey('version')) {
            throw 'Missing version property.'
        }

        $version = [string]$data.version
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw 'Version value is empty.'
        }

        return $version.Trim()
    }
    catch {
        throw "Unable to read version file '$Path': $_"
    }
}

function Set-VersionFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Version
    )

    $payload = [ordered]@{ version = $Version }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding utf8
}

$currentVersion = Get-CurrentVersion -Path $versionPath
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

Write-Host "Current version: $currentVersion"
Write-Host "Next version   : $newVersion"

if ($PrintOnly) {
    return
}

Set-VersionFile -Path $versionPath -Version $newVersion
Write-Host "Updated version file: $versionPath" -ForegroundColor Green
