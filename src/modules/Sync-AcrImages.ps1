#Requires -Version 7.0
<#
.SYNOPSIS
    Azure Container Registry image synchronization module.
#>

function Invoke-AcrSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$Force
    )

    $moduleConfig = $Config.modules.acr
    $results = [System.Collections.Generic.List[hashtable]]::new()
    $retryCount = if ($moduleConfig.retryCount) { [int]$moduleConfig.retryCount } else { 3 }
    $retryDelay = if ($moduleConfig.retryDelaySeconds) { [int]$moduleConfig.retryDelaySeconds } else { 10 }

    if (-not (Test-CommandExists -CommandName 'az')) {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'PREREQ' -Status 'ERROR' -Message 'Azure CLI (az) is not installed'))
    }

    if (-not (Test-CommandExists -CommandName 'docker')) {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'PREREQ' -Status 'ERROR' -Message 'Docker is not installed'))
    }

    if ($results.Count -gt 0) {
        return $results
    }

    $null = & docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'PREREQ' -Status 'ERROR' -Message 'Docker daemon is not available'))
        return $results
    }

    $tenantId = Get-SecureEnvVariable -Name 'AZURE_TENANT_ID'
    if (-not $tenantId) {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'AUTH' -Status 'ERROR' -Message 'AZURE_TENANT_ID is not configured'))
        return $results
    }

    try {
        $alreadyAuthenticated = $false
        $accountInfo = & az account show --only-show-errors --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$accountInfo)) {
            try {
                $account = $accountInfo | ConvertFrom-Json
                if ([string]$account.tenantId -eq [string]$tenantId) {
                    $alreadyAuthenticated = $true
                    Write-Log -Level Info -Message "Azure session already active for tenant '$tenantId'."
                }
            }
            catch {
                # Ignore parse issues and fall back to login flow.
            }
        }

        if (-not $alreadyAuthenticated) {
            Write-Log -Level Info -Message "Starting interactive Azure login for tenant '$tenantId'."
            $null = & az login --tenant $tenantId --allow-no-subscriptions --only-show-errors 2>&1

            if ($LASTEXITCODE -ne 0) {
                $results.Add((New-ReportEntry -Module 'ACR' -Item 'AUTH' -Status 'ERROR' -Message 'Azure login failed'))
                return $results
            }
        }
    }
    catch {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'AUTH' -Status 'ERROR' -Message "$_"))
        return $results
    }

    $registries = @($moduleConfig.registries)
    foreach ($registry in $registries) {
        try {
            Invoke-WithRetry -MaxRetries $retryCount -BaseDelaySeconds $retryDelay -OperationName "ACR login $registry" -ScriptBlock {
                $out = & az acr login --name $registry 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "az acr login failed for $registry"
                }
                return $out
            } | Out-Null
        }
        catch {
            $results.Add((New-ReportEntry -Module 'ACR' -Item "registry:$registry" -Status 'ERROR' -Message "$_"))
        }
    }

    $imagesInclude = @(Get-AcrNormalizedFilterTokens -Tokens @($moduleConfig.imagesInclude))
    $imagesExclude = @(Get-AcrNormalizedFilterTokens -Tokens @($moduleConfig.imagesExclude))

    Write-AcrFilterAmbiguityWarnings -EntityLabel 'ACR images' -IncludeTokens $imagesInclude -ExcludeTokens $imagesExclude

    if ($imagesInclude.Count -eq 0) {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'images' -Status 'SKIPPED' -Message 'No images configured in imagesInclude'))
        return $results
    }

    $workItems = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($imagesInclude -contains '*') {
        foreach ($registry in $registries) {
            $repoNames = @(Get-AcrRegistryRepositories -Registry $registry -RetryCount $retryCount -RetryDelaySeconds $retryDelay)
            foreach ($repoName in $repoNames) {
                $resolvedImage = "$registry.azurecr.io/$repoName"
                if ($seen.Add($resolvedImage)) {
                    $shouldSync = Test-AcrIncludeExcludeMatch -Name $repoName -IncludeTokens $imagesInclude -ExcludeTokens $imagesExclude
                    $workItems.Add([PSCustomObject]@{
                            Label = "$registry - $repoName"
                            Item = "$registry/$repoName"
                            ResolvedImage = $resolvedImage
                            ShouldSync = $shouldSync
                        })
                }
            }
        }
    }
    else {
        foreach ($includeImage in $imagesInclude) {
            if ($includeImage -match '\.azurecr\.io/') {
                if ($seen.Add($includeImage)) {
                    $nameForFilter = ($includeImage -replace '^.+?\.azurecr\.io/', '')
                    $shouldSync = Test-AcrIncludeExcludeMatch -Name $nameForFilter -IncludeTokens $imagesInclude -ExcludeTokens $imagesExclude
                    $workItems.Add([PSCustomObject]@{
                            Label = $includeImage
                            Item = $nameForFilter
                            ResolvedImage = $includeImage
                            ShouldSync = $shouldSync
                        })
                }
                continue
            }

            foreach ($registry in $registries) {
                $resolvedImage = "$registry.azurecr.io/$includeImage"
                if ($seen.Add($resolvedImage)) {
                    $shouldSync = Test-AcrIncludeExcludeMatch -Name $includeImage -IncludeTokens $imagesInclude -ExcludeTokens $imagesExclude
                    $workItems.Add([PSCustomObject]@{
                            Label = "$registry - $includeImage"
                            Item = "$registry/$includeImage"
                            ResolvedImage = $resolvedImage
                            ShouldSync = $shouldSync
                        })
                }
            }
        }
    }

    if ($workItems.Count -eq 0) {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'images' -Status 'SKIPPED' -Message 'No images resolved from include/exclude rules'))
        return $results
    }

    $totalItems = $workItems.Count
    $itemIndex = 0
    foreach ($item in $workItems) {
        $itemIndex++
        Write-Log -Level Info -Message "Image [$itemIndex/$totalItems]: $($item.Label)"

        if (-not $item.ShouldSync) {
            $entry = New-ReportEntry -Module 'ACR' -Item $item.Item -Status 'SKIPPED' -Message 'Filtered by image include/exclude rules.'
            $results.Add($entry)
            Write-AcrImageEntryLog -Entry $entry
            continue
        }

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $resolvedImage = [string]$item.ResolvedImage

        try {
            $pullResult = Invoke-WithRetry -MaxRetries $retryCount -BaseDelaySeconds $retryDelay -OperationName "docker pull $resolvedImage" -ScriptBlock {
                $pull = & docker pull $resolvedImage 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "docker pull failed"
                }
                return ($pull -join "`n")
            }

            $timer.Stop()
            $status = if ($pullResult -match 'up to date') { 'NONE' } elseif ($pullResult -match 'Downloaded newer image') { 'UPDATED' } else { 'ADDED' }
            $entry = New-ReportEntry -Module 'ACR' -Item $item.Item -Status $status -Duration $timer.Elapsed
            $results.Add($entry)
            Write-AcrImageEntryLog -Entry $entry
        }
        catch {
            $timer.Stop()
            $entry = New-ReportEntry -Module 'ACR' -Item $item.Item -Status 'ERROR' -Message "$_" -Duration $timer.Elapsed
            $results.Add($entry)
            Write-AcrImageEntryLog -Entry $entry
        }
    }

    return $results
}

