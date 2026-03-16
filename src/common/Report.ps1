#Requires -Version 7.0
<#
.SYNOPSIS
    Unified final reporting for dev-bootstrap.
#>

$script:_ReportEntries = [System.Collections.Generic.List[hashtable]]::new()

function New-ReportEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Module,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)][ValidateSet('ADDED', 'UPDATED', 'NONE', 'SKIPPED', 'ERROR', 'ORPHAN', 'INSTALLED', 'ALREADY_PRESENT')][string]$Status,
        [string]$Message = '',
        [TimeSpan]$Duration = [TimeSpan]::Zero
    )

    return @{
        Module = $Module
        Item = $Item
        Status = $Status
        Message = $Message
        Duration = $Duration
    }
}

function Add-ReportEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Entry)

    $script:_ReportEntries.Add($Entry)
}

function Add-ReportEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IEnumerable]$Entries)

    foreach ($entry in $Entries) {
        $script:_ReportEntries.Add($entry)
    }
}

function Get-ReportEntries { , $script:_ReportEntries }
function Clear-ReportEntries { $script:_ReportEntries.Clear() }

function Write-FinalReport {
    [CmdletBinding()]
    param([TimeSpan]$TotalDuration = [TimeSpan]::Zero)

    $entries = $script:_ReportEntries

    Write-Log -Level Info -Message ''
    Write-Log -Level Info -Message '================ Final Report ================'

    if ($entries.Count -eq 0) {
        Write-Log -Level Warning -Message 'No operations were executed.'
        return 0
    }

    $moduleGroups = $entries | Group-Object -Property { $_.Module }
    foreach ($moduleGroup in $moduleGroups) {
        Write-Log -Level Info -Message ''
        Write-Log -Level Info -Message "Module: $($moduleGroup.Name) ($($moduleGroup.Count) items)"

        foreach ($entry in $moduleGroup.Group) {
            $durationText = if ($entry.Duration -gt [TimeSpan]::Zero) { " ($($entry.Duration.ToString('hh\:mm\:ss')))" } else { '' }
            $messageText = if ($entry.Message) { " - $($entry.Message)" } else { '' }
            $entryLevel = if ($entry.Status -eq 'ERROR') { 'Error' } else { 'Info' }
            Write-Log -Level $entryLevel -Message "  $($entry.Status.PadRight(15)) $($entry.Item)$durationText$messageText"
        }
    }

    Write-Log -Level Info -Message ''
    Write-StatusSummaryTable -Title 'Summary:' -Entries $entries

    $errorCount = @($entries | Where-Object { $_.Status -eq 'ERROR' }).Count
    Write-ReportRemediationSteps -Entries $entries

    Write-Log -Level Info -Message ''
    Write-Log -Level Info -Message "Total operations : $($entries.Count)"
    Write-Log -Level Info -Message "Errors           : $errorCount"
    Write-Log -Level Info -Message "Total duration   : $($TotalDuration.ToString('hh\:mm\:ss\.fff'))"

    return $errorCount
}

function Write-StatusSummaryTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Entries
    )

    $entryList = @($Entries)
    if ($entryList.Count -eq 0) {
        Write-Log -Level Info -Message $Title
        Write-Log -Level Info -Message '  (no items)'
        return
    }

    Write-Log -Level Info -Message $Title
    Write-Log -Level Info -Message '  STATUS           COUNT'
    Write-Log -Level Info -Message '  ---------------  -----'

    $statusGroups = $entryList | Group-Object -Property { $_.Status }
    foreach ($group in ($statusGroups | Sort-Object Name)) {
        Write-Log -Level Info -Message "  $($group.Name.PadRight(15))  $($group.Count.ToString().PadLeft(5))"
    }
}

function Write-ReportRemediationSteps {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IEnumerable]$Entries)

    $errorEntries = @($Entries | Where-Object { $_.Status -eq 'ERROR' })
    if ($errorEntries.Count -eq 0) {
        return
    }

    $steps = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in $errorEntries) {
        $message = [string]$entry.Message

        if ($message -match 'GITHUB_TOKEN is not set and \.env file is missing') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Create .env from .env.example and set GITHUB_TOKEN.'
            continue
        }

        if ($message -match 'GITHUB_TOKEN is defined in \.env but empty') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Set a non-empty GITHUB_TOKEN in .env or in user/machine environment variables.'
            continue
        }

        if ($message -match 'GITHUB_TOKEN is not set') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Set GITHUB_TOKEN in .env or in user/machine environment variables.'
            continue
        }

        if ($message -match 'GITHUB_TOKEN is invalid|expired|missing required scopes') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Replace GITHUB_TOKEN with a valid token that has required repository scopes, then retry.'
            continue
        }

        if ($message -match 'AZURE_DEVOPS_PAT is not set and \.env file is missing') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Create .env from .env.example and set AZURE_DEVOPS_PAT.'
            continue
        }

        if ($message -match 'AZURE_DEVOPS_PAT is defined in \.env but empty') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Set a non-empty AZURE_DEVOPS_PAT in .env or in user/machine environment variables.'
            continue
        }

        if ($message -match 'AZURE_DEVOPS_PAT is not set') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Set AZURE_DEVOPS_PAT in .env or in user/machine environment variables.'
            continue
        }

        if ($message -match 'No (Azure )?DevOps organization resolved|supports exactly one organization') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Set AZURE_DEVOPS_ORGS to a single organization name in .env or environment variables.'
            continue
        }

        if ($message -match 'git is not installed') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Install Git or run the prerequisite installer for your platform.'
            continue
        }

        if ($message -match 'Package manager not available') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Install a supported package manager (Windows: winget, Linux: apt/dnf/yum/zypper).'
            continue
        }

        if ($message -match 'Docker daemon is not available') {
            Add-RemediationStep -Steps $steps -Seen $seen -Step 'Start Docker Desktop/service and retry the ACR module.'
            continue
        }
    }

    if ($steps.Count -eq 0) {
        return
    }

    Write-Log -Level Warning -Message ''
    Write-Log -Level Warning -Message 'Recommended next steps:'
    $index = 1
    foreach ($step in $steps) {
        Write-Log -Level Warning -Message "  $index) $step"
        $index++
    }
}

function Add-RemediationStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Steps,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$Seen,
        [Parameter(Mandatory)][string]$Step
    )

    if ($Seen.Add($Step)) {
        $Steps.Add($Step)
    }
}

function Write-OrphanSummaryTables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IEnumerable]$Entries,
        [Parameter(Mandatory)][string[]]$ExecutedModules
    )

    $entryList = @($Entries)
    foreach ($moduleName in @('GitHub', 'DevOps')) {
        $moduleKey = $moduleName.ToLowerInvariant()
        if (-not ($ExecutedModules -contains $moduleKey)) {
            continue
        }

        $orphans = @($entryList | Where-Object {
                ([string]$_.Status).ToUpperInvariant() -eq 'ORPHAN' -and
                ([string]$_.Module).Equals($moduleName, [System.StringComparison]::OrdinalIgnoreCase)
            })

        Write-Log -Level Info -Message ''
        Write-Log -Level Info -Message "Orphan folders summary: $moduleName"
        Write-Log -Level Info -Message '  INDEX  FOLDER'
        Write-Log -Level Info -Message '  -----  ------------------------------------------------------------'

        if ($orphans.Count -eq 0) {
            Write-Log -Level Info -Message '      -  (none)'
            continue
        }

        $index = 1
        foreach ($entry in $orphans) {
            $indexText = $index.ToString().PadLeft(5)
            Write-Log -Level Info -Message "  $indexText  $($entry.Item)"
            $index++
        }
    }
}
