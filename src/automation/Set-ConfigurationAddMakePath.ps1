#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Adds GnuWin32\bin to the Windows user PATH.
#>
param(
    [Parameter(Mandatory)][hashtable]$ModuleConfig,
    [Parameter(Mandatory)][string]$ProjectRoot
)

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
