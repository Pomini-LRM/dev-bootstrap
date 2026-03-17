#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Version helpers for dev-bootstrap.
#>

function Get-DevBootstrapVersion {
    <#
    .SYNOPSIS
        Returns current dev-bootstrap version string from version.json.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $versionFile = Join-Path $ProjectRoot 'config' 'version.json'
    if (-not (Test-Path -LiteralPath $versionFile)) {
        return '0.0.0-local'
    }

    try {
        $raw = Get-Content -LiteralPath $versionFile -Raw -Encoding utf8
        $data = $raw | ConvertFrom-Json -AsHashtable -Depth 5
        $version = if ($data.ContainsKey('version')) { [string]$data.version } else { '' }
        $date = if ($data.ContainsKey('date')) { [string]$data.date } else { '' }
        if ([string]::IsNullOrWhiteSpace($version)) {
            return '0.0.0-local'
        }
        if (-not [string]::IsNullOrWhiteSpace($date)) {
            return "$($version.Trim()) ($date)"
        }
        return $version.Trim()
    }
    catch {
        return '0.0.0-local'
    }
}
