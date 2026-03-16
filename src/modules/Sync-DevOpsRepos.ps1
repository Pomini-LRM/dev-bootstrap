#Requires -Version 7.0
<#
.SYNOPSIS
    Azure DevOps repository synchronization module.
.DESCRIPTION
        Syncs repositories for organizations configured in AZURE_DEVOPS_ORGS.
        Optional include/exclude project filters limit project scope.
        Optional includeWikis setting controls code wiki download.

    Target path layout:
            <path>/<organization>/<project>/<repo>
#>

function Invoke-DevOpsSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$Force
    )

    $moduleConfig = $Config.modules.devops
    $results = [System.Collections.Generic.List[hashtable]]::new()

    $pat = Get-SecureEnvVariable -Name 'AZURE_DEVOPS_PAT'
    if (-not $pat) {
        $envFilePath = Join-Path $ProjectRoot '.env'
        $envPatState = Get-EnvFileVariableState -Path $envFilePath -Name 'AZURE_DEVOPS_PAT'
        $message = switch ($envPatState) {
            'MissingFile' { "AZURE_DEVOPS_PAT is not set and .env file is missing: $envFilePath" }
            'DefinedEmpty' { 'AZURE_DEVOPS_PAT is defined in .env but empty.' }
            'NotDefined' { 'AZURE_DEVOPS_PAT is not set in .env or environment variables.' }
            default { 'AZURE_DEVOPS_PAT is not set in process/user/machine environment.' }
        }

        $results.Add((New-ReportEntry -Module 'DevOps' -Item 'AUTH' -Status 'ERROR' -Message $message))
        return $results
    }

    if (-not (Test-CommandExists -CommandName 'git')) {
        $results.Add((New-ReportEntry -Module 'DevOps' -Item 'PREREQ' -Status 'ERROR' -Message 'git is not installed'))
        return $results
    }

    $organizations = Resolve-DevOpsOrganizations -ModuleConfig $moduleConfig
    if ($organizations.Count -eq 0) {
        $results.Add((New-ReportEntry -Module 'DevOps' -Item 'CONFIG' -Status 'ERROR' -Message 'No DevOps organization resolved. Configure AZURE_DEVOPS_ORGS.'))
        return $results
    }

    $targetRoot = Resolve-ConfiguredPath -Path $moduleConfig.path
    if (-not (Test-Path -LiteralPath $targetRoot)) {
        New-Item -Path $targetRoot -ItemType Directory -Force | Out-Null
    }

    Write-DevOpsFilterAmbiguityWarnings -EntityLabel 'DevOps projects' -IncludeTokens @($moduleConfig.projectsInclude) -ExcludeTokens @($moduleConfig.projectsExclude)

    $authHeader = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
    $headers = @{ Authorization = "Basic $authHeader"; 'Content-Type' = 'application/json' }

    $retryCount = if ($moduleConfig.retryCount) { [int]$moduleConfig.retryCount } else { 3 }
    $retryDelay = if ($moduleConfig.retryDelaySeconds) { [int]$moduleConfig.retryDelaySeconds } else { 5 }

    $expected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($organization in $organizations) {
        $projects = Get-DevOpsProjects -Organization $organization -Headers $headers -RetryCount $retryCount -RetryDelaySeconds $retryDelay
        $projects = @($projects | Where-Object {
                Test-DevOpsIncludeExcludeMatch -Name $_.name -IncludeTokens @($moduleConfig.projectsInclude) -ExcludeTokens @($moduleConfig.projectsExclude)
            })

        foreach ($project in $projects) {
            $repos = Get-DevOpsRepos -Organization $organization -Project $project.name -Headers $headers -RetryCount $retryCount -RetryDelaySeconds $retryDelay
            foreach ($repo in $repos) {
                $repoTimer = [System.Diagnostics.Stopwatch]::StartNew()
                $relative = "$organization/$($project.name)/$($repo.name)"
                $repoPath = Join-Path (Join-Path (Join-Path $targetRoot $organization) $project.name) $repo.name
                $expected.Add($relative) | Out-Null

                $cloneUrl = $repo.remoteUrl -replace '^https://', "https://pat:$pat@"

                try {
                    $status = Invoke-GitCloneOrPull -CloneUrl $cloneUrl -DestinationPath $repoPath
                    $repoTimer.Stop()
                    $results.Add((New-ReportEntry -Module 'DevOps' -Item $relative -Status $status -Duration $repoTimer.Elapsed))
                }
                catch {
                    $repoTimer.Stop()
                    $results.Add((New-ReportEntry -Module 'DevOps' -Item $relative -Status 'ERROR' -Message "$_" -Duration $repoTimer.Elapsed))
                }
            }

            if ($moduleConfig.includeWikis) {
                $wikis = Get-DevOpsWikis -Organization $organization -Project $project.name -Headers $headers -RetryCount $retryCount -RetryDelaySeconds $retryDelay
                foreach ($wiki in $wikis) {
                    $wikiTimer = [System.Diagnostics.Stopwatch]::StartNew()
                    $wikiName = "$($wiki.name).wiki"
                    $relative = "$organization/$($project.name)/$wikiName"
                    $wikiPath = Join-Path (Join-Path (Join-Path $targetRoot $organization) $project.name) $wikiName
                    $expected.Add($relative) | Out-Null

                    $cloneUrl = $wiki.remoteUrl -replace '^https://', "https://pat:$pat@"

                    try {
                        $status = Invoke-GitCloneOrPull -CloneUrl $cloneUrl -DestinationPath $wikiPath
                        $wikiTimer.Stop()
                        $results.Add((New-ReportEntry -Module 'DevOps' -Item $relative -Status $status -Duration $wikiTimer.Elapsed))
                    }
                    catch {
                        $wikiTimer.Stop()
                        $results.Add((New-ReportEntry -Module 'DevOps' -Item $relative -Status 'ERROR' -Message "$_" -Duration $wikiTimer.Elapsed))
                    }
                }
            }
        }
    }

    Add-DevOpsOrphanEntries -TargetRoot $targetRoot -Expected $expected -Results $results

    if ($moduleConfig.setFolderIcon) {
        if (Test-IsWindows) {
            Set-WindowsFolderIcon -FolderPath $targetRoot
        }
        else {
            Write-Log -Level Warning -Message 'Folder icon option is Windows-only. Ignoring on this platform.'
        }
    }

    return $results
}

