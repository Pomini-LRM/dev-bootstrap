#Requires -Version 7.0
<#
.SYNOPSIS
    Version helpers for dev-bootstrap.
#>

function Get-DevBootstrapVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $versionFile = Join-Path $ProjectRoot 'config' 'version.json'
    if (-not (Test-Path -LiteralPath $versionFile)) {
        return '0.0.0-local'
    }

    try {
        $raw = Get-Content -LiteralPath $versionFile -Raw -Encoding utf8
        $data = $raw | ConvertFrom-Json -AsHashtable -Depth 5
        $version = [string]$data.version
        if ([string]::IsNullOrWhiteSpace($version)) {
            return '0.0.0-local'
        }
        return $version.Trim()
    }
    catch {
        return '0.0.0-local'
    }
}
