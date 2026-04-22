#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Azure Container Registry image synchronization module.
#>

function Invoke-AcrSync {
    <#
    .SYNOPSIS
        Authenticates to Azure/ACR and pulls matching images.
    #>
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
                Write-Log -Level Debug -Message "Unable to parse 'az account show' output. Falling back to login flow."
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
    $reachableRegistries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($registry in $registries) {
        if (Test-AcrRegistryReachable -Registry $registry -RetryCount $retryCount -RetryDelaySeconds $retryDelay) {
            $null = $reachableRegistries.Add($registry)
        }
        else {
            Write-Log -Level Warning -Message "Registry '$registry' not reachable. Image freshness checks will be skipped for this registry."
        }
    }

    foreach ($registry in $registries) {
        if (-not $reachableRegistries.Contains($registry)) {
            continue
        }

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
            if (-not $reachableRegistries.Contains($registry)) {
                continue
            }

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

        $registryName = [string]$item.ResolvedImage
        if ($registryName -match '^([^\.]+)\.azurecr\.io/') {
            $registryName = [string]$Matches[1]
        }

        if (-not $reachableRegistries.Contains($registryName)) {
            $entry = New-ReportEntry -Module 'ACR' -Item $item.Item -Status 'SKIPPED' -Message 'Registry not reachable: freshness cannot be verified.'
            $results.Add($entry)
            Write-AcrImageEntryLog -Entry $entry
            continue
        }

        $freshnessProbe = Test-AcrImageFreshnessProbe -ResolvedImage ([string]$item.ResolvedImage) -RetryCount $retryCount -RetryDelaySeconds $retryDelay
        if (-not $freshnessProbe.IsReachable) {
            $entry = New-ReportEntry -Module 'ACR' -Item $item.Item -Status 'SKIPPED' -Message $freshnessProbe.Message
            $results.Add($entry)
            Write-AcrImageEntryLog -Entry $entry
            continue
        }

        Write-Log -Level Info -Message '  Freshness check: verified from ACR metadata.'

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $resolvedImage = [string]$item.ResolvedImage

        try {
            Write-ConsoleStatus -Message "  Pulling image '$resolvedImage' (download in progress, this may take several minutes)..."

            $pullResult = Invoke-WithRetry -MaxRetries $retryCount -BaseDelaySeconds $retryDelay -OperationName "docker pull $resolvedImage" -ScriptBlock {
                $captured = [System.Collections.Generic.List[string]]::new()
                & docker pull $resolvedImage 2>&1 | ForEach-Object {
                    $line = [string]$_
                    $captured.Add($line)
                    Write-ConsoleStatus -Message "    $line"
                }
                if ($LASTEXITCODE -ne 0) {
                    throw "docker pull failed"
                }
                return ($captured -join "`n")
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

function Test-AcrRegistryReachable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Registry,
        [int]$RetryCount = 3,
        [int]$RetryDelaySeconds = 10
    )

    try {
        try {
            $health = & az acr check-health --name $Registry --yes --ignore-errors --output json 2>&1
            $healthText = (@($health) -join "`n")
            $healthExit = $LASTEXITCODE

            $challengeOk = $healthText -match 'Challenge endpoint .* : OK'
            $tokenOk = $healthText -match 'Fetch access token .* : OK'

            if ($challengeOk -and $tokenOk) {
                if ($healthExit -ne 0) {
                    Write-Log -Level Debug -Message "ACR check-health for '$Registry' returned exit $healthExit but core endpoints are OK; treating as healthy."
                }
            }
            else {
                $hasHardHealthError = $false
                foreach ($line in @($health)) {
                    $lineText = [string]$line
                    if ($lineText -match 'An error occurred:\s+(\S+)') {
                        $code = [string]$Matches[1]
                        if ($code -notin @('HELM_COMMAND_ERROR', 'NOTARY_COMMAND_ERROR')) {
                            $hasHardHealthError = $true
                            break
                        }
                    }
                }

                if ($hasHardHealthError) {
                    Write-Log -Level Warning -Message "ACR check-health for '$Registry' reported a hard error; falling back to repository probe."
                }
                else {
                    Write-Log -Level Debug -Message "ACR check-health for '$Registry' did not report core endpoints OK; falling back to repository probe."
                }
            }
        }
        catch {
            Write-Log -Level Warning -Message "ACR check-health for '$Registry' threw an exception; falling back to repository probe: $_"
        }

        Invoke-WithRetry -MaxRetries $RetryCount -BaseDelaySeconds $RetryDelaySeconds -OperationName "ACR reachability $Registry" -ScriptBlock {
            $probe = & az acr repository list --name $Registry --top 1 --only-show-errors --output tsv 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Registry '$Registry' not reachable"
            }

            if (Test-AzOutputIndicatesFailure -Output @($probe)) {
                throw "Registry '$Registry' not reachable"
            }
        } | Out-Null

        return $true
    }
    catch {
        Write-Log -Level Warning -Message "ACR reachability check failed for '$Registry': $_"
        return $false
    }
}

function Test-AcrImageFreshnessProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResolvedImage,
        [int]$RetryCount = 3,
        [int]$RetryDelaySeconds = 10
    )

    if ($ResolvedImage -notmatch '^(?<registry>[^\.]+)\.azurecr\.io/(?<path>.+)$') {
        return @{
            IsReachable = $false
            Message = "Invalid ACR image format: $ResolvedImage"
        }
    }

    $registry = [string]$Matches['registry']
    $repositoryPath = [string]$Matches['path']

    # Remove digest and/or tag to query repository metadata.
    if ($repositoryPath -match '^(?<repo>.+)@sha256:[0-9a-fA-F]{64}$') {
        $repositoryPath = [string]$Matches['repo']
    }
    if ($repositoryPath -match '^(?<repo>.+):[^/]+$') {
        $repositoryPath = [string]$Matches['repo']
    }

    try {
        Invoke-WithRetry -MaxRetries $RetryCount -BaseDelaySeconds $RetryDelaySeconds -OperationName "ACR freshness probe $ResolvedImage" -ScriptBlock {
            $probe = & az acr repository show-tags --name $registry --repository $repositoryPath --top 1 --orderby time_desc --only-show-errors --output tsv 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to verify image freshness for $ResolvedImage"
            }

            if (Test-AzOutputIndicatesFailure -Output @($probe)) {
                throw "Unable to verify image freshness for $ResolvedImage"
            }
        } | Out-Null

        return @{
            IsReachable = $true
            Message = 'Image freshness probe succeeded.'
        }
    }
    catch {
        return @{
            IsReachable = $false
            Message = "Registry appears closed or unreachable: freshness cannot be verified for $ResolvedImage."
        }
    }
}

