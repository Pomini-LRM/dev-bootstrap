#!/usr/bin/env pwsh
#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.

<#
.SYNOPSIS
    Builds a Windows release package with EXE, config, and user documentation.

.DESCRIPTION
    Builds a bundled entry script that inlines runtime source modules,
    compiles it into dev-bootstrap.exe using PS2EXE,
    prepares a distributable folder with user-facing docs,
    and produces a ZIP + SHA256 file.
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory,
    [switch]$IncludeUserConfig,
    [switch]$SkipModuleInstall,
    [switch]$SkipExeBuild,
    [string]$GitHubOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ReleaseVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$VersionFilePath)

    if (-not (Test-Path -LiteralPath $VersionFilePath)) {
        throw "Version file not found: $VersionFilePath"
    }

    $raw = Get-Content -LiteralPath $VersionFilePath -Raw -Encoding utf8
    $json = $raw | ConvertFrom-Json -AsHashtable -Depth 5
    $version = if ($json.ContainsKey('version')) { [string]$json.version } else { '' }

    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "Version file '$VersionFilePath' does not define a valid 'version' value."
    }

    return $version.Trim()
}

function Get-PS2EXECommand {
    [CmdletBinding()]
    param([switch]$NoInstall)

    $invokeCommand = Get-Command -Name Invoke-PS2EXE -ErrorAction SilentlyContinue
    if ($null -eq $invokeCommand) {
        $invokeCommand = Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue
    }

    if ($null -ne $invokeCommand) {
        return $invokeCommand.Name
    }

    if ($NoInstall) {
        throw 'PS2EXE is not installed. Install module ps2exe or rerun without -SkipModuleInstall.'
    }

    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name ps2exe -Scope CurrentUser -Force

    $invokeCommand = Get-Command -Name Invoke-PS2EXE -ErrorAction SilentlyContinue
    if ($null -eq $invokeCommand) {
        $invokeCommand = Get-Command -Name Invoke-ps2exe -ErrorAction SilentlyContinue
    }

    if ($null -eq $invokeCommand) {
        throw 'PS2EXE installation succeeded but invoke command was not found.'
    }

    return $invokeCommand.Name
}

function Get-NormalizedScriptContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$StripModuleDotSource,
        [switch]$StripEntrypointDotSource
    )

    $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $content = [regex]::Replace($content, '(?m)^#!/usr/bin/env pwsh\s*\r?\n', '')
    $content = [regex]::Replace($content, '(?m)^#Requires\s+-Version\s+.+\r?\n', '')

    if ($StripModuleDotSource) {
        $content = [regex]::Replace($content, '(?m)^\s*\.\s+\$module\.ScriptPath\s*\r?\n', '')
    }

    if ($StripEntrypointDotSource) {
        $content = [regex]::Replace($content, '(?m)^\s*\.\s*\(Join-Path\s+\$projectRoot\s+''src''.+\)\s*\r?\n', '')
    }

    return $content.Trim() + "`r`n"
}

function Get-BundledEntrypointParts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $content = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $content = [regex]::Replace($content, '(?m)^#!/usr/bin/env pwsh\s*\r?\n', '')
    $content = [regex]::Replace($content, '(?m)^#Requires\s+-Version\s+.+\r?\n', '')

    $cmdletBindingIndex = $content.IndexOf('[CmdletBinding()]', [System.StringComparison]::OrdinalIgnoreCase)
    if ($cmdletBindingIndex -lt 0) {
        throw "Unable to locate [CmdletBinding()] in entrypoint: $Path"
    }

    $paramKeywordIndex = $content.IndexOf('param(', $cmdletBindingIndex, [System.StringComparison]::OrdinalIgnoreCase)
    if ($paramKeywordIndex -lt 0) {
        throw "Unable to locate script param() block in entrypoint: $Path"
    }

    $paramOpenIndex = $content.IndexOf('(', $paramKeywordIndex)
    if ($paramOpenIndex -lt 0) {
        throw "Unable to locate opening parenthesis for param() in entrypoint: $Path"
    }

    $depth = 0
    $paramCloseIndex = -1
    for ($index = $paramOpenIndex; $index -lt $content.Length; $index++) {
        $char = $content[$index]
        if ($char -eq '(') {
            $depth++
            continue
        }

        if ($char -eq ')') {
            $depth--
            if ($depth -eq 0) {
                $paramCloseIndex = $index
                break
            }
        }
    }

    if ($paramCloseIndex -lt 0) {
        throw "Unable to locate closing parenthesis for param() in entrypoint: $Path"
    }

    $paramBlock = $content.Substring($cmdletBindingIndex, ($paramCloseIndex - $cmdletBindingIndex + 1)).Trim()
    $body = $content.Substring($paramCloseIndex + 1)
    $body = [regex]::Replace($body, '(?m)^\s*\.\s*\(Join-Path\s+\$projectRoot\s+''src''.+\)\s*\r?\n', '')

    return @{
        ParamBlock = $paramBlock
        Body = ($body.Trim() + "`r`n")
    }
}

