#!/usr/bin/env pwsh
#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.

<#
.SYNOPSIS
    Interactive first-time configuration wizard for dev-bootstrap.

.DESCRIPTION
    Creates config/config.json from config/config.example.json through guided questions.
#>

[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $projectRoot 'config' 'config.example.json'

if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot 'config' 'config.json'
}

function Read-YesNo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $true
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $answer = Read-Host "$Prompt $suffix"

    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $Default
    }

    switch ($answer.Trim().ToLowerInvariant()) {
        'y' { return $true }
        'yes' { return $true }
        'n' { return $false }
        'no' { return $false }
        default {
            Write-Host "Invalid choice '$answer'. Please answer y or n." -ForegroundColor Yellow
            return Read-YesNo -Prompt $Prompt -Default $Default
        }
    }
}

function Read-TextWithDefault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default = ''
    )

    if ([string]::IsNullOrWhiteSpace($Default)) {
        return (Read-Host $Prompt)
    }

    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value.Trim()
}

function Read-ListWithDefault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string[]]$Default = @()
    )

    $defaultDisplay = if ($Default.Count -gt 0) { $Default -join ',' } else { '' }
    $raw = Read-TextWithDefault -Prompt $Prompt -Default $defaultDisplay

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    return @($raw.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Read-AppInstallerCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $catalogPath = Join-Path $ProjectRoot 'config' 'appinstaller.catalog.json'
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        throw "AppInstaller catalog not found: $catalogPath"
    }

    $raw = Get-Content -LiteralPath $catalogPath -Raw -Encoding utf8
    return ($raw | ConvertFrom-Json -AsHashtable -Depth 30)
}

function Read-AutomationCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $catalogPath = Join-Path $ProjectRoot 'config' 'automation.catalog.json'
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        throw "Automation catalog not found: $catalogPath"
    }

    $raw = Get-Content -LiteralPath $catalogPath -Raw -Encoding utf8
    return ($raw | ConvertFrom-Json -AsHashtable -Depth 30)
}

function Merge-Hashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Default,
        [Parameter(Mandatory)][hashtable]$Override
    )

    $result = @{}
    foreach ($key in $Default.Keys) {
        $result[$key] = $Default[$key]
    }

    foreach ($key in $Override.Keys) {
        $defaultValue = $result[$key]
        $overrideValue = $Override[$key]

        if ($defaultValue -is [hashtable] -and $overrideValue -is [hashtable]) {
            $result[$key] = Merge-Hashtable -Default $defaultValue -Override $overrideValue
        }
        else {
            $result[$key] = $overrideValue
        }
    }

    return $result
}

function ConvertTo-OrderedObject {
    [CmdletBinding()]
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($InputObject.Keys | Sort-Object)) {
            $ordered[$key] = ConvertTo-OrderedObject -InputObject $InputObject[$key]
        }
        return $ordered
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) {
            $items.Add((ConvertTo-OrderedObject -InputObject $item))
        }
        return @($items)
    }

    return $InputObject
}

function Get-CompactUserConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    $result = @{
        general = $Config.general
        modules = @{}
    }

    foreach ($moduleName in @('appInstaller', 'automation', 'github', 'devops', 'acr')) {
        $moduleConfig = $Config.modules[$moduleName]
        if ($moduleConfig.enabled) {
            if ($moduleName -eq 'appInstaller') {
                $recommendedApps = @{}
                foreach ($key in @($moduleConfig.recommendedApps.Keys | Sort-Object)) {
                    $recommendedApps[$key] = [bool]$moduleConfig.recommendedApps[$key]
                }

                $optionalApps = @{}
                foreach ($key in @($moduleConfig.optionalApps.Keys | Sort-Object)) {
                    $optionalApps[$key] = [bool]$moduleConfig.optionalApps[$key]
                }

                $result.modules[$moduleName] = @{
                    enabled = $true
                    force = [bool]$moduleConfig.force
                    recommendedApps = $recommendedApps
                    optionalApps = $optionalApps
                }
            }
            elseif ($moduleName -eq 'automation') {
                $catalog = @{}
                foreach ($key in @($moduleConfig.catalog.Keys | Sort-Object)) {
                    $catalog[$key] = [bool]$moduleConfig.catalog[$key]
                }

                $result.modules[$moduleName] = @{
                    enabled = $true
                    catalog = $catalog
                    gitHubUser = @{
                        name = [string]$moduleConfig.gitHubUser.name
                        email = [string]$moduleConfig.gitHubUser.email
                    }
                }
            }
            else {
                $result.modules[$moduleName] = $moduleConfig
            }
        }
        else {
            $result.modules[$moduleName] = @{ enabled = $false }
        }
    }

    return $result
}

