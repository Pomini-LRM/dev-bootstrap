#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Shared include/exclude filtering helpers.
#>

function Test-IncludeExcludeMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [object[]]$IncludeTokens = @('*'),
        [object[]]$ExcludeTokens = @()
    )

    $include = @(Get-NormalizedFilterTokenSet -Tokens $IncludeTokens)
    $exclude = @(Get-NormalizedFilterTokenSet -Tokens $ExcludeTokens)

    if ($exclude -contains '*' -or $exclude -contains $Name) {
        return $false
    }

    if ($include -contains '*') {
        return $true
    }

    if ($include.Count -eq 0) {
        return $false
    }

    return $include -contains $Name
}

function Get-NormalizedFilterTokenSet {
    [CmdletBinding()]
    param([object[]]$Tokens)

    if ($null -eq $Tokens) {
        return @()
    }

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($token in @($Tokens)) {
        $normalized = [string]$token
        $normalized = $normalized.Trim()
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            $result.Add($normalized)
        }
    }

    return $result.ToArray()
}

function Write-FilterAmbiguityWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntityLabel,
        [object[]]$IncludeTokens,
        [object[]]$ExcludeTokens
    )

    $include = @(Get-NormalizedFilterTokenSet -Tokens $IncludeTokens)
    $exclude = @(Get-NormalizedFilterTokenSet -Tokens $ExcludeTokens)

    if ($include.Count -gt 1 -and $include -contains '*') {
        Write-Log -Level Warning -Message "$EntityLabel include list contains '*' and explicit names. Explicit names are redundant."
    }

    if ($exclude -contains '*') {
        Write-Log -Level Warning -Message "$EntityLabel exclude list contains '*'. All matching entities will be excluded."
    }

    foreach ($token in $include) {
        if ($exclude -contains $token) {
            Write-Log -Level Warning -Message "$EntityLabel token '$token' is present in both include and exclude lists. Exclude wins."
        }
    }
}