function New-BundledEntrypointScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $sourceFiles = @(
        'src/common/Logger.ps1'
        'src/common/Filters.ps1'
        'src/common/Config.ps1'
        'src/common/Platform.ps1'
        'src/common/Report.ps1'
        'src/common/Utilities.ps1'
        'src/common/Version.ps1'
        'src/modules/Install-Apps.ps1'
        'src/modules/Invoke-Automation.ps1'
        'src/modules/Sync-GitHubRepos.ps1'
        'src/modules/Sync-DevOpsRepos.ps1'
        'src/modules/Sync-AcrImages.ps1'
        'src/orchestrator/Invoke-DevBootstrap.ps1'
    )

    $entrypointPath = Join-Path $ProjectRoot 'dev-bootstrap.ps1'
    if (-not (Test-Path -LiteralPath $entrypointPath)) {
        throw "Entrypoint file not found: $entrypointPath"
    }

    $entrypointParts = Get-BundledEntrypointParts -Path $entrypointPath

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('#Requires -Version 7.0')
    [void]$builder.AppendLine('# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.')
    [void]$builder.AppendLine('# Generated by scripts/Build-WindowsReleasePackage.ps1')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine($entrypointParts.ParamBlock)
    [void]$builder.AppendLine()

    foreach ($relativePath in $sourceFiles) {
        $absolutePath = Join-Path $ProjectRoot $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath)) {
            throw "Source file not found for bundling: $absolutePath"
        }

        $stripModuleDotSource = $relativePath -eq 'src/orchestrator/Invoke-DevBootstrap.ps1'
        $content = Get-NormalizedScriptContent -Path $absolutePath -StripModuleDotSource:$stripModuleDotSource

        [void]$builder.AppendLine("# region bundled: $relativePath")
        [void]$builder.AppendLine($content)
        [void]$builder.AppendLine("# endregion bundled: $relativePath")
        [void]$builder.AppendLine()
    }

    [void]$builder.AppendLine('# region bundled entrypoint body')
    [void]$builder.AppendLine($entrypointParts.Body)
    [void]$builder.AppendLine('# endregion bundled entrypoint body')

    Set-Content -LiteralPath $OutputPath -Value $builder.ToString() -Encoding utf8
}

function Get-UserDocumentationPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    return @(
        'LICENSE'
        'README.md'
        'QUICK_START.md'
        'SECURITY.md'
        'docs/troubleshooting-fresh-install.md'
        'docs/acr-authentication.md'
        'docs/azure-devops-pat.md'
        'docs/github-classic-token.md'
    )
}

if (-not $IsWindows) {
    throw 'Build-WindowsReleasePackage.ps1 must run on Windows.'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot 'artifacts'
}

$entryScriptPath = Join-Path $ProjectRoot 'dev-bootstrap.ps1'
$envExamplePath = Join-Path $ProjectRoot '.env.example'
$versionPath = Join-Path $ProjectRoot 'config' 'version.json'

if (-not (Test-Path -LiteralPath $entryScriptPath)) {
    throw "Entry script not found: $entryScriptPath"
}
if (-not (Test-Path -LiteralPath $envExamplePath)) {
    throw "Environment template not found: $envExamplePath"
}

$version = Get-ReleaseVersion -VersionFilePath $versionPath
$releaseBaseName = "dev-bootstrap-windows-v$version"
$stagingRoot = Join-Path $OutputDirectory $releaseBaseName
$zipPath = Join-Path $OutputDirectory "$releaseBaseName.zip"
$shaPath = "$zipPath.sha256"
$exePath = Join-Path $stagingRoot 'dev-bootstrap.exe'

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
if (Test-Path -LiteralPath $shaPath) {
    Remove-Item -LiteralPath $shaPath -Force
}

New-Item -Path $stagingRoot -ItemType Directory -Force | Out-Null

