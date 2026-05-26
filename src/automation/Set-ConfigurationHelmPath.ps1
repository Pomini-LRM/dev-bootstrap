#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Adds Helm installation path to the Windows user PATH.
#>
param(
    [Parameter(Mandatory)][hashtable]$ModuleConfig,
    [Parameter(Mandatory)][string]$ProjectRoot
)

if (-not (Test-IsWindows)) {
    return @{ Status = 'SKIPPED'; Message = 'Unsupported platform. Windows only.' }
}

$candidates = [System.Collections.Generic.List[string]]::new()
if ($env:LOCALAPPDATA) {
    $candidates.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'))
}

$candidates.Add('C:\Program Files\Helm')
$candidates.Add('C:\Program Files (x86)\Helm')

$existingHelmPath = $null
foreach ($candidateRoot in $candidates) {
    if (-not (Test-Path -LiteralPath $candidateRoot)) {
        continue
    }

    $helmBinary = Get-ChildItem -Path $candidateRoot -Recurse -Filter 'helm.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -ne $helmBinary) {
        $existingHelmPath = Split-Path -Parent $helmBinary.FullName
        break
    }
}

if (-not $existingHelmPath) {
    return @{ Status = 'SKIPPED'; Message = 'Helm path not found. Install Helm first.' }
}

$userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
$segments = @($userPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($segments -contains $existingHelmPath) {
    return @{ Status = 'NONE'; Message = "Path already present: $existingHelmPath" }
}

$newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $existingHelmPath } else { "$userPath;$existingHelmPath" }
[System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')

if (-not ($env:Path -split ';' | Where-Object { $_ -eq $existingHelmPath })) {
    $env:Path = "$env:Path;$existingHelmPath"
}

return @{ Status = 'UPDATED'; Message = "Added to user PATH: $existingHelmPath" }
