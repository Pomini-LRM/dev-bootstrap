#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Copies template VS Code Copilot Chat keybindings to user settings.
#>
param(
    [Parameter(Mandatory)][hashtable]$ModuleConfig,
    [Parameter(Mandatory)][string]$ProjectRoot
)

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
