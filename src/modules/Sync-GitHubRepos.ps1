#Requires -Version 7.0
<#
.SYNOPSIS
    GitHub repository synchronization module.
.DESCRIPTION
    Downloads all repositories visible to the authenticated token by default.
        Optional include/exclude filters allow limiting users and organizations.

    Target path layout:
            <path>/<owner>/<repo>

    Example:
            path = D:\GitHub
      repo owner = octo-org
      repo name = app
      -> D:\GitHub\octo-org\app
#>

function Invoke-GitHubSync {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [switch]$Force
    )

    $moduleConfig = $Config.modules.github
    $results = [System.Collections.Generic.List[hashtable]]::new()

    $token = Get-SecureEnvVariable -Name 'GITHUB_TOKEN'
    if (-not $token) {
        $envFilePath = Join-Path $ProjectRoot '.env'
        $envTokenState = Get-EnvFileVariableState -Path $envFilePath -Name 'GITHUB_TOKEN'
        $message = switch ($envTokenState) {
            'MissingFile' { "GITHUB_TOKEN is not set and .env file is missing: $envFilePath" }
            'DefinedEmpty' { 'GITHUB_TOKEN is defined in .env but empty.' }
            'NotDefined' { 'GITHUB_TOKEN is not set in .env or environment variables.' }
            default { 'GITHUB_TOKEN is not set in process/user/machine environment.' }
        }

        $results.Add((New-ReportEntry -Module 'GitHub' -Item 'AUTH' -Status 'ERROR' -Message $message))
        return $results
    }

    if (-not (Test-CommandExists -CommandName 'git')) {
        $results.Add((New-ReportEntry -Module 'GitHub' -Item 'PREREQ' -Status 'ERROR' -Message 'git is not installed'))
        return $results
    }

    $targetRoot = Resolve-ConfiguredPath -Path $moduleConfig.path
    if (-not (Test-Path -LiteralPath $targetRoot)) {
        New-Item -Path $targetRoot -ItemType Directory -Force | Out-Null
    }

    Write-FilterAmbiguityWarnings -EntityLabel 'GitHub users' -IncludeTokens @($moduleConfig.usersInclude) -ExcludeTokens @($moduleConfig.usersExclude)
    Write-FilterAmbiguityWarnings -EntityLabel 'GitHub organizations' -IncludeTokens @($moduleConfig.organizationsInclude) -ExcludeTokens @($moduleConfig.organizationsExclude)

    $headers = @{
        Authorization = "Bearer $token"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    $tokenDiagnostics = Get-GitHubTokenDiagnostics -Token $token -ProjectRoot $ProjectRoot
    Write-Log -Level Info -Message "GitHub token diagnostics: source=$($tokenDiagnostics.Source); envFileState=$($tokenDiagnostics.EnvFileState); length=$($tokenDiagnostics.Length); preview=$($tokenDiagnostics.Preview); format=$($tokenDiagnostics.Format)"

    $authResult = Test-GitHubTokenAccess -Headers $headers
    if (-not $authResult.IsValid) {
        if (-not [string]::IsNullOrWhiteSpace([string]$authResult.Diagnostics)) {
            Write-Log -Level Warning -Message "GitHub auth diagnostics: $($authResult.Diagnostics)"
        }
        $results.Add((New-ReportEntry -Module 'GitHub' -Item 'AUTH' -Status 'ERROR' -Message $authResult.Message))
        return $results
    }

    $retryCount = if ($moduleConfig.retryCount) { [int]$moduleConfig.retryCount } else { 3 }
    $retryDelay = if ($moduleConfig.retryDelaySeconds) { [int]$moduleConfig.retryDelaySeconds } else { 5 }

    $repos = Get-AllVisibleGitHubRepos -Headers $headers -RetryCount $retryCount -RetryDelaySeconds $retryDelay
    if (@($repos).Count -eq 0) {
        Write-Log -Level Warning -Message 'No GitHub repositories returned by the token.'
        return $results
    }

    $expected = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($repo in $repos) {
        $owner = $repo.owner.login
        $repoName = $repo.name

        if (-not (Test-GitHubRepoIncluded -Repo $repo -Config $moduleConfig)) {
            $results.Add((New-ReportEntry -Module 'GitHub' -Item "$owner/$repoName" -Status 'SKIPPED' -Message 'Filtered by usersInclude/usersExclude or organizationsInclude/organizationsExclude'))
            continue
        }

        $repoTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $ownerPath = Join-Path $targetRoot $owner
        $repoPath = Join-Path $ownerPath $repoName
        $expected.Add("$owner/$repoName") | Out-Null

        if (-not (Test-Path -LiteralPath $ownerPath)) {
            New-Item -Path $ownerPath -ItemType Directory -Force | Out-Null
        }

        $cloneUrl = $repo.clone_url -replace '^https://', "https://x-access-token:$token@"

        try {
            $status = Invoke-GitCloneOrPull -CloneUrl $cloneUrl -DestinationPath $repoPath
            $repoTimer.Stop()
            $results.Add((New-ReportEntry -Module 'GitHub' -Item "$owner/$repoName" -Status $status -Duration $repoTimer.Elapsed))
        }
        catch {
            $repoTimer.Stop()
            $results.Add((New-ReportEntry -Module 'GitHub' -Item "$owner/$repoName" -Status 'ERROR' -Message "$_" -Duration $repoTimer.Elapsed))
        }
    }

    Add-GitHubOrphanEntries -TargetRoot $targetRoot -Expected $expected -Results $results

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

function Get-AllVisibleGitHubRepos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Headers,
        [int]$RetryCount = 3,
        [int]$RetryDelaySeconds = 5
    )

    $all = [System.Collections.Generic.List[object]]::new()
    $page = 1
    $perPage = 100

    while ($true) {
        $url = "https://api.github.com/user/repos?visibility=all&affiliation=owner,collaborator,organization_member&per_page=$perPage&page=$page&sort=full_name"
        Write-Log -Level Info -Message "GitHub API request: GET /user/repos page=$page per_page=$perPage"

        $items = Invoke-WithRetry -MaxRetries $RetryCount -BaseDelaySeconds $RetryDelaySeconds -OperationName "GitHub page $page" -ScriptBlock {
            Invoke-RestMethod -Uri $url -Headers $Headers -Method GET -ResponseHeadersVariable 'responseHeaders'
        }

        $requestId = Get-HttpHeaderValue -Headers $responseHeaders -Name 'X-GitHub-Request-Id'
        $itemsCount = @($items).Count
        Write-Log -Level Info -Message "GitHub API response: page=$page count=$itemsCount requestId='$requestId'"

        if ($null -eq $items -or @($items).Count -eq 0) {
            break
        }

        $all.AddRange(@($items))
        if (@($items).Count -lt $perPage) {
            break
        }

        $page++
    }

    return $all
}

