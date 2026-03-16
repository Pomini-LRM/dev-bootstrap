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

    $dockerInfo = & docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'PREREQ' -Status 'ERROR' -Message 'Docker daemon is not available'))
        return $results
    }

    $tenantId = if ($moduleConfig.tenantId) { $moduleConfig.tenantId } else { Get-SecureEnvVariable -Name 'AZURE_TENANT_ID' }
    if (-not $tenantId) {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'AUTH' -Status 'ERROR' -Message 'tenantId is not configured (config or AZURE_TENANT_ID)'))
        return $results
    }

    $clientId = Get-SecureEnvVariable -Name 'AZURE_CLIENT_ID'
    $clientSecret = Get-SecureEnvVariable -Name 'AZURE_CLIENT_SECRET'

    try {
        if ($clientId -and $clientSecret) {
            $login = & az login --service-principal -u $clientId -p $clientSecret --tenant $tenantId 2>&1
        }
        else {
            $login = & az login --tenant $tenantId 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            $results.Add((New-ReportEntry -Module 'ACR' -Item 'AUTH' -Status 'ERROR' -Message 'Azure login failed'))
            return $results
        }
    }
    catch {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'AUTH' -Status 'ERROR' -Message "$_"))
        return $results
    }

    foreach ($registry in @($moduleConfig.registries)) {
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

    if ($moduleConfig.images.Count -eq 0) {
        $results.Add((New-ReportEntry -Module 'ACR' -Item 'images' -Status 'SKIPPED' -Message 'No images configured'))
        return $results
    }

    foreach ($image in @($moduleConfig.images)) {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $resolvedImage = $image
        if ($resolvedImage -notmatch '\.azurecr\.io/') {
            $resolvedImage = "$($moduleConfig.registries[0]).azurecr.io/$resolvedImage"
        }

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
            $results.Add((New-ReportEntry -Module 'ACR' -Item $image -Status $status -Duration $timer.Elapsed))
        }
        catch {
            $timer.Stop()
            $results.Add((New-ReportEntry -Module 'ACR' -Item $image -Status 'ERROR' -Message "$_" -Duration $timer.Elapsed))
        }
    }

    return $results
}
