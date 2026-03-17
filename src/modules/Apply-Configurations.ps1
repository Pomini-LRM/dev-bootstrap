#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Local machine configuration module.
#>

function Invoke-Configurations {
    <#
    .SYNOPSIS
        Applies selected local workstation configurations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$Force
    )

    $moduleConfig = $Config.modules.configurations
    $results = [System.Collections.Generic.List[hashtable]]::new()

    $catalog = Read-ConfigurationsCatalog -ProjectRoot $ProjectRoot
    $catalogByKey = @{}
    foreach ($item in @($catalog.configurations)) {
        $catalogByKey[[string]$item.key] = $item
    }

    $enabledFlags = @($moduleConfig.catalog.Keys | Where-Object { [bool]$moduleConfig.catalog[$_] })
    if ($enabledFlags.Count -eq 0) {
        $results.Add((New-ReportEntry -Module 'Configurations' -Item 'catalog' -Status 'SKIPPED' -Message 'No configuration item enabled.'))
        return $results
    }

    Write-Log -Level Info -Message "Configuration items enabled: $($enabledFlags.Count)"

    $itemIndex = 0
    foreach ($key in $enabledFlags) {
        $itemIndex++
        $name = if ($catalogByKey.ContainsKey($key)) { [string]$catalogByKey[$key].name } else { [string]$key }
        Write-Log -Level Info -Message "Configuration [$itemIndex/$($enabledFlags.Count)]: $name"
        $timer = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $result = switch ($key) {
                'addMakePath' { Set-ConfigurationAddMakePath -Config $moduleConfig }
                'addCopilotChatKeybindings' { Set-ConfigurationCopilotChatKeybindings -ProjectRoot $ProjectRoot }
                'setGitHubUser' { Set-ConfigurationGitHubUser -Config $moduleConfig }
                'desktopLinkForThisApplication' { Set-ConfigurationDesktopLinkForApplication -ProjectRoot $ProjectRoot }
                default { @{ Status = 'SKIPPED'; Message = "Unknown configuration key '$key'." } }
            }

            $timer.Stop()
            $entry = New-ReportEntry -Module 'Configurations' -Item $name -Status $result.Status -Message $result.Message -Duration $timer.Elapsed
            $results.Add($entry)
            Write-ConfigurationsEntryLog -Entry $entry
        }
        catch {
            $timer.Stop()
            $entry = New-ReportEntry -Module 'Configurations' -Item $name -Status 'ERROR' -Message "$_" -Duration $timer.Elapsed
            $results.Add($entry)
            Write-ConfigurationsEntryLog -Entry $entry
        }
    }

    return $results
}

function Read-ConfigurationsCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $catalogPath = Join-Path $ProjectRoot 'config' 'configurations.catalog.json'
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        throw "Configurations catalog not found: $catalogPath"
    }

    $raw = Get-Content -LiteralPath $catalogPath -Raw -Encoding utf8
    $catalog = $raw | ConvertFrom-Json -AsHashtable -Depth 20

    if (-not $catalog.ContainsKey('configurations') -or @($catalog.configurations).Count -eq 0) {
        throw "Configurations catalog '$catalogPath' must define a non-empty 'configurations' array."
    }

    return $catalog
}

function Set-ConfigurationAddMakePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    if (-not (Test-IsWindows)) {
        return @{ Status = 'SKIPPED'; Message = 'Unsupported platform. Windows only.' }
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles 'GnuWin32\bin'))
    }

    $programFiles86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFiles86)) {
        $candidates.Add((Join-Path $programFiles86 'GnuWin32\bin'))
    }

    $candidates.Add('C:\GnuWin32\bin')

    $existingMakePath = $null
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'make.exe')) {
            $existingMakePath = $candidate
            break
        }
    }

    if (-not $existingMakePath) {
        return @{ Status = 'SKIPPED'; Message = 'GnuWin32.Make path not found. Install app first.' }
    }

    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $segments = @($userPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($segments -contains $existingMakePath) {
        return @{ Status = 'NONE'; Message = "Path already present: $existingMakePath" }
    }

    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $existingMakePath } else { "$userPath;$existingMakePath" }
    [System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')

    if (-not ($env:Path -split ';' | Where-Object { $_ -eq $existingMakePath })) {
        $env:Path = "$env:Path;$existingMakePath"
    }

    return @{ Status = 'UPDATED'; Message = "Added to user PATH: $existingMakePath" }
}

