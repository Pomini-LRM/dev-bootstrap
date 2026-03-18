#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Creates a desktop shortcut for dev-bootstrap with custom icon.
#>
param(
    [Parameter(Mandatory)][hashtable]$ModuleConfig,
    [Parameter(Mandatory)][string]$ProjectRoot
)

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
if (-not (Test-Path -LiteralPath $launcherPath)) {
    return @{ Status = 'ERROR'; Message = "Launcher not found: $launcherPath" }
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