if (-not $SkipExeBuild) {
    $invokePs2ExeCommand = Get-PS2EXECommand -NoInstall:$SkipModuleInstall
    $bundledScriptPath = Join-Path $env:TEMP "dev-bootstrap-bundled-$version.ps1"
    New-BundledEntrypointScript -ProjectRoot $ProjectRoot -OutputPath $bundledScriptPath

    try {
        & $invokePs2ExeCommand `
            -inputFile $bundledScriptPath `
            -outputFile $exePath `
            -x64 `
            -title 'dev-bootstrap' `
            -description 'POMINI dev-bootstrap'

        if ($LASTEXITCODE -ne 0) {
            throw "PS2EXE compilation failed with exit code: $LASTEXITCODE"
        }
    }
    finally {
        if (Test-Path -LiteralPath $bundledScriptPath) {
            Remove-Item -LiteralPath $bundledScriptPath -Force
        }
    }
}
else {
    Set-Content -LiteralPath $exePath -Value 'EXE build skipped by request.' -Encoding ascii
}

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Executable not found after build: $exePath"
}

Copy-Item -LiteralPath $envExamplePath -Destination (Join-Path $stagingRoot '.env.example') -Force
Copy-Item -LiteralPath $envExamplePath -Destination (Join-Path $stagingRoot '.env') -Force

foreach ($path in @('config')) {
    $source = Join-Path $ProjectRoot $path
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $stagingRoot $path) -Recurse -Force
    }
}

foreach ($relativeDocPath in (Get-UserDocumentationPaths -ProjectRoot $ProjectRoot)) {
    $sourceDocPath = Join-Path $ProjectRoot $relativeDocPath
    if (-not (Test-Path -LiteralPath $sourceDocPath)) {
        continue
    }

    $destinationDocPath = Join-Path $stagingRoot $relativeDocPath
    $destinationDirectory = Split-Path -Parent $destinationDocPath
    if (-not [string]::IsNullOrWhiteSpace($destinationDirectory)) {
        New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null
    }

    Copy-Item -LiteralPath $sourceDocPath -Destination $destinationDocPath -Force
}

if (-not $IncludeUserConfig) {
    $userConfigPath = Join-Path $stagingRoot 'config' 'config.json'
    if (Test-Path -LiteralPath $userConfigPath) {
        Remove-Item -LiteralPath $userConfigPath -Force
    }
}

$backupFiles = Get-ChildItem -LiteralPath $stagingRoot -Recurse -File |
    Where-Object { $_.Name -match '\.bak(\.|$)' }
foreach ($backupFile in $backupFiles) {
    Remove-Item -LiteralPath $backupFile.FullName -Force
}

$scriptFiles = Get-ChildItem -LiteralPath $stagingRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1'
foreach ($scriptFile in $scriptFiles) {
    Remove-Item -LiteralPath $scriptFile.FullName -Force
}

$forbiddenFiles = @(Get-ChildItem -LiteralPath $stagingRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1')
if ($forbiddenFiles.Count -gt 0) {
    $names = @($forbiddenFiles | ForEach-Object { $_.FullName }) -join ', '
    throw "Release package contains forbidden PowerShell source files: $names"
}

Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $zipPath -Force
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
"$hash  $([System.IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath $shaPath -Encoding ascii

Write-Host "Release package folder: $stagingRoot" -ForegroundColor Green
Write-Host "Release ZIP          : $zipPath" -ForegroundColor Green
Write-Host "SHA256 file          : $shaPath" -ForegroundColor Green
Write-Host "SHA256               : $hash"

if (-not [string]::IsNullOrWhiteSpace($GitHubOutputPath)) {
    Add-Content -LiteralPath $GitHubOutputPath -Value "exe_path=$exePath"
    Add-Content -LiteralPath $GitHubOutputPath -Value "exe_name=$([System.IO.Path]::GetFileName($exePath))"
    Add-Content -LiteralPath $GitHubOutputPath -Value "zip_path=$zipPath"
    Add-Content -LiteralPath $GitHubOutputPath -Value "zip_name=$([System.IO.Path]::GetFileName($zipPath))"
    Add-Content -LiteralPath $GitHubOutputPath -Value "sha_path=$shaPath"
    Add-Content -LiteralPath $GitHubOutputPath -Value "sha_name=$([System.IO.Path]::GetFileName($shaPath))"
    Add-Content -LiteralPath $GitHubOutputPath -Value "sha256=$hash"
    Add-Content -LiteralPath $GitHubOutputPath -Value "version=$version"
}