function Read-EnabledModulesFallback {
    [CmdletBinding()]
    param([string[]]$DefaultSelection)

    Write-Host ''
    Write-Host 'Which modules do you want to enable? (multi-select)' -ForegroundColor Cyan
    Write-Host '[1] appInstaller'
    Write-Host '[2] automation'
    Write-Host '[3] github'
    Write-Host '[4] devops'
    Write-Host '[5] acr'

    $raw = Read-Host 'Enter numbers separated by comma (empty = keep defaults)'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        if ($DefaultSelection.Count -gt 0) {
            return $DefaultSelection
        }

        return @('appInstaller', 'automation', 'github', 'devops', 'acr')
    }

    $map = @{ '1' = 'appInstaller'; '2' = 'automation'; '3' = 'github'; '4' = 'devops'; '5' = 'acr' }
    $selected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($token in @($raw.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if (-not $map.ContainsKey($token)) {
            throw "Invalid module choice '$token'. Valid values are 1,2,3,4,5."
        }

        $selected.Add($map[$token]) | Out-Null
    }

    return @($selected)
}

function Read-EnabledModules {
    [CmdletBinding()]
    param([string[]]$DefaultSelection = @())

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        return Read-EnabledModulesFallback -DefaultSelection $DefaultSelection
    }

    $modules = @('appInstaller', 'automation', 'github', 'devops', 'acr')
    $selected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $DefaultSelection) {
        if ($modules -contains $item) {
            $selected.Add($item) | Out-Null
        }
    }

    $index = 0

    try {
        while ($true) {
            Clear-Host
            Write-Host 'Which modules do you want to enable? (multi-select)' -ForegroundColor Cyan
            Write-Host 'Use Up/Down to move, Space to toggle, Enter to confirm.' -ForegroundColor DarkGray
            Write-Host ''

            for ($i = 0; $i -lt $modules.Count; $i++) {
                $module = $modules[$i]
                $cursor = if ($i -eq $index) { '>' } else { ' ' }
                $mark = if ($selected.Contains($module)) { 'x' } else { ' ' }
                Write-Host ("$cursor [$mark] $module")
            }

            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            switch ($key.VirtualKeyCode) {
                38 {
                    if ($index -gt 0) { $index-- } else { $index = $modules.Count - 1 }
                }
                40 {
                    if ($index -lt ($modules.Count - 1)) { $index++ } else { $index = 0 }
                }
                32 {
                    $current = $modules[$index]
                    if ($selected.Contains($current)) {
                        $selected.Remove($current) | Out-Null
                    }
                    else {
                        $selected.Add($current) | Out-Null
                    }
                }
                13 {
                    Clear-Host
                    return @($selected)
                }
                default {}
            }
        }
    }
    catch {
        Write-Host 'Interactive keyboard selection is unavailable in this terminal. Falling back to numeric input.' -ForegroundColor Yellow
        return Read-EnabledModulesFallback -DefaultSelection $DefaultSelection
    }
}

function Get-EnabledModuleDefaults {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    $enabled = [System.Collections.Generic.List[string]]::new()
    foreach ($moduleName in @('appInstaller', 'automation', 'github', 'devops', 'acr')) {
        if ($Config.modules[$moduleName].enabled) {
            $enabled.Add($moduleName)
        }
    }

    return @($enabled)
}

if (-not (Test-Path -LiteralPath $templatePath)) {
    Write-Error "Template file not found: $templatePath"
    exit 2
}

$existingConfigPresent = Test-Path -LiteralPath $OutputPath

$config = Get-Content -LiteralPath $templatePath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth 30

