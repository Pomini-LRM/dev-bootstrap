#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    dev-bootstrap entrypoint.

.DESCRIPTION
    Runs environment bootstrap modules for applications, repositories, and container images.

.PARAMETER RunMode
    full | appInstaller | configurations | github | devops | acr

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
    [ValidateSet('full', 'appInstaller', 'configurations', 'github', 'devops', 'acr')]
    [string]$RunMode = 'full',

    [string]$ConfigPath,

    [switch]$Silent,
    [switch]$NoConfirm,
    [switch]$FailFast,
    [switch]$Force,
    [switch]$ShowVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot

. (Join-Path $projectRoot 'src' 'common' 'Logger.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Config.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Platform.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Report.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Utilities.ps1')
. (Join-Path $projectRoot 'src' 'common' 'Version.ps1')
. (Join-Path $projectRoot 'src' 'orchestrator' 'Invoke-DevBootstrap.ps1')

$scriptVersion = Get-DevBootstrapVersion -ProjectRoot $projectRoot

if ($ShowVersion) {
    Write-Host "dev-bootstrap version: $scriptVersion"
    exit 0
}

$defaultConfigPath = Join-Path $projectRoot 'config' 'config.json'
$envFilePath = Join-Path $projectRoot '.env'

if (-not $ConfigPath) {
    $ConfigPath = $defaultConfigPath
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
    exit 2
}

try {
    $config = Read-DevBootstrapConfig -Path $ConfigPath
}
catch {
    Write-Host "Unable to load configuration: $_" -ForegroundColor Red
    exit 2
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
    exit 2
}

$exitCode = Invoke-DevBootstrap -Config $config -RunMode $RunMode -ProjectRoot $projectRoot -Force:$Force.IsPresent
exit $exitCode
