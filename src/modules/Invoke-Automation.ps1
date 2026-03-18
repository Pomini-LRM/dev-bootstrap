#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Generic automation script runner module.
.DESCRIPTION
    Reads the automation catalog, resolves and validates scriptFile entries,
    and executes enabled automation scripts with standardized parameters.
#>

function Invoke-Automation {
    <#
    .SYNOPSIS
        Executes enabled automation scripts from the catalog.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$Force
    )

    $moduleConfig = $Config.modules.automation
    $results = [System.Collections.Generic.List[hashtable]]::new()

    $catalog = Read-AutomationCatalog -ProjectRoot $ProjectRoot
    $catalogByKey = @{}
    foreach ($item in @($catalog.automations)) {
        $catalogByKey[[string]$item.key] = $item
    }

    $enabledFlags = @($moduleConfig.catalog.Keys | Where-Object { [bool]$moduleConfig.catalog[$_] })
    if ($enabledFlags.Count -eq 0) {
        $results.Add((New-ReportEntry -Module 'Automation' -Item 'catalog' -Status 'SKIPPED' -Message 'No automation item enabled.'))
        return $results
    }

    Write-Log -Level Info -Message "Automation items enabled: $($enabledFlags.Count)"
    if ($Force.IsPresent) {
        Write-Log -Level Info -Message 'Automation runner force mode is enabled.'
    }

    $automationRoot = Join-Path $ProjectRoot 'src' 'automation'

    $itemIndex = 0
    foreach ($key in $enabledFlags) {
        $itemIndex++
        $catalogEntry = if ($catalogByKey.ContainsKey($key)) { $catalogByKey[$key] } else { $null }
        $name = if ($catalogEntry) { [string]$catalogEntry.name } else { [string]$key }
        Write-Log -Level Info -Message "Automation [$itemIndex/$($enabledFlags.Count)]: $name"
        $timer = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            if (-not $catalogEntry) {
                $result = @{ Status = 'SKIPPED'; Message = "Key '$key' not found in automation catalog." }
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$catalogEntry.scriptFile)) {
                $result = @{ Status = 'ERROR'; Message = "Catalog entry '$key' is missing required 'scriptFile' field." }
            }
            else {
                $scriptFile = [string]$catalogEntry.scriptFile

                if (-not $scriptFile.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $result = @{ Status = 'ERROR'; Message = "Script file '$scriptFile' must have a .ps1 extension." }
                }
                else {
                    $scriptPath = Join-Path $automationRoot $scriptFile

                    if (-not (Test-Path -LiteralPath $scriptPath)) {
                        $result = @{ Status = 'ERROR'; Message = "Script file not found: $scriptPath" }
                    }
                    else {
                        $previousExitCode = $global:LASTEXITCODE
                        $global:LASTEXITCODE = 0
                        $result = & $scriptPath -ModuleConfig $moduleConfig -ProjectRoot $ProjectRoot
                        $scriptExitCode = $global:LASTEXITCODE
                        $global:LASTEXITCODE = $previousExitCode

                        if ($scriptExitCode -ne 0) {
                            $result = @{ Status = 'ERROR'; Message = "Script '$scriptFile' failed with exit code $scriptExitCode." }
                        }

                        if ($null -eq $result -or -not ($result -is [hashtable])) {
                            $result = @{ Status = 'ERROR'; Message = "Script '$scriptFile' returned invalid output. Expected hashtable with Status and Message." }
                        }
                    }
                }
            }

            $timer.Stop()
            $entry = New-ReportEntry -Module 'Automation' -Item $name -Status $result.Status -Message $result.Message -Duration $timer.Elapsed
            $results.Add($entry)
            Write-AutomationEntryLog -Entry $entry
        }
        catch {
            $timer.Stop()
            $entry = New-ReportEntry -Module 'Automation' -Item $name -Status 'ERROR' -Message "$_" -Duration $timer.Elapsed
            $results.Add($entry)
            Write-AutomationEntryLog -Entry $entry
        }
    }

    return $results
}

function Read-AutomationCatalog {
    <#
    .SYNOPSIS
        Loads and validates the automation catalog.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $catalogPath = Join-Path $ProjectRoot 'config' 'automation.catalog.json'
    if (-not (Test-Path -LiteralPath $catalogPath)) {
        throw "Automation catalog not found: $catalogPath"
    }

    $raw = Get-Content -LiteralPath $catalogPath -Raw -Encoding utf8
    $catalog = $raw | ConvertFrom-Json -AsHashtable -Depth 20

    if (-not $catalog.ContainsKey('automations') -or @($catalog.automations).Count -eq 0) {
        throw "Automation catalog '$catalogPath' must define a non-empty 'automations' array."
    }

    foreach ($entry in @($catalog.automations)) {
        if (-not $entry.ContainsKey('key') -or [string]::IsNullOrWhiteSpace([string]$entry.key)) {
            throw "Automation catalog entry is missing required 'key' field."
        }

        if (-not $entry.ContainsKey('scriptFile') -or [string]::IsNullOrWhiteSpace([string]$entry.scriptFile)) {
            throw "Automation catalog entry '$($entry.key)' is missing required 'scriptFile' field."
        }

        $sf = [string]$entry.scriptFile
        if (-not $sf.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Automation catalog entry '$($entry.key)': scriptFile '$sf' must have a .ps1 extension."
        }
    }

    return $catalog
}

function Write-AutomationEntryLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Entry)

    $level = if ($Entry.Status -eq 'ERROR') { 'Error' } else { 'Info' }
    $durationText = if ($Entry.Duration -gt [TimeSpan]::Zero) { " ($($Entry.Duration.ToString('hh\:mm\:ss')))" } else { '' }
    $actionText = if ([string]::IsNullOrWhiteSpace([string]$Entry.Message)) { 'Automation processed.' } else { [string]$Entry.Message }

    Write-Log -Level $level -Message "  Action: $actionText"
    Write-Log -Level $level -Message "  Status: $($Entry.Status)$durationText"
}
