#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Centralized configuration management for dev-bootstrap.
#>

function Get-DefaultConfig {
    [CmdletBinding()]
    param()

    return @{
        general = @{
            logDirectory = 'log'
            failFast = $false
            silent = $false
            debug = $false
            noConfirm = $false
            force = $false
        }
        modules = @{
            appInstaller = @{
                enabled = $true
                force = $false
                recommendedApps = @{
                    gnuWin32Make = $true
                    winget = $true
                    nvmWindows = $true
                    notepadplusplus = $true
                    python31012 = $true
                    vscode = $true
                }
                optionalApps = @{
                    githubCopilot = $false
                    githubDesktop = $false
                    inkscape = $false
                    pythonLatest = $false
                    teamviewer = $false
                }
            }
            automation = @{
                enabled = $false
                catalog = @{
                    addMakePath = $true
                    setGitHubUser = $false
                    desktopLinkForThisApplication = $false
                }
                gitHubUser = @{
                    name = ''
                    email = ''
                }
            }
            github = @{
                enabled = $false
                path = '~/GitHub'
                usersInclude = @('*')
                usersExclude = @()
                organizationsInclude = @('*')
                organizationsExclude = @()
                setFolderIcon = $true
                retryCount = 3
                retryDelaySeconds = 5
            }
            devops = @{
                enabled = $false
                path = '~/DevOps'
                projectsInclude = @('*')
                projectsExclude = @()
                includeWikis = $false
                setFolderIcon = $true
                retryCount = 3
                retryDelaySeconds = 5
            }
            acr = @{
                enabled = $false
                registries = @()
                imagesInclude = @('*')
                imagesExclude = @()
                retryCount = 3
                retryDelaySeconds = 10
            }
        }
    }
}

function Read-DevBootstrapConfig {
    <#
    .SYNOPSIS
        Loads, normalizes, merges, and validates dev-bootstrap configuration.
    .PARAMETER Path
        Path to the JSON config file.
    .OUTPUTS
        hashtable
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $defaults = Get-DefaultConfig

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Configuration file not found: $Path. Using default configuration."
        return $defaults
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8

        $schemaPath = Join-Path (Split-Path -Parent $Path) 'config.schema.json'
        if ((Test-Path -LiteralPath $schemaPath) -and (Get-Command -Name Test-Json -ErrorAction SilentlyContinue)) {
            $isSchemaValid = Test-Json -Json $raw -SchemaFile $schemaPath
            if (-not $isSchemaValid) {
                throw "Configuration file does not match schema '$schemaPath'."
            }
        }

        $loaded = $raw | ConvertFrom-Json -AsHashtable -Depth 30
    }
    catch {
        throw "Invalid JSON configuration in '$Path': $_"
    }

    $loaded = ConvertTo-AutomationModuleConfig -Config $loaded
    $loaded = ConvertTo-AppInstallerAppSelectionConfig -Config $loaded
    $loaded = ConvertTo-AcrImageFilterConfig -Config $loaded
    $merged = Merge-Hashtable -Default $defaults -Override $loaded
    $merged = ConvertTo-AutomationModuleConfig -Config $merged
    $merged = ConvertTo-AppInstallerAppSelectionConfig -Config $merged
    $merged = ConvertTo-AcrImageFilterConfig -Config $merged
    $errors = @(Test-DevBootstrapConfig -Config $merged)
    if ($errors.Count -gt 0) {
        throw ("Configuration validation failed:`n" + ($errors -join "`n"))
    }

    return $merged
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

