#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        $env:TEMP = [System.IO.Path]::GetTempPath()
    }

    $script:projectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:projectRoot 'src' 'common' 'Logger.ps1')
    . (Join-Path $script:projectRoot 'src' 'common' 'Filters.ps1')
    . (Join-Path $script:projectRoot 'src' 'common' 'Platform.ps1')
    . (Join-Path $script:projectRoot 'src' 'common' 'Utilities.ps1')
    . (Join-Path $script:projectRoot 'src' 'common' 'Report.ps1')
    . (Join-Path $script:projectRoot 'src' 'modules' 'Sync-GitHubRepos.ps1')
    . (Join-Path $script:projectRoot 'src' 'modules' 'Sync-DevOpsRepos.ps1')
    . (Join-Path $script:projectRoot 'src' 'modules' 'Sync-AcrImages.ps1')

    $testLogDir = Join-Path $env:TEMP 'dev-bootstrap-tests-sync-modules' 'log'
    Initialize-Logger -LogDirectory $testLogDir -Level 'Error' -Silent | Out-Null

    $script:originalGitHubToken = [System.Environment]::GetEnvironmentVariable('GITHUB_TOKEN', 'Process')
    $script:originalDevOpsPat = [System.Environment]::GetEnvironmentVariable('AZURE_DEVOPS_PAT', 'Process')
    $script:originalTenantId = [System.Environment]::GetEnvironmentVariable('AZURE_TENANT_ID', 'Process')
}

Describe 'Module auth guards' {
    It 'returns AUTH error when GitHub token is missing' {
        [System.Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $null, 'Process')

        $config = @{ modules = @{ github = @{ path = 'D:\\GitHub'; usersInclude = @('*'); usersExclude = @(); organizationsInclude = @('*'); organizationsExclude = @(); setFolderIcon = $false; retryCount = 1; retryDelaySeconds = 0 } } }
        $results = Invoke-GitHubSync -Config $config -ProjectRoot $script:projectRoot

        $entries = @($results)
        $entries.Count | Should -Be 1
        $entries[0].Item | Should -Be 'AUTH'
        $entries[0].Status | Should -Be 'ERROR'
    }

    It 'returns AUTH error when DevOps PAT is missing' {
        [System.Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PAT', $null, 'Process')

        $config = @{ modules = @{ devops = @{ path = 'D:\\DevOps'; projectsInclude = @('*'); projectsExclude = @(); includeWikis = $false; setFolderIcon = $false; retryCount = 1; retryDelaySeconds = 0 } } }
        $results = Invoke-DevOpsSync -Config $config -ProjectRoot $script:projectRoot

        $entries = @($results)
        $entries.Count | Should -Be 1
        $entries[0].Item | Should -Be 'AUTH'
        $entries[0].Status | Should -Be 'ERROR'
    }

    It 'returns prereq errors when az and docker are unavailable' {
        Mock -CommandName Test-CommandExists -MockWith { return $false }

        $config = @{ modules = @{ acr = @{ registries = @('myregistry'); imagesInclude = @('*'); imagesExclude = @(); retryCount = 1; retryDelaySeconds = 0 } } }
        $results = Invoke-AcrSync -Config $config -ProjectRoot $script:projectRoot

        $statuses = @($results | ForEach-Object { $_.Status })
        $statuses | Should -Contain 'ERROR'
        @($results).Count | Should -Be 2
    }
}

Describe 'ACR diagnostics helpers' {
    It 'detects failure details in az output text' {
        (Test-AzOutputIndicatesFailure -Output @('ERROR: The resource was not found')) | Should -BeTrue
        (Test-AzOutputIndicatesFailure -Output @('Forbidden: access denied')) | Should -BeTrue
        (Test-AzOutputIndicatesFailure -Output @('Could not resolve host name')) | Should -BeTrue
    }

    It 'does not flag healthy az output' {
        (Test-AzOutputIndicatesFailure -Output @('plrm-vscode')) | Should -BeFalse
        (Test-AzOutputIndicatesFailure -Output @('')) | Should -BeFalse
    }
}

Describe 'ACR result coherence' {
    It 'reports one skipped entry per included image when registry is unreachable' {
        [System.Environment]::SetEnvironmentVariable('AZURE_TENANT_ID', '51835014-d218-4754-b420-16de4790eedf', 'Process')

        Mock -CommandName Test-CommandExists -MockWith { $true }
        Mock -CommandName docker -MockWith {
            $global:LASTEXITCODE = 0
            return 'Docker is running'
        }
        Mock -CommandName az -MockWith {
            $joined = ($args -join ' ').ToLowerInvariant()
            $global:LASTEXITCODE = 0

            if ($joined -match '^account show') {
                return '{"tenantId":"51835014-d218-4754-b420-16de4790eedf"}'
            }

            if ($joined -match '^acr check-health') {
                return 'ERROR: challenge endpoint failed'
            }

            if ($joined -match '^acr repository list') {
                return 'ERROR: registry not reachable'
            }

            return ''
        }

        $config = @{ modules = @{ acr = @{ registries = @('acrpominishareddev'); imagesInclude = @('img-a', 'img-b', 'img-c'); imagesExclude = @(); retryCount = 1; retryDelaySeconds = 0 } } }
        $results = @(Invoke-AcrSync -Config $config -ProjectRoot $script:projectRoot)

        $results.Count | Should -Be 3
        (@($results | Where-Object { $_.Status -eq 'SKIPPED' })).Count | Should -Be 3
        (@($results | Where-Object { $_.Status -eq 'ERROR' })).Count | Should -Be 0
    }
}

AfterAll {
    [System.Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $script:originalGitHubToken, 'Process')
    [System.Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PAT', $script:originalDevOpsPat, 'Process')
    [System.Environment]::SetEnvironmentVariable('AZURE_TENANT_ID', $script:originalTenantId, 'Process')

    $testRoot = Join-Path $env:TEMP 'dev-bootstrap-tests-sync-modules'
    if (Test-Path $testRoot) {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