function Get-AcrRegistryRepositories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Registry,
        [int]$RetryCount = 3,
        [int]$RetryDelaySeconds = 10
    )

    $raw = Invoke-WithRetry -MaxRetries $RetryCount -BaseDelaySeconds $RetryDelaySeconds -OperationName "ACR repository list $Registry" -ScriptBlock {
        $out = & az acr repository list --name $Registry --only-show-errors --output tsv 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to list repositories for $Registry"
        }

        return $out
    }

    return @(@($raw) | ForEach-Object { [string]$_ } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-AcrIncludeExcludeMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [object[]]$IncludeTokens = @('*'),
        [object[]]$ExcludeTokens = @()
    )

    $include = @(Get-AcrNormalizedFilterTokens -Tokens $IncludeTokens)
    $exclude = @(Get-AcrNormalizedFilterTokens -Tokens $ExcludeTokens)

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

function Get-AcrNormalizedFilterTokens {
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

function Write-AcrFilterAmbiguityWarnings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntityLabel,
        [object[]]$IncludeTokens,
        [object[]]$ExcludeTokens
    )

    $include = @(Get-AcrNormalizedFilterTokens -Tokens $IncludeTokens)
    $exclude = @(Get-AcrNormalizedFilterTokens -Tokens $ExcludeTokens)

    if ($include.Count -gt 1 -and $include -contains '*') {
        Write-Log -Level Warning -Message "$EntityLabel include list contains '*' and explicit names. Explicit names are redundant."
    }

    if ($exclude -contains '*') {
        Write-Log -Level Warning -Message "$EntityLabel exclude list contains '*'. All matching images will be excluded."
    }

    foreach ($token in $include) {
        if ($exclude -contains $token) {
            Write-Log -Level Warning -Message "$EntityLabel token '$token' is present in both include and exclude lists. Exclude wins."
        }
    }
}

function Write-AcrImageEntryLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Entry)

    $level = if ($Entry.Status -eq 'ERROR') { 'Error' } else { 'Info' }
    $durationText = if ($Entry.Duration -gt [TimeSpan]::Zero) { " ($($Entry.Duration.ToString('hh\:mm\:ss')))" } else { '' }
    $actionText = if ([string]::IsNullOrWhiteSpace([string]$Entry.Message)) { Get-AcrActionFromStatus -Status ([string]$Entry.Status) } else { [string]$Entry.Message }

    Write-Log -Level $level -Message "  Action: $actionText"
    Write-Log -Level $level -Message "  Status: $($Entry.Status)$durationText"
}

function Get-AcrActionFromStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Status)

    switch ($Status.ToUpperInvariant()) {
        'ADDED' { return 'Image pulled.' }
        'UPDATED' { return 'Image updated.' }
        'NONE' { return 'Image already up to date.' }
        'SKIPPED' { return 'Image skipped.' }
        'ERROR' { return 'Image sync failed.' }
        default { return 'Image sync completed.' }
    }
}
