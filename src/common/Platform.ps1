#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Platform and package manager detection.
#>

function Get-OSPlatform {
    [CmdletBinding()]
    param()

    if ($IsWindows) { return 'Windows' }
    if ($IsLinux) { return 'Linux' }
    if ($IsMacOS) { return 'macOS' }
    return 'Unknown'
}

function Test-IsWindows { return $IsWindows -eq $true }
function Test-IsLinux { return $IsLinux -eq $true }
function Test-IsMacOS { return $IsMacOS -eq $true }

function Test-CommandExists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CommandName)

    return $null -ne (Get-Command -Name $CommandName -ErrorAction SilentlyContinue)
}

function Get-LinuxPackageManager {
    [CmdletBinding()]
    param()

    if (-not (Test-IsLinux)) { return $null }

    $managers = @(
        @{ Name = 'apt'; Command = 'apt-get' }
        @{ Name = 'dnf'; Command = 'dnf' }
        @{ Name = 'yum'; Command = 'yum' }
        @{ Name = 'zypper'; Command = 'zypper' }
    )

    foreach ($manager in $managers) {
        if (Test-CommandExists -CommandName $manager.Command) {
            return $manager
        }
    }

    return $null
}

function Get-WindowsPackageManager {
    [CmdletBinding()]
    param()

    if (-not (Test-IsWindows)) { return $null }

    if (Test-CommandExists -CommandName 'winget') {
        return @{ Name = 'winget'; Command = 'winget' }
    }

    return $null
}

function Write-MacOSFallbackWarning {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FeatureName)

    if (Test-IsMacOS) {
        Write-Log -Level Warning -Message "$FeatureName is not supported on macOS. The operation will be skipped."
        return $true
    }

    return $false
}