function Test-AzOutputIndicatesFailure {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Output)

    $text = (@($Output) -join "`n").ToLowerInvariant().Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }

    return (
        $text -match '(^|\s)error\s*:' -or
        $text -match '\bforbidden\b' -or
        $text -match '\bunauthorized\b' -or
        $text -match '\bdenied\b' -or
        $text -match '\bnot found\b' -or
        $text -match 'resource\s+not\s+found' -or
        $text -match 'authentication\s+failed' -or
        $text -match 'authorization\s+failed' -or
        $text -match 'failed to establish a new connection' -or
        $text -match 'name or service not known' -or
        $text -match 'could not resolve' -or
        $text -match 'connection refused' -or
        $text -match 'timed out'
    )
}

function Test-AcrIncludeExcludeMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [object[]]$IncludeTokens = @('*'),
        [object[]]$ExcludeTokens = @()
    )

    return (Test-IncludeExcludeMatch -Name $Name -IncludeTokens $IncludeTokens -ExcludeTokens $ExcludeTokens)
}

function Get-AcrNormalizedFilterTokens {
    [CmdletBinding()]
    param([object[]]$Tokens)

    return @(Get-NormalizedFilterTokenSet -Tokens $Tokens)
}

function Write-AcrFilterAmbiguityWarnings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntityLabel,
        [object[]]$IncludeTokens,
        [object[]]$ExcludeTokens
    )

    Write-FilterAmbiguityWarning -EntityLabel $EntityLabel -IncludeTokens $IncludeTokens -ExcludeTokens $ExcludeTokens
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