if ($existingConfigPresent) {
    try {
        $existingConfig = Get-Content -LiteralPath $OutputPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth 30
        $config = Merge-Hashtable -Default $config -Override $existingConfig
        Write-Host "Existing configuration loaded from: $OutputPath" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Existing configuration could not be parsed and was ignored: $OutputPath" -ForegroundColor Yellow
        Write-Host "Reason: $_" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'dev-bootstrap interactive configuration' -ForegroundColor Green
Write-Host "Template: $templatePath"
Write-Host "Output:   $OutputPath"

$enabledModuleDefaults = Get-EnabledModuleDefaults -Config $config
$enabledModules = Read-EnabledModules -DefaultSelection $enabledModuleDefaults

foreach ($moduleName in @('appInstaller', 'automation', 'github', 'devops', 'acr')) {
    $config.modules[$moduleName].enabled = $enabledModules -contains $moduleName
}

Write-Host ''
Write-Host 'General' -ForegroundColor Cyan
$config.general.logDirectory = Read-TextWithDefault -Prompt 'Log directory path' -Default ([string]$config.general.logDirectory)
$config.general.failFast = Read-YesNo -Prompt 'Enable fail-fast (stop on first critical module error)?' -Default ([bool]$config.general.failFast)
$config.general.silent = Read-YesNo -Prompt 'Enable silent mode (no console output)?' -Default ([bool]$config.general.silent)
$config.general.noConfirm = Read-YesNo -Prompt 'Skip execution confirmation prompts?' -Default ([bool]$config.general.noConfirm)
$config.general.force = Read-YesNo -Prompt 'Enable force mode by default?' -Default ([bool]$config.general.force)

if ($config.modules.appInstaller.enabled) {
    Write-Host ''
    Write-Host 'Module: appInstaller' -ForegroundColor Cyan
    $config.modules.appInstaller.force = Read-YesNo -Prompt 'Enable appInstaller force by default?' -Default ([bool]$config.modules.appInstaller.force)

    $catalog = Read-AppInstallerCatalog -ProjectRoot $projectRoot

    if (-not $config.modules.appInstaller.ContainsKey('recommendedApps') -or $null -eq $config.modules.appInstaller.recommendedApps) {
        $config.modules.appInstaller.recommendedApps = @{}
    }

    if (-not $config.modules.appInstaller.ContainsKey('optionalApps') -or $null -eq $config.modules.appInstaller.optionalApps) {
        $config.modules.appInstaller.optionalApps = @{}
    }

    foreach ($app in @($catalog.apps | Where-Object { $_.category -eq 'recommended' })) {
        if ($config.modules.appInstaller.optionalApps.ContainsKey($app.key)) {
            $config.modules.appInstaller.recommendedApps[$app.key] = [bool]$config.modules.appInstaller.optionalApps[$app.key]
            $config.modules.appInstaller.optionalApps.Remove($app.key)
            continue
        }

        if (-not $config.modules.appInstaller.recommendedApps.ContainsKey($app.key)) {
            $config.modules.appInstaller.recommendedApps[$app.key] = $true
        }
    }

    foreach ($app in @($catalog.apps | Where-Object { $_.category -eq 'optional' })) {
        if (-not $config.modules.appInstaller.optionalApps.ContainsKey($app.key)) {
            $config.modules.appInstaller.optionalApps[$app.key] = $false
        }
    }

    Write-Host 'Module-required apps are managed automatically based on enabled modules.' -ForegroundColor DarkGray

    Write-Host ''
    Write-Host 'Recommended apps:' -ForegroundColor DarkGray
    foreach ($app in @($catalog.apps | Where-Object { $_.category -eq 'recommended' })) {
        $prompt = "Enable recommended app: $($app.name)?"
        $config.modules.appInstaller.recommendedApps[$app.key] = Read-YesNo -Prompt $prompt -Default ([bool]$config.modules.appInstaller.recommendedApps[$app.key])
    }

    Write-Host ''
    Write-Host 'Optional apps:' -ForegroundColor DarkGray
    foreach ($app in @($catalog.apps | Where-Object { $_.category -eq 'optional' })) {
        $prompt = "Enable optional app: $($app.name)?"
        $config.modules.appInstaller.optionalApps[$app.key] = Read-YesNo -Prompt $prompt -Default ([bool]$config.modules.appInstaller.optionalApps[$app.key])
    }
}

if ($config.modules.automation.enabled) {
    Write-Host ''
    Write-Host 'Module: automation' -ForegroundColor Cyan

    $configCatalog = Read-AutomationCatalog -ProjectRoot $projectRoot

    if (-not $config.modules.automation.ContainsKey('catalog') -or $null -eq $config.modules.automation.catalog) {
        $config.modules.automation.catalog = @{}
    }

    if (-not $config.modules.automation.ContainsKey('gitHubUser') -or $null -eq $config.modules.automation.gitHubUser) {
        $config.modules.automation.gitHubUser = @{ name = ''; email = '' }
    }

    foreach ($entry in @($configCatalog.automations)) {
        $key = [string]$entry.key
        if (-not $config.modules.automation.catalog.ContainsKey($key)) {
            $config.modules.automation.catalog[$key] = $false
        }

        $prompt = "Enable automation: $($entry.name)?"
        $config.modules.automation.catalog[$key] = Read-YesNo -Prompt $prompt -Default ([bool]$config.modules.automation.catalog[$key])
    }

    if ([bool]$config.modules.automation.catalog.setGitHubUser) {
        $config.modules.automation.gitHubUser.name = Read-TextWithDefault -Prompt 'Git user.name' -Default ([string]$config.modules.automation.gitHubUser.name)
        $config.modules.automation.gitHubUser.email = Read-TextWithDefault -Prompt 'Git user.email' -Default ([string]$config.modules.automation.gitHubUser.email)
    }
}

if ($config.modules.github.enabled) {
    Write-Host ''
    Write-Host 'Module: github' -ForegroundColor Cyan
    $config.modules.github.path = Read-TextWithDefault -Prompt 'GitHub destination full path' -Default ([string]$config.modules.github.path)
    $config.modules.github.setFolderIcon = Read-YesNo -Prompt 'Set folder icon for GitHub root (Windows only)?' -Default ([bool]$config.modules.github.setFolderIcon)
}

if ($config.modules.devops.enabled) {
    Write-Host ''
    Write-Host 'Module: devops' -ForegroundColor Cyan
    $config.modules.devops.path = Read-TextWithDefault -Prompt 'DevOps destination full path' -Default ([string]$config.modules.devops.path)
    $config.modules.devops.includeWikis = Read-YesNo -Prompt 'Include code wikis?' -Default ([bool]$config.modules.devops.includeWikis)
    $config.modules.devops.setFolderIcon = Read-YesNo -Prompt 'Set folder icon for DevOps root (Windows only)?' -Default ([bool]$config.modules.devops.setFolderIcon)
}

if ($config.modules.acr.enabled) {
    Write-Host ''
    Write-Host 'Module: acr' -ForegroundColor Cyan

    if (-not $config.modules.acr.ContainsKey('imagesInclude')) {
        if ($config.modules.acr.ContainsKey('images')) {
            $config.modules.acr.imagesInclude = @($config.modules.acr.images)
        }
        else {
            $config.modules.acr.imagesInclude = @('*')
        }
    }

    if (-not $config.modules.acr.ContainsKey('imagesExclude') -or $null -eq $config.modules.acr.imagesExclude) {
        $config.modules.acr.imagesExclude = @()
    }

    if ($config.modules.acr.ContainsKey('images')) {
        $config.modules.acr.Remove('images') | Out-Null
    }

    $config.modules.acr.registries = Read-ListWithDefault -Prompt 'ACR registries (comma-separated)' -Default @($config.modules.acr.registries)
    $config.modules.acr.imagesInclude = Read-ListWithDefault -Prompt 'Images include (comma-separated; use * for all)' -Default @($config.modules.acr.imagesInclude)
    $config.modules.acr.imagesExclude = Read-ListWithDefault -Prompt 'Images exclude (comma-separated)' -Default @($config.modules.acr.imagesExclude)
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

if ($existingConfigPresent -and (Test-Path -LiteralPath $OutputPath)) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupPath = "$OutputPath.bak.$timestamp"
    Copy-Item -LiteralPath $OutputPath -Destination $backupPath -Force
    Write-Host "Backup saved to: $backupPath" -ForegroundColor Cyan
}

$configToSave = Get-CompactUserConfig -Config $config
$orderedConfig = ConvertTo-OrderedObject -InputObject $configToSave
$orderedConfig | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding utf8

Write-Host ''
Write-Host "Configuration saved to: $OutputPath" -ForegroundColor Green
Write-Host 'Next steps:' -ForegroundColor Green

$enabled = @(@('appInstaller', 'automation', 'github', 'devops', 'acr') | Where-Object { $config.modules[$_].enabled })
$requiredVariables = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

if ($enabled -contains 'github') {
    $requiredVariables.Add('GITHUB_TOKEN') | Out-Null
}

if ($enabled -contains 'devops') {
    $requiredVariables.Add('AZURE_DEVOPS_PAT') | Out-Null
    $requiredVariables.Add('AZURE_DEVOPS_ORGS') | Out-Null
}

if ($enabled -contains 'acr') {
    $requiredVariables.Add('AZURE_TENANT_ID') | Out-Null
}

$step = 1
$envPath = Join-Path $projectRoot '.env'
$envExists = Test-Path -LiteralPath $envPath
if ($requiredVariables.Count -gt 0) {
    if (-not $envExists) {
        Write-Host "  $step ) Create .env from .env.example"
        $step++
    }

    $orderedVars = @($requiredVariables) | Sort-Object
    Write-Host "  $step ) Fill required tokens/variables ($($orderedVars -join ', '))"
    $step++
}
else {
    Write-Host "  $step ) No tokens are required for the selected modules."
    $step++
}

Write-Host "  $step ) Run: pwsh .\dev-bootstrap.ps1"