function Test-GitHubRepoIncluded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Repo,
        [Parameter(Mandatory)][hashtable]$Config
    )

    $owner = [string]$Repo.owner.login

    if ([string]$Repo.owner.type -eq 'Organization') {
        return Test-IncludeExcludeMatch -Name $owner -IncludeTokens @($Config.organizationsInclude) -ExcludeTokens @($Config.organizationsExclude)
    }

    return Test-IncludeExcludeMatch -Name $owner -IncludeTokens @($Config.usersInclude) -ExcludeTokens @($Config.usersExclude)
}

function Test-IncludeExcludeMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [object[]]$IncludeTokens = @('*'),
        [object[]]$ExcludeTokens = @()
    )

    $include = @(Get-NormalizedFilterTokens -Tokens $IncludeTokens)
    $exclude = @(Get-NormalizedFilterTokens -Tokens $ExcludeTokens)

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

function Get-NormalizedFilterTokens {
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

function Write-FilterAmbiguityWarnings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntityLabel,
        [object[]]$IncludeTokens,
        [object[]]$ExcludeTokens
    )

    $include = @(Get-NormalizedFilterTokens -Tokens $IncludeTokens)
    $exclude = @(Get-NormalizedFilterTokens -Tokens $ExcludeTokens)

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

function Add-GitHubOrphanEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$Expected,
        [Parameter(Mandatory)][System.Collections.Generic.List[hashtable]]$Results
    )

    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        return
    }

    $ownerDirs = Get-ChildItem -LiteralPath $TargetRoot -Directory -ErrorAction SilentlyContinue
    foreach ($ownerDir in $ownerDirs) {
        $repoDirs = Get-ChildItem -LiteralPath $ownerDir.FullName -Directory -ErrorAction SilentlyContinue
        foreach ($repoDir in $repoDirs) {
            $relative = "$($ownerDir.Name)/$($repoDir.Name)"
            if (-not $Expected.Contains($relative)) {
                $Results.Add((New-ReportEntry -Module 'GitHub' -Item $relative -Status 'ORPHAN' -Message 'Local repository does not exist remotely for current scope'))
            }
        }
    }
}

