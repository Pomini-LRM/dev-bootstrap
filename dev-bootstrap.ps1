#!/usr/bin/env pwsh
#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.

<#
.SYNOPSIS
    dev-bootstrap entrypoint.

.DESCRIPTION
    Runs environment bootstrap modules for applications, repositories, and container images.

.PARAMETER RunMode
    full | appInstaller | automation | github | devops | acr

.PARAMETER ConfigPath
    Path to JSON configuration. Defaults to config/config.json.

.PARAMETER Silent
    Disable console output while keeping file logging enabled.

.PARAMETER NoConfirm
    Disable interactive confirmation prompt.

.PARAMETER FailFast
    Stop execution after the first critical module error.

.PARAMETER Force
    Force reinstall/reclone where supported.

.PARAMETER ShowVersion
    Prints dev-bootstrap version and exits.
#>

[CmdletBinding()]
param(
    [ValidateSet('full', 'appInstaller', 'automation', 'github', 'devops', 'acr')]
    [string]$RunMode = 'full',

    [string]$ConfigPath,

    [switch]$Silent,
    [switch]$NoConfirm,
    [switch]$FailFast,
    [switch]$Force,
    [switch]$ShowVersion,
    [switch]$PauseBeforeExit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-BeforeExit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ExitCode
    )

    if ($PauseBeforeExit) {
        Read-Host 'Press ENTER to close'
    }

    exit $ExitCode
}

# Guard: warn if ExecutionPolicy is not Bypass.
$currentPolicy = Get-ExecutionPolicy
if ($currentPolicy -notin @('Bypass', 'Unrestricted')) {
    Write-Host '' -ForegroundColor Yellow
    Write-Host "Current ExecutionPolicy: $currentPolicy" -ForegroundColor Yellow
    Write-Host 'Running without -ExecutionPolicy Bypass may cause script execution restrictions.' -ForegroundColor Yellow
    Write-Host '' -ForegroundColor Yellow
    $answer = Read-Host 'Restart with -ExecutionPolicy Bypass? [Y/n]'
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToLowerInvariant() -in @('y', 'yes')) {
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
        $proc = Start-Process -FilePath 'pwsh' -ArgumentList $argList -Wait -NoNewWindow -PassThru
        exit $proc.ExitCode
    }
    Write-Host 'Continuing with current ExecutionPolicy.' -ForegroundColor DarkGray
}

# Guard: ensure script runs with Administrator privileges (required for registry modifications and PATH updates).
$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [System.Security.Principal.WindowsPrincipal]$currentIdentity
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host '' -ForegroundColor Yellow
    Write-Host 'dev-bootstrap requires Administrator privileges.' -ForegroundColor Yellow
    Write-Host 'This is needed to: modify system PATH, add VSCode context menu, and install software.' -ForegroundColor Yellow
    Write-Host '' -ForegroundColor Yellow
    $answer = Read-Host 'Restart as Administrator? [Y/n]'
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToLowerInvariant() -in @('y', 'yes')) {
        $argList = @('-NoProfile', '-File', $MyInvocation.MyCommand.Path)
        foreach ($p in $PSBoundParameters.GetEnumerator()) {
            if ($p.Value -is [switch]) {
                if ($p.Value.IsPresent) { $argList += "-$($p.Key)" }
            }
            else {
                $argList += "-$($p.Key)"
                $argList += "$($p.Value)"
            }
        }
        $proc = Start-Process -FilePath 'pwsh' -ArgumentList $argList -Wait -PassThru -Verb RunAs
        exit $proc.ExitCode
    }
    Write-Host 'Continuing without Administrator privileges. Some operations may fail.' -ForegroundColor Yellow
}

$projectRoot = $PSScriptRoot

. (Join-Path $projectRoot 'src' 'common' 'Logger.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Filters.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Config.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Platform.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Report.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Utilities.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Version.ps1')
. (Join-Path $projectRoot 'src' 'orchestrator' 'Invoke-DevBootstrap.ps1')

$scriptVersion = Get-DevBootstrapVersion -ProjectRoot $projectRoot

if ($ShowVersion) {
    Write-Host "dev-bootstrap version: $scriptVersion"
    Wait-BeforeExit -ExitCode 0
}

$defaultConfigPath = Join-Path $projectRoot 'config' 'config.json'
$envFilePath = Join-Path $projectRoot '.env'

if (-not $ConfigPath) {
    $ConfigPath = $defaultConfigPath
}

