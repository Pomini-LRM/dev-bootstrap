#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$settingsPath = Join-Path $ProjectRoot 'PSScriptAnalyzerSettings.psd1'
if (-not (Test-Path -LiteralPath $settingsPath)) {
    throw "PSScriptAnalyzer settings not found: $settingsPath"
}

if (-not (Get-Command -Name Invoke-Formatter -ErrorAction SilentlyContinue)) {
    throw 'Invoke-Formatter is not available. Install PSScriptAnalyzer first.'
}

$targets = @(
    'dev-bootstrap.ps1'
    'DevBootstrap.psm1'
    'DevBootstrap.psd1'
    'scripts'
    'src'
    'tests'
)

$files = [System.Collections.Generic.List[string]]::new()
foreach ($target in $targets) {
    $resolvedTarget = Join-Path $ProjectRoot $target
    if (-not (Test-Path -LiteralPath $resolvedTarget)) {
        continue
    }

    $item = Get-Item -LiteralPath $resolvedTarget
    if ($item.PSIsContainer) {
        foreach ($file in (Get-ChildItem -LiteralPath $resolvedTarget -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1')) {
            $files.Add($file.FullName)
        }
        continue
    }

    $files.Add($item.FullName)
}

$uniqueFiles = @($files | Sort-Object -Unique)
$changedFiles = [System.Collections.Generic.List[string]]::new()

foreach ($filePath in $uniqueFiles) {
    $original = Get-Content -LiteralPath $filePath -Raw -Encoding utf8
    $preferredLineEnding = if ($original -match "`r`n") { "`r`n" } else { "`n" }
    $normalizedOriginal = $original -replace "`r`n", "`n" -replace "`r", "`n"
    $formatted = Invoke-Formatter -ScriptDefinition $normalizedOriginal -Settings $settingsPath
    if ($preferredLineEnding -eq "`r`n") {
        $formatted = $formatted -replace "(?<!`r)`n", "`r`n"
    }
    if (-not $formatted.EndsWith($preferredLineEnding, [System.StringComparison]::Ordinal)) {
        $formatted += $preferredLineEnding
    }

    if ($formatted -ceq $original) {
        continue
    }

    $changedFiles.Add($filePath)
    if (-not $Check.IsPresent) {
        Set-Content -LiteralPath $filePath -Value $formatted -Encoding utf8
    }
}

if ($Check.IsPresent) {
    if ($changedFiles.Count -gt 0) {
        Write-Error "Formatting check failed for $($changedFiles.Count) file(s):`n$($changedFiles -join "`n")"
        exit 1
    }

    Write-Host "Formatting check passed for $($uniqueFiles.Count) file(s)." -ForegroundColor Green
    exit 0
}

Write-Host "Formatted $($changedFiles.Count) file(s) out of $($uniqueFiles.Count)." -ForegroundColor Green

