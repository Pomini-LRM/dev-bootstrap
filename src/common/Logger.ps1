#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Persistent logging for dev-bootstrap.
.DESCRIPTION
    Writes logs to file and console using Debug, Info, Warning, and Error levels.
    Automatically redacts secrets from log and console output.
    Log file format: YYYYMMDD_HHMMSS_log.log
#>

$script:_LogFilePath = $null
$script:_LogWriter = $null
$script:_LogLevel = 'Info'
$script:_LogSilent = $false
$script:_LogLevelMap = @{ 'Debug' = 0; 'Info' = 1; 'Warning' = 2; 'Error' = 3 }
$script:_StepTimers = @{}

function Initialize-Logger {
    <#
    .SYNOPSIS
        Initializes file and console logging for the current run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [switch]$Silent
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:_LogFilePath = Join-Path $LogDirectory "${timestamp}_log.log"
    $script:_LogLevel = $Level
    $script:_LogSilent = $Silent.IsPresent

    if ($script:_LogWriter) {
        $script:_LogWriter.Dispose()
        $script:_LogWriter = $null
    }

    $script:_LogWriter = [System.IO.StreamWriter]::new($script:_LogFilePath, $false, [System.Text.Encoding]::UTF8)
    $script:_LogWriter.AutoFlush = $true

    Write-Log -Level Info -Message '============================================='
    Write-Log -Level Info -Message 'dev-bootstrap - Logging initialized'
    Write-Log -Level Info -Message "Log file  : $($script:_LogFilePath)"
    Write-Log -Level Info -Message "Log level : $Level"
    Write-Log -Level Info -Message "OS        : $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)"
    Write-Log -Level Info -Message "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Log -Level Info -Message '============================================='

    return $script:_LogFilePath
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a sanitized log entry to console and log file.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ($script:_LogLevelMap[$Level] -lt $script:_LogLevelMap[$script:_LogLevel]) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $sanitized = ConvertTo-SanitizedString -Text $Message
    $entry = "[$timestamp] [$($Level.ToUpper().PadRight(7))] $sanitized"

    if (-not $script:_LogSilent) {
        switch ($Level) {
            'Debug' { Write-Host $entry -ForegroundColor DarkGray }
            'Info' { Write-Host $entry -ForegroundColor Cyan }
            'Warning' { Write-Host $entry -ForegroundColor Yellow }
            'Error' { Write-Host $entry -ForegroundColor Red }
        }
    }

    if ($script:_LogWriter) {
        $script:_LogWriter.WriteLine($entry)
    }
    elseif ($script:_LogFilePath) {
        $entry | Out-File -FilePath $script:_LogFilePath -Append -Encoding utf8
    }
}

function ConvertTo-SanitizedString {
    [CmdletBinding()]
    param([string]$Text)

    $result = $Text
    $result = $result -replace '(?i)(password|secret|token|pat|api_key|apikey|access_key|client_secret)["''\s]*[:=]["''\s]*\S+', '$1=***REDACTED***'
    $result = $result -replace 'ghp_[A-Za-z0-9_]{20,}', '***REDACTED_GH_TOKEN***'
    $result = $result -replace 'gho_[A-Za-z0-9_]{20,}', '***REDACTED_GH_TOKEN***'
    $result = $result -replace 'github_pat_[A-Za-z0-9_]{20,}', '***REDACTED_GH_TOKEN***'
    $result = $result -replace '(?i)Bearer\s+\S+', 'Bearer ***REDACTED***'
    $result = $result -replace '(?i)Basic\s+[A-Za-z0-9+/=]{20,}', 'Basic ***REDACTED***'
    $result = $result -replace 'https://[^\s:@/]+:[^\s@/]+@', 'https://***:***@'

    return $result
}

function Start-StepTimer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StepName)

    $script:_StepTimers[$StepName] = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Log -Level Info -Message ">> Starting step: $StepName"
}

function Stop-StepTimer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StepName)

    $elapsed = [TimeSpan]::Zero
    if ($script:_StepTimers.ContainsKey($StepName)) {
        $script:_StepTimers[$StepName].Stop()
        $elapsed = $script:_StepTimers[$StepName].Elapsed
        $script:_StepTimers.Remove($StepName)
    }

    Write-Log -Level Info -Message "<< Finished step: $StepName (duration: $($elapsed.ToString('hh\:mm\:ss\.fff')))"
    return $elapsed
}

function Get-LogFilePath {
    return $script:_LogFilePath
}
