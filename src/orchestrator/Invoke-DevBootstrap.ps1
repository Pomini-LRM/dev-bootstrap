#Requires -Version 7.0
<#
.SYNOPSIS
    Main orchestrator for dev-bootstrap.
#>

function Invoke-DevBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [ValidateSet('full', 'github', 'devops', 'acr', 'appInstaller')][string]$RunMode = 'full',
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$Force
    )

    $runTimer = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Log -Level Info -Message '============================================='
    Write-Log -Level Info -Message "dev-bootstrap - Run started (mode: $RunMode)"
    Write-Log -Level Info -Message '============================================='

    Import-EnvFile -Path (Join-Path $ProjectRoot '.env')
    Clear-ReportEntries

    if (-not $Config.general.noConfirm -and -not $Config.general.silent) {
        $confirm = Read-HostSafe -Prompt "Proceed with '$RunMode' execution? (Y/n)"
        if ($confirm -and $confirm -notin @('y', 'Y', '')) {
            Write-Log -Level Warning -Message 'Execution canceled by user.'
            return 0
        }
    }

    $moduleDefinitions = @(
        @{
            Name = 'appInstaller'
            Label = 'App Installer'
            Enabled = $Config.modules.appInstaller.enabled
            ScriptPath = Join-Path $ProjectRoot 'src' 'modules' 'Install-Apps.ps1'
            Invoke = { param($c, $p, $f) Invoke-AppInstaller -Config $c -ProjectRoot $p -Force:$f }
        }
        @{
            Name = 'github'
            Label = 'GitHub Sync'
            Enabled = $Config.modules.github.enabled
            ScriptPath = Join-Path $ProjectRoot 'src' 'modules' 'Sync-GitHubRepos.ps1'
            Invoke = { param($c, $p, $f) Invoke-GitHubSync -Config $c -ProjectRoot $p -Force:$f }
        }
        @{
            Name = 'devops'
            Label = 'Azure DevOps Sync'
            Enabled = $Config.modules.devops.enabled
            ScriptPath = Join-Path $ProjectRoot 'src' 'modules' 'Sync-DevOpsRepos.ps1'
            Invoke = { param($c, $p, $f) Invoke-DevOpsSync -Config $c -ProjectRoot $p -Force:$f }
        }
        @{
            Name = 'acr'
            Label = 'ACR Image Sync'
            Enabled = $Config.modules.acr.enabled
            ScriptPath = Join-Path $ProjectRoot 'src' 'modules' 'Sync-AcrImages.ps1'
            Invoke = { param($c, $p, $f) Invoke-AcrSync -Config $c -ProjectRoot $p -Force:$f }
        }
    )

    $modulesToRun = if ($RunMode -eq 'full') {
        $moduleDefinitions | Where-Object { $_.Enabled }
    }
    else {
        $moduleDefinitions | Where-Object { $_.Name -eq $RunMode }
    }

    if (@($modulesToRun).Count -eq 0) {
        Write-Log -Level Warning -Message 'No module selected for execution. Check configuration and run mode.'
        $runTimer.Stop()
        $errorCount = 0
        return $(if ($errorCount -gt 0) { 1 } else { 0 })
    }

    $failFast = $Config.general.failFast
    $hasCriticalError = $false
    $moduleExecutions = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($module in $modulesToRun) {
        if ($hasCriticalError -and $failFast) {
            Add-ReportEntry -Entry (New-ReportEntry -Module $module.Label -Item 'MODULE' -Status 'SKIPPED' -Message 'Skipped due to fail-fast policy.')
            $moduleExecutions.Add(@{
                Module = $module.Label
                Status = 'SKIPPED'
                Items = 0
                Errors = 0
                Duration = [TimeSpan]::Zero
            })
            continue
        }

        . $module.ScriptPath
        Start-StepTimer -StepName $module.Label

        $moduleStatus = 'SUCCESS'
        $moduleItemCount = 0
        $moduleErrorCount = 0
        $stepDuration = [TimeSpan]::Zero

        try {
            Write-Log -Level Info -Message "Executing module: $($module.Label)"
            $moduleResults = & $module.Invoke $Config $ProjectRoot $Force.IsPresent
            $moduleResultList = @($moduleResults)
            $moduleItemCount = $moduleResultList.Count

            if ($moduleItemCount -gt 0) {
                Add-ReportEntries -Entries $moduleResultList
                Write-Log -Level Info -Message ''
                Write-StatusSummaryTable -Title "Module summary: $($module.Label)" -Entries $moduleResultList

                $moduleErrorEntries = @($moduleResultList | Where-Object { $_.Status -eq 'ERROR' })
                foreach ($errorEntry in $moduleErrorEntries) {
                    $msg = if ([string]::IsNullOrWhiteSpace([string]$errorEntry.Message)) { 'No error details.' } else { [string]$errorEntry.Message }
                    Write-Log -Level Error -Message "  ERROR $($errorEntry.Item) - $msg"
                }
            }

            $moduleErrorCount = @($moduleResultList | Where-Object { $_.Status -eq 'ERROR' }).Count
            if ($moduleErrorCount -gt 0) {
                $moduleStatus = 'ERROR'
                Write-Log -Level Warning -Message "Module $($module.Label) completed with $moduleErrorCount errors."
                if ($failFast) { $hasCriticalError = $true }
            }
        }
        catch {
            $moduleStatus = 'ERROR'
            $moduleErrorCount = [Math]::Max($moduleErrorCount, 1)
            Write-Log -Level Error -Message "Module $($module.Label) failed with exception: $_"
            Add-ReportEntry -Entry (New-ReportEntry -Module $module.Label -Item 'MODULE' -Status 'ERROR' -Message "Exception: $_")
            if ($failFast) { $hasCriticalError = $true }
        }
        finally {
            $stepDuration = Stop-StepTimer -StepName $module.Label
        }

        $moduleExecutions.Add(@{
            Module = $module.Label
            Status = $moduleStatus
            Items = $moduleItemCount
            Errors = $moduleErrorCount
            Duration = $stepDuration
        })
    }

    $runTimer.Stop()
    $entries = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($item in @(Get-ReportEntries)) {
        if ($item -is [hashtable]) {
            $entries.Add($item)
            continue
        }

        if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string])) {
            foreach ($inner in $item) {
                if ($inner -is [hashtable]) {
                    $entries.Add($inner)
                }
            }
        }
    }

    $errorCount = @($entries | Where-Object { $_.Status -eq 'ERROR' }).Count
    Write-ReportRemediationSteps -Entries $entries

    Write-ModuleExecutionSummary -ModuleExecutions $moduleExecutions -TotalOperations $entries.Count -ErrorCount $errorCount -TotalDuration $runTimer.Elapsed

    Write-Log -Level Info -Message "Log file: $(Get-LogFilePath)"
    Write-Log -Level Info -Message '============================================='
    Write-Log -Level Info -Message 'dev-bootstrap - Run completed'
    Write-Log -Level Info -Message '============================================='

    return $(if ($errorCount -gt 0) { 1 } else { 0 })
}

