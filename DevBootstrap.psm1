#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.

$moduleRoot = Split-Path -Parent $PSCommandPath

$filesToLoad = @(
    'src/common/Logger.ps1'
    'src/common/Filters.ps1'
    'src/common/Config.ps1'
    'src/common/Platform.ps1'
    'src/common/Report.ps1'
    'src/common/Utilities.ps1'
    'src/common/Version.ps1'
    'src/orchestrator/Invoke-DevBootstrap.ps1'
    'src/modules/Install-Apps.ps1'
    'src/modules/Invoke-Automation.ps1'
    'src/modules/Sync-GitHubRepos.ps1'
    'src/modules/Sync-DevOpsRepos.ps1'
    'src/modules/Sync-AcrImages.ps1'
)

foreach ($relativePath in $filesToLoad) {
    . (Join-Path $moduleRoot $relativePath)
}

Export-ModuleMember -Function @(
    'Invoke-DevBootstrap',
    'Read-DevBootstrapConfig',
    'Get-DevBootstrapVersion',
    'Initialize-Logger',
    'Write-Log',
    'Import-EnvFile'
)
