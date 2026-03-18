#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Sets global git user.name and user.email.
#>
param(
    [Parameter(Mandatory)][hashtable]$ModuleConfig,
    [Parameter(Mandatory)][string]$ProjectRoot
)

$name = [string]$ModuleConfig.gitHubUser.name
$email = [string]$ModuleConfig.gitHubUser.email

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