function Test-GitHubTokenAccess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Headers)

    try {
        Write-Log -Level Info -Message 'GitHub API request: GET /user'
        $response = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $Headers -Method GET
        $me = $response.Content | ConvertFrom-Json
        if ($null -ne $me -and -not [string]::IsNullOrWhiteSpace([string]$me.login)) {
            $scopes = Get-HttpHeaderValue -Headers $response.Headers -Name 'X-OAuth-Scopes'
            $requestId = Get-HttpHeaderValue -Headers $response.Headers -Name 'X-GitHub-Request-Id'
            Write-Log -Level Info -Message "GitHub auth validated for user '$([string]$me.login)'. scopes='$scopes'; requestId='$requestId'"
            return @{ IsValid = $true; Message = 'OK'; Diagnostics = '' }
        }

        return @{ IsValid = $false; Message = 'GITHUB_TOKEN validation failed: GitHub did not return the authenticated user profile.'; Diagnostics = 'GitHub /user endpoint returned an empty profile payload.' }
    }
    catch {
        $statusCode = $null
        $scopes = ''
        $requestId = ''
        $responseBody = ''
        try {
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($_.Exception.Response -and $_.Exception.Response.Headers) {
                $scopes = Get-HttpHeaderValue -Headers $_.Exception.Response.Headers -Name 'X-OAuth-Scopes'
                $requestId = Get-HttpHeaderValue -Headers $_.Exception.Response.Headers -Name 'X-GitHub-Request-Id'
            }

            if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace([string]$_.ErrorDetails.Message)) {
                $responseBody = [string]$_.ErrorDetails.Message
            }
        }
        catch {}

        $diagnostics = "status=$statusCode; scopes='$scopes'; requestId='$requestId'"
        if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
            $diagnostics = "$diagnostics; body='$responseBody'"
        }

        if ($statusCode -in @(401, 403)) {
            return @{ IsValid = $false; Message = 'GITHUB_TOKEN is invalid, expired, or missing required scopes. Generate a valid token and retry.'; Diagnostics = $diagnostics }
        }

        return @{ IsValid = $false; Message = "Unable to validate GITHUB_TOKEN against GitHub API: $_"; Diagnostics = $diagnostics }
    }
}

function Get-GitHubTokenDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $processValue = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN', 'Process')
    $userValue = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN', 'User')
    $machineValue = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN', 'Machine')
    $source = if (-not [string]::IsNullOrWhiteSpace($processValue)) {
        'Process'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($userValue)) {
        'User'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($machineValue)) {
        'Machine'
    }
    else {
        'Unknown'
    }

    $envState = Get-EnvFileVariableState -Path (Join-Path $ProjectRoot '.env') -Name 'GITHUB_TOKEN'
    $firstLength = [Math]::Min(6, $Token.Length)
    $first = $Token.Substring(0, $firstLength)
    $lastLength = [Math]::Min(3, $Token.Length)
    $last = $Token.Substring($Token.Length - $lastLength, $lastLength)
    $preview = "$first...$last"
    $format = if ($Token.StartsWith('github_pat_')) {
        'FineGrainedPAT'
    }
    elseif ($Token.StartsWith('ghp_')) {
        'ClassicPAT'
    }
    elseif ($Token.StartsWith('gho_')) {
        'OAuthToken'
    }
    elseif ($Token.StartsWith('ghu_')) {
        'UserToServerToken'
    }
    elseif ($Token.StartsWith('ghs_')) {
        'ServerToServerToken'
    }
    else {
        'Unknown'
    }

    return @{
        Source = $source
        EnvFileState = $envState
        Length = $Token.Length
        Preview = $preview
        Format = $format
    }
}

function Get-HttpHeaderValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Headers,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        if ($null -eq $Headers) {
            return ''
        }

        $direct = $Headers[$Name]
        if ($null -ne $direct) {
            if ($direct -is [System.Collections.IEnumerable] -and -not ($direct -is [string])) {
                return (@($direct) -join ', ')
            }

            return [string]$direct
        }

        foreach ($key in @($Headers.Keys)) {
            if ([string]$key -ieq $Name) {
                $value = $Headers[$key]
                if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    return (@($value) -join ', ')
                }

                return [string]$value
            }
        }
    }
    catch {}

    return ''
}