function Resolve-DevOpsOrganizations {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$ModuleConfig)

    $fromPlural = Get-SecureEnvVariable -Name 'AZURE_DEVOPS_ORGS'
    if ($fromPlural) {
        return @($fromPlural.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    return @()
}

function Test-DevOpsIncludeExcludeMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [object[]]$IncludeTokens = @('*'),
        [object[]]$ExcludeTokens = @()
    )

    $include = Get-DevOpsNormalizedFilterTokens -Tokens $IncludeTokens
    $exclude = Get-DevOpsNormalizedFilterTokens -Tokens $ExcludeTokens

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

function Get-DevOpsNormalizedFilterTokens {
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

function Write-DevOpsFilterAmbiguityWarnings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntityLabel,
        [object[]]$IncludeTokens,
        [object[]]$ExcludeTokens
    )

    $include = Get-DevOpsNormalizedFilterTokens -Tokens $IncludeTokens
    $exclude = Get-DevOpsNormalizedFilterTokens -Tokens $ExcludeTokens

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

function Get-DevOpsProjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][hashtable]$Headers,
        [int]$RetryCount,
        [int]$RetryDelaySeconds
    )

    $url = "https://dev.azure.com/$Organization/_apis/projects?api-version=7.0&`$top=1000"
    $response = Invoke-WithRetry -MaxRetries $RetryCount -BaseDelaySeconds $RetryDelaySeconds -OperationName "DevOps projects ($Organization)" -ScriptBlock {
        Invoke-RestMethod -Uri $url -Headers $Headers -Method GET
    }

    return @($response.value)
}

function Get-DevOpsRepos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][hashtable]$Headers,
        [int]$RetryCount,
        [int]$RetryDelaySeconds
    )

    $url = "https://dev.azure.com/$Organization/$Project/_apis/git/repositories?api-version=7.0"
    $response = Invoke-WithRetry -MaxRetries $RetryCount -BaseDelaySeconds $RetryDelaySeconds -OperationName "DevOps repos ($Organization/$Project)" -ScriptBlock {
        Invoke-RestMethod -Uri $url -Headers $Headers -Method GET
    }

    return @($response.value | Where-Object { -not $_.isDisabled })
}

function Get-DevOpsWikis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][hashtable]$Headers,
        [int]$RetryCount,
        [int]$RetryDelaySeconds
    )

    $url = "https://dev.azure.com/$Organization/$Project/_apis/wiki/wikis?api-version=7.0"
    $response = Invoke-WithRetry -MaxRetries $RetryCount -BaseDelaySeconds $RetryDelaySeconds -OperationName "DevOps wikis ($Organization/$Project)" -ScriptBlock {
        Invoke-RestMethod -Uri $url -Headers $Headers -Method GET
    }

    return @($response.value | Where-Object { $_.type -eq 'codeWiki' -and $_.remoteUrl })
}

function Add-DevOpsOrphanEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$Expected,
        [Parameter(Mandatory)][System.Collections.Generic.List[hashtable]]$Results
    )

    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        return
    }

    $orgDirs = Get-ChildItem -LiteralPath $TargetRoot -Directory -ErrorAction SilentlyContinue
    foreach ($orgDir in $orgDirs) {
        $projectDirs = Get-ChildItem -LiteralPath $orgDir.FullName -Directory -ErrorAction SilentlyContinue
        foreach ($projectDir in $projectDirs) {
            $repoDirs = Get-ChildItem -LiteralPath $projectDir.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($repoDir in $repoDirs) {
                $relative = "$($orgDir.Name)/$($projectDir.Name)/$($repoDir.Name)"
                if (-not $Expected.Contains($relative)) {
                    $Results.Add((New-ReportEntry -Module 'DevOps' -Item $relative -Status 'ORPHAN' -Message 'Local repository does not exist remotely for current scope'))
                }
            }
        }
    }
}