function Set-ConfigurationCopilotChatKeybindings {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    if (-not (Test-IsWindows)) {
        return @{ Status = 'SKIPPED'; Message = 'Unsupported platform. Windows only.' }
    }

    $source = Join-Path $ProjectRoot 'config' 'templates' 'keybindings.json'
    if (-not (Test-Path -LiteralPath $source)) {
        return @{ Status = 'ERROR'; Message = "Template not found: $source" }
    }

    $destinationRoot = Join-Path $env:APPDATA 'Code' 'User'
    if (-not (Test-Path -LiteralPath $destinationRoot)) {
        New-Item -Path $destinationRoot -ItemType Directory -Force | Out-Null
    }

    $destination = Join-Path $destinationRoot 'keybindings.json'
    if (Test-Path -LiteralPath $destination) {
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($sourceHash -eq $destinationHash) {
            return @{ Status = 'NONE'; Message = "Keybindings already up to date: $destination" }
        }
    }

    Copy-Item -LiteralPath $source -Destination $destination -Force

    return @{ Status = 'UPDATED'; Message = "Keybindings copied to: $destination" }
}

function Set-ConfigurationGitHubUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Config)

    $name = [string]$Config.gitHubUser.name
    $email = [string]$Config.gitHubUser.email

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($email)) {
        return @{ Status = 'ERROR'; Message = 'gitHubUser.name and gitHubUser.email are required.' }
    }

    if (-not (Test-CommandExists -CommandName 'git')) {
        return @{ Status = 'ERROR'; Message = 'git is not installed.' }
    }

    $currentName = [string](& git config --global --get user.name 2>$null)
    $currentEmail = [string](& git config --global --get user.email 2>$null)
    $currentName = $currentName.Trim()
    $currentEmail = $currentEmail.Trim()

    if ($currentName -eq $name -and $currentEmail -eq $email) {
        return @{ Status = 'NONE'; Message = "git global identity already set: $name <$email>" }
    }

    & git config --global user.name $name 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return @{ Status = 'ERROR'; Message = 'Failed to set git global user.name.' }
    }

    & git config --global user.email $email 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return @{ Status = 'ERROR'; Message = 'Failed to set git global user.email.' }
    }

    return @{ Status = 'UPDATED'; Message = "git global identity updated: $name <$email>" }
}

function Set-ConfigurationDesktopLinkForApplication {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    if (-not (Test-IsWindows)) {
        return @{ Status = 'SKIPPED'; Message = 'Unsupported platform. Windows only.' }
    }

    $scriptPath = Join-Path $ProjectRoot 'dev-bootstrap.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        return @{ Status = 'ERROR'; Message = "Script not found: $scriptPath" }
    }

    $iconPath = Join-Path $ProjectRoot 'config' 'icons' 'dev-bootstrap.ico'
    if (-not (Test-Path -LiteralPath $iconPath)) {
        return @{ Status = 'ERROR'; Message = "Icon not found: $iconPath" }
    }

    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        return @{ Status = 'ERROR'; Message = 'Desktop path not available for current user.' }
    }

    $shortcutPath = Join-Path $desktopPath 'dev-bootstrap.lnk'
    if (Test-Path -LiteralPath $shortcutPath) {
        return @{ Status = 'NONE'; Message = "Desktop shortcut already set: $shortcutPath" }
    }

    $launcherPath = Join-Path $ProjectRoot 'dev-bootstrap-launcher.cmd'
    $launcherContent = @(
        '@echo off',
        'setlocal',
        'where pwsh >nul 2>nul',
        'if %errorlevel%==0 (',
        '  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-bootstrap.ps1" %*',
        ') else (',
        '  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-bootstrap.ps1" %*',
        ')',
        'echo.',
        'pause',
        'endlocal'
    ) -join "`r`n"

    $writeLauncher = $true
    if (Test-Path -LiteralPath $launcherPath) {
        $existingLauncher = Get-Content -LiteralPath $launcherPath -Raw -Encoding ascii
        if ($existingLauncher -eq $launcherContent) {
            $writeLauncher = $false
        }
    }

    if ($writeLauncher) {
        Set-Content -LiteralPath $launcherPath -Value $launcherContent -Encoding ascii -Force
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $launcherPath
    $shortcut.Arguments = ''
    $shortcut.WorkingDirectory = $ProjectRoot
    $shortcut.IconLocation = "$iconPath,0"
    $shortcut.Description = 'Run dev-bootstrap'
    $shortcut.Save()

    return @{ Status = 'UPDATED'; Message = "Desktop shortcut created: $shortcutPath" }
}

function Write-ConfigurationsEntryLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Entry)

    $level = if ($Entry.Status -eq 'ERROR') { 'Error' } else { 'Info' }
    $durationText = if ($Entry.Duration -gt [TimeSpan]::Zero) { " ($($Entry.Duration.ToString('hh\:mm\:ss')))" } else { '' }
    $actionText = if ([string]::IsNullOrWhiteSpace([string]$Entry.Message)) { 'Configuration processed.' } else { [string]$Entry.Message }

    Write-Log -Level $level -Message "  Action: $actionText"
    Write-Log -Level $level -Message "  Status: $($Entry.Status)$durationText"
}
