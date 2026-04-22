#Requires -Version 5.1
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Installs minimum prerequisites to run dev-bootstrap on Windows.
.DESCRIPTION
    This script is intended for first-time setup on a new machine.
    It installs PowerShell 7 if missing and ensures TLS 1.2 is enabled.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Guard: warn if ExecutionPolicy is not Bypass.
$currentPolicy = Get-ExecutionPolicy
if ($currentPolicy -notin @('Bypass', 'Unrestricted')) {
    Write-Host '' -ForegroundColor Yellow
    Write-Host "Current ExecutionPolicy: $currentPolicy" -ForegroundColor Yellow
    Write-Host 'Running without -ExecutionPolicy Bypass may cause script execution restrictions.' -ForegroundColor Yellow
    Write-Host '' -ForegroundColor Yellow
    $answer = Read-Host 'Restart with -ExecutionPolicy Bypass? [Y/n]'
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToLowerInvariant() -in @('y', 'yes')) {
        $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        $argList = @('-ExecutionPolicy', 'Bypass', '-File', $MyInvocation.MyCommand.Path)
        foreach ($p in $PSBoundParameters.GetEnumerator()) {
            if ($p.Value -is [switch]) {
                if ($p.Value.IsPresent) { $argList += "-$($p.Key)" }
            }
            else {
                $argList += "-$($p.Key)"
                $argList += "$($p.Value)"
            }
        }
        $proc = Start-Process -FilePath $psExe -ArgumentList $argList -Wait -NoNewWindow -PassThru
        exit $proc.ExitCode
    }
    Write-Host 'Continuing with current ExecutionPolicy.' -ForegroundColor DarkGray
}

Write-Host 'Checking minimum prerequisites for dev-bootstrap...' -ForegroundColor Cyan

if (-not ([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwsh) {
    Write-Host "PowerShell 7 is already installed: $($pwsh.Source)" -ForegroundColor Green
}
else {
    Write-Host 'PowerShell 7 not found. Installing...' -ForegroundColor Yellow

    $winget = Get-Command winget -ErrorAction SilentlyContinue

    if ($winget) {
        winget install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements --silent
    }
    else {
        throw 'winget is not available. Install PowerShell 7 manually from https://github.com/PowerShell/PowerShell/releases.'
    }
}

$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Write-Host 'Preparing winget sources and agreements...' -ForegroundColor Cyan
    try {
        winget source update | Out-Null
        if ($LASTEXITCODE -ne 0) {
            winget source reset --force | Out-Null
            winget source update | Out-Null
        }

        winget list --accept-source-agreements --disable-interactivity | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'winget sources are ready.' -ForegroundColor Green
        }
        else {
            Write-Host 'winget source initialization returned a non-zero code. AppInstaller may fail until winget sources are healthy.' -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "winget source initialization failed: $_" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'Prerequisite setup completed.' -ForegroundColor Green

$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path (Join-Path $projectRoot 'config') 'config.json'

if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Host 'Configuration file not found (config/config.json).' -ForegroundColor Yellow
    Write-Host 'Next step: create configuration before running dev-bootstrap.' -ForegroundColor Cyan
    Write-Host '  Option A (interactive): pwsh .\scripts\setup-config-interactive.ps1'
    Write-Host '  Option B (manual): copy .\config\config.example.json .\config\config.json'
}
else {
    Write-Host 'Next step: run dev-bootstrap with pwsh:' -ForegroundColor Cyan
    Write-Host '  pwsh ./dev-bootstrap.ps1'
}