function Read-HostSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Prompt)

    try { return Read-Host -Prompt $Prompt }
    catch { return '' }
}

function Write-ModuleExecutionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$ModuleExecutions,
        [Parameter(Mandatory)][int]$TotalOperations,
        [Parameter(Mandatory)][int]$ErrorCount,
        [Parameter(Mandatory)][TimeSpan]$TotalDuration
    )

    $rows = @($ModuleExecutions)
    Write-Log -Level Info -Message ''
    Write-Log -Level Info -Message 'Module execution summary:'
    Write-Log -Level Info -Message '  MODULE                 STATUS      ITEMS  ERRORS  DURATION'
    Write-Log -Level Info -Message '  ---------------------  ----------  -----  ------  ------------'

    foreach ($row in $rows) {
        $durationText = [TimeSpan]$row.Duration
        $moduleText = ([string]$row.Module).PadRight(21)
        $statusText = ([string]$row.Status).PadRight(10)
        $itemsText = ([string]$row.Items).PadLeft(5)
        $errorsText = ([string]$row.Errors).PadLeft(6)
        Write-Log -Level Info -Message "  $moduleText  $statusText  $itemsText  $errorsText  $($durationText.ToString('hh\:mm\:ss'))"
    }

    $totalDurationText = if ($TotalDuration.TotalHours -ge 1) {
        $TotalDuration.ToString('hh\:mm\:ss\.fff')
    }
    else {
        $TotalDuration.ToString('mm\:ss\.fff')
    }

    $totalModuleText = 'TOTAL'.PadRight(21)
    $totalStatusText = ''.PadRight(10)
    $totalItemsText = ([string]$TotalOperations).PadLeft(5)
    $totalErrorsText = ([string]$ErrorCount).PadLeft(6)
    Write-Log -Level Info -Message "  $totalModuleText  $totalStatusText  $totalItemsText  $totalErrorsText  $totalDurationText"
}