function Test-DevBootstrapConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    $errors = [System.Collections.Generic.List[string]]::new()

    if (-not $Config.ContainsKey('general')) {
        $errors.Add("Missing required section 'general'.")
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Config.general.logDirectory)) {
            $errors.Add('general.logDirectory must not be empty.')
        }
    }

    if (-not $Config.ContainsKey('modules')) {
        $errors.Add("Missing required section 'modules'.")
        return , @($errors)
    }

    $githubModule = if ($Config.modules.ContainsKey('github') -and $Config.modules.github -is [System.Collections.IDictionary]) {
        $Config.modules.github
    }
    else {
        $null
    }

    $devOpsModule = if ($Config.modules.ContainsKey('devops') -and $Config.modules.devops -is [System.Collections.IDictionary]) {
        $Config.modules.devops
    }
    else {
        $null
    }

    $acrModule = if ($Config.modules.ContainsKey('acr') -and $Config.modules.acr -is [System.Collections.IDictionary]) {
        $Config.modules.acr
    }
    else {
        $null
    }

    $appInstallerModule = if ($Config.modules.ContainsKey('appInstaller') -and $Config.modules.appInstaller -is [System.Collections.IDictionary]) {
        $Config.modules.appInstaller
    }
    else {
        $null
    }

    $automationModule = if ($Config.modules.ContainsKey('automation') -and $Config.modules.automation -is [System.Collections.IDictionary]) {
        $Config.modules.automation
    }
    else {
        $null
    }

    if ($null -ne $githubModule -and $githubModule.enabled -and [string]::IsNullOrWhiteSpace($githubModule.path)) {
        $errors.Add('modules.github.path must not be empty.')
    }
    elseif ($null -ne $githubModule -and $githubModule.enabled) {
        try {
            $githubPathInput = [string]$githubModule.path
            if ($githubPathInput.Trim().StartsWith('~')) {
                $githubPathInput = Join-Path $HOME $githubPathInput.Trim().Substring(1).TrimStart('/', '\\')
            }

            if (-not [System.IO.Path]::IsPathRooted($githubPathInput)) {
                $errors.Add('modules.github.path must be an absolute path.')
            }

            $null = Resolve-ConfiguredPath -Path $githubModule.path
        }
        catch {
            $errors.Add("modules.github.path is invalid: $($githubModule.path)")
        }
    }

    if ($null -ne $devOpsModule -and $devOpsModule.enabled -and [string]::IsNullOrWhiteSpace($devOpsModule.path)) {
        $errors.Add('modules.devops.path must not be empty.')
    }
    elseif ($null -ne $devOpsModule -and $devOpsModule.enabled) {
        try {
            $devopsPathInput = [string]$devOpsModule.path
            if ($devopsPathInput.Trim().StartsWith('~')) {
                $devopsPathInput = Join-Path $HOME $devopsPathInput.Trim().Substring(1).TrimStart('/', '\\')
            }

            if (-not [System.IO.Path]::IsPathRooted($devopsPathInput)) {
                $errors.Add('modules.devops.path must be an absolute path.')
            }

            $null = Resolve-ConfiguredPath -Path $devOpsModule.path
        }
        catch {
            $errors.Add("modules.devops.path is invalid: $($devOpsModule.path)")
        }
    }

    if ($null -ne $acrModule -and $acrModule.enabled) {
        $tenantId = Get-SecureEnvVariable -Name 'AZURE_TENANT_ID'

        if ([string]::IsNullOrWhiteSpace($tenantId)) {
            $errors.Add('AZURE_TENANT_ID is required when ACR is enabled.')
        }

        $registries = @($acrModule.registries)
        if ($registries.Count -eq 0) {
            $errors.Add('modules.acr.registries requires at least one registry name.')
        }

        if ($null -eq $acrModule.imagesInclude) {
            $errors.Add('modules.acr.imagesInclude must be set (use ["*"] for all images).')
        }
    }

    if ($null -ne $appInstallerModule -and $appInstallerModule.enabled) {
        if ($null -eq $appInstallerModule.recommendedApps -or -not ($appInstallerModule.recommendedApps -is [System.Collections.IDictionary])) {
            $errors.Add('modules.appInstaller.recommendedApps must be a hashtable of boolean flags.')
        }

        if ($null -eq $appInstallerModule.optionalApps -or -not ($appInstallerModule.optionalApps -is [System.Collections.IDictionary])) {
            $errors.Add('modules.appInstaller.optionalApps must be a hashtable of boolean flags.')
        }
    }

    if ($null -ne $automationModule -and $automationModule.enabled) {
        if ($null -eq $automationModule.catalog -or -not ($automationModule.catalog -is [System.Collections.IDictionary])) {
            $errors.Add('modules.automation.catalog must be a hashtable of boolean flags.')
        }

        if ($automationModule.catalog.setGitHubUser) {
            if (-not $automationModule.ContainsKey('gitHubUser') -or -not ($automationModule.gitHubUser -is [System.Collections.IDictionary])) {
                $errors.Add('modules.automation.gitHubUser must be set when modules.automation.catalog.setGitHubUser is enabled.')
            }
            else {
                if ([string]::IsNullOrWhiteSpace([string]$automationModule.gitHubUser.name)) {
                    $errors.Add('modules.automation.gitHubUser.name must not be empty when setGitHubUser is enabled.')
                }

                if ([string]::IsNullOrWhiteSpace([string]$automationModule.gitHubUser.email)) {
                    $errors.Add('modules.automation.gitHubUser.email must not be empty when setGitHubUser is enabled.')
                }
            }
        }
    }

    return , @($errors)
}

function ConvertTo-AppInstallerAppSelectionConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    if (-not $Config.ContainsKey('modules') -or -not $Config.modules.ContainsKey('appInstaller')) {
        return $Config
    }

    $appInstaller = $Config.modules.appInstaller

    if (-not $appInstaller.ContainsKey('recommendedApps') -or $null -eq $appInstaller.recommendedApps) {
        $appInstaller.recommendedApps = @{}
    }

    if (-not $appInstaller.ContainsKey('optionalApps') -or $null -eq $appInstaller.optionalApps) {
        $appInstaller.optionalApps = @{}
    }

    if ($appInstaller.recommendedApps -isnot [System.Collections.IDictionary]) {
        $appInstaller.recommendedApps = @{}
    }

    if ($appInstaller.optionalApps -isnot [System.Collections.IDictionary]) {
        $appInstaller.optionalApps = @{}
    }

    $recommendedKeys = @('gnuWin32Make', 'winget', 'nvmWindows', 'notepadplusplus', 'python31012', 'vscode')
    foreach ($key in $recommendedKeys) {
        if ($appInstaller.optionalApps.ContainsKey($key)) {
            $appInstaller.recommendedApps[$key] = [bool]$appInstaller.optionalApps[$key]
            $appInstaller.optionalApps.Remove($key)
            continue
        }

        if (-not $appInstaller.recommendedApps.ContainsKey($key)) {
            $appInstaller.recommendedApps[$key] = $true
        }
    }

    return $Config
}

function ConvertTo-AcrImageFilterConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    if (-not $Config.ContainsKey('modules') -or -not $Config.modules.ContainsKey('acr')) {
        return $Config
    }

    $acr = $Config.modules.acr

    if ($acr -isnot [System.Collections.IDictionary]) {
        return $Config
    }

    if (-not $acr.ContainsKey('imagesInclude')) {
        if ($acr.ContainsKey('images')) {
            $acr.imagesInclude = @($acr.images)
        }
        else {
            $acr.imagesInclude = @('*')
        }
    }

    if (-not $acr.ContainsKey('imagesExclude') -or $null -eq $acr.imagesExclude) {
        $acr.imagesExclude = @()
    }

    if ($acr.ContainsKey('images')) {
        $acr.Remove('images') | Out-Null
    }

    $acr.imagesInclude = @($acr.imagesInclude)
    $acr.imagesExclude = @($acr.imagesExclude)

    return $Config
}

function ConvertTo-AutomationModuleConfig {
    <#
    .SYNOPSIS
        Migrates legacy 'modules.configurations' key to 'modules.automation'.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    if (-not $Config.ContainsKey('modules')) {
        return $Config
    }

    $modules = $Config.modules
    if ($modules.ContainsKey('configurations') -and -not $modules.ContainsKey('automation')) {
        Write-Warning "Migrating deprecated 'modules.configurations' to 'modules.automation'. Update your config.json to use 'automation' directly."
        $modules['automation'] = $modules['configurations']
        $modules.Remove('configurations')
    }

    return $Config
}