# ---- First-run handoff: import config files from dev-bootstrap-first ---------
$firstRunHandoff = if ($env:DEV_BOOTSTRAP_FINAL) {
    $env:DEV_BOOTSTRAP_FINAL
}
elseif ($IsWindows -or (-not (Test-Path variable:IsWindows))) {
    Join-Path $env:USERPROFILE 'PominiLRM' 'dev-bootstrap'
}
else {
    Join-Path $HOME 'PominiLRM' 'dev-bootstrap'
}

if ((Test-Path -LiteralPath $firstRunHandoff) -and ($firstRunHandoff -ne $projectRoot)) {
    $handoffConfig = Join-Path $firstRunHandoff 'config' 'config.json'
    $handoffEnv = Join-Path $firstRunHandoff '.env'
    $imported = $false

    if ((Test-Path -LiteralPath $handoffConfig) -and (-not (Test-Path -LiteralPath $ConfigPath))) {
        $configDir = Join-Path $projectRoot 'config'
        if (-not (Test-Path -LiteralPath $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $handoffConfig -Destination $ConfigPath -Force
        Write-Host "Imported config.json from first-run handoff: $firstRunHandoff" -ForegroundColor Green
        $imported = $true
    }

    if ((Test-Path -LiteralPath $handoffEnv) -and (-not (Test-Path -LiteralPath $envFilePath))) {
        Copy-Item -LiteralPath $handoffEnv -Destination $envFilePath -Force
        Write-Host "Imported .env from first-run handoff: $firstRunHandoff" -ForegroundColor Green
        $imported = $true
    }

    if ($imported) {
        Remove-Item -LiteralPath $firstRunHandoff -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed first-run handoff folder: $firstRunHandoff" -ForegroundColor DarkGray
    }
}

if (Test-Path -LiteralPath $envFilePath) {
    Import-EnvFile -Path $envFilePath
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Host '' -ForegroundColor Red
    Write-Host 'Configuration file not found.' -ForegroundColor Red
    Write-Host "Path: $ConfigPath" -ForegroundColor Red
    Write-Host '' -ForegroundColor Red
    Write-Host 'First-time setup requires creating config/config.json before running dev-bootstrap.' -ForegroundColor Yellow
    Write-Host 'See README: First-Time Setup and Configuration.' -ForegroundColor Yellow
    Write-Host '' -ForegroundColor Yellow
    Write-Host 'Quick start:' -ForegroundColor Cyan
    Write-Host '  1) Manual: copy config\config.example.json config\config.json'
    Write-Host '  2) Interactive: pwsh .\scripts\setup-config-interactive.ps1'
    Wait-BeforeExit -ExitCode 2
}

try {
    $config = Read-DevBootstrapConfig -Path $ConfigPath
}
catch {
    Write-Host "Unable to load configuration: $_" -ForegroundColor Red
    Wait-BeforeExit -ExitCode 2
}

$requiresTokenModules = @()
if ($config.modules.github.enabled) { $requiresTokenModules += 'github' }
if ($config.modules.devops.enabled) { $requiresTokenModules += 'devops' }
if ($config.modules.acr.enabled) { $requiresTokenModules += 'acr' }

if (($requiresTokenModules.Count -gt 0) -and -not (Test-Path -LiteralPath $envFilePath)) {
    $modulesText = $requiresTokenModules -join ', '
    Write-Warning @"
Environment file not found: $envFilePath

Selected modules may require tokens/credentials ($modulesText).
If these variables are not already set at user/machine level, create .env from .env.example.
See README: First-Time Setup and Configuration.
"@
}

if ($Silent) { $config.general.silent = $true }
if ($PSBoundParameters.ContainsKey('Debug')) { $config.general.debug = $true }
if ($NoConfirm) { $config.general.noConfirm = $true }
if ($FailFast) { $config.general.failFast = $true }
if ($Force) { $config.general.force = $true }

$logLevel = if ($config.general.debug) { 'Debug' } else { 'Info' }
$logDirectory = if ([System.IO.Path]::IsPathRooted($config.general.logDirectory)) {
    $config.general.logDirectory
}
else {
    Join-Path $projectRoot $config.general.logDirectory
}

try {
    Initialize-Logger -LogDirectory $logDirectory -Level $logLevel -Silent:$config.general.silent | Out-Null
    Write-Log -Level Info -Message "dev-bootstrap version: $scriptVersion"
}
catch {
    Write-Error "Unable to initialize logger: $_"
    Wait-BeforeExit -ExitCode 2
}

Clear-DeferredActions
$exitCode = Invoke-DevBootstrap -Config $config -RunMode $RunMode -ProjectRoot $projectRoot -Force:$Force.IsPresent
Invoke-DeferredActions -Silent:$config.general.silent -NoConfirm:$config.general.noConfirm
Wait-BeforeExit -ExitCode $exitCode


