#!/usr/bin/env pwsh
#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.

<#
.SYNOPSIS
    Automates a GitHub Release trigger flow.

.DESCRIPTION
    Optionally bumps version, validates code quality, commits changes,
    creates an annotated git tag, and pushes branch + tag.

    The GitHub workflow '.github/workflows/release.yml' publishes the release.
#>

[CmdletBinding()]
param(
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Part = 'patch',

    [switch]$SkipVersionBump,
    [switch]$SkipQualityGate,
    [switch]$SkipPush,
    [string]$Remote = 'origin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-VersionFromFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VersionPath)

    if (-not (Test-Path -LiteralPath $VersionPath)) {
        throw "Version file not found: $VersionPath"
    }

    $raw = Get-Content -LiteralPath $VersionPath -Raw -Encoding utf8
    $data = $raw | ConvertFrom-Json -AsHashtable -Depth 5
    if (-not $data.ContainsKey('version')) {
        throw "Version file '$VersionPath' does not contain 'version'."
    }

    $value = [string]$data.version
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Version file '$VersionPath' contains an empty 'version' value."
    }

    return $value.Trim()
}

function Invoke-Git {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)

    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Arguments -join ' ')"
    }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

if (-not (Get-Command -Name git -ErrorAction SilentlyContinue)) {
    throw 'git command not found. Install Git and retry.'
}

if (-not $SkipVersionBump) {
    Write-Host "Bumping version: $Part" -ForegroundColor Cyan
    & (Join-Path $projectRoot 'scripts' 'bump-version.ps1') -Part $Part
    if (-not $?) {
        throw 'Version bump failed.'
    }
}

if (-not $SkipQualityGate) {
    Write-Host 'Running quality gate...' -ForegroundColor Cyan
    & (Join-Path $projectRoot 'scripts' 'Invoke-CodeQuality.ps1')
    if (-not $?) {
        throw 'Quality gate failed. Fix issues before publishing release.'
    }
}

$versionPath = Join-Path $projectRoot 'config' 'version.json'
$version = Get-VersionFromFile -VersionPath $versionPath
$tag = "v$version"
$commitMessage = "release: $tag"

$status = (& git status --porcelain=v1)
if ([string]::IsNullOrWhiteSpace(($status | Out-String))) {
    throw 'No changes detected to commit. Ensure version bump or release changes are present.'
}

Invoke-Git -Arguments @('add', '-A')
Invoke-Git -Arguments @('commit', '-m', $commitMessage)

$tagExists = (& git tag --list $tag)
if (-not [string]::IsNullOrWhiteSpace(($tagExists | Out-String))) {
    throw "Tag '$tag' already exists. Use a new version before publishing."
}

Invoke-Git -Arguments @('tag', '-a', $tag, '-m', $tag)

$branch = (& git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw 'Unable to detect current git branch.'
}

if (-not $SkipPush) {
    Write-Host "Pushing branch '$branch' and tag '$tag' to '$Remote'..." -ForegroundColor Cyan
    Invoke-Git -Arguments @('push', $Remote, $branch)
    Invoke-Git -Arguments @('push', $Remote, $tag)

    Write-Host 'Release trigger completed.' -ForegroundColor Green
    Write-Host "GitHub Actions will publish release for tag: $tag" -ForegroundColor Green
}
else {
    Write-Host "Local release artifacts prepared (commit + tag). Push manually when ready." -ForegroundColor Yellow
    Write-Host "  git push $Remote $branch" -ForegroundColor Yellow
    Write-Host "  git push $Remote $tag" -ForegroundColor Yellow
}
