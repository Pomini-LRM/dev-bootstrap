#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $projectRoot 'src' 'common' 'Logger.ps1')
    . (Join-Path $projectRoot 'src' 'common' 'Platform.ps1')
    . (Join-Path $projectRoot 'src' 'common' 'Utilities.ps1')
    . (Join-Path $projectRoot 'src' 'common' 'Config.ps1')
    . (Join-Path $projectRoot 'src' 'common' 'Report.ps1')
    . (Join-Path $projectRoot 'src' 'modules' 'Apply-Configurations.ps1')

    $testLogDir = Join-Path $env:TEMP 'dev-bootstrap-tests-configurations' 'log'
    Initialize-Logger -LogDirectory $testLogDir -Level 'Error' -Silent | Out-Null
}

Describe 'Configurations catalog' {
    It 'loads configuration catalog entries' {
        $catalog = Read-ConfigurationsCatalog -ProjectRoot $projectRoot
        @($catalog.configurations).Count | Should -Be 4
        @($catalog.configurations | ForEach-Object { $_.key }) | Should -Contain 'addMakePath'
        @($catalog.configurations | ForEach-Object { $_.key }) | Should -Contain 'addCopilotChatKeybindings'
        @($catalog.configurations | ForEach-Object { $_.key }) | Should -Contain 'setGitHubUser'
        @($catalog.configurations | ForEach-Object { $_.key }) | Should -Contain 'desktopLinkForThisApplication'
    }
}

Describe 'Invoke-Configurations' {
    It 'returns skipped when no configuration item is enabled' {
        $config = Get-DefaultConfig
        $config.modules.configurations.enabled = $true
        foreach ($key in @($config.modules.configurations.catalog.Keys)) {
            $config.modules.configurations.catalog[$key] = $false
        }

        $results = @(Invoke-Configurations -Config $config -ProjectRoot $projectRoot)
        $results.Count | Should -Be 1
        $results[0].Status | Should -Be 'SKIPPED'
    }
}

Describe 'Set-ConfigurationGitHubUser' {
    It 'returns error when gitHubUser values are missing' {
        $moduleConfig = @{
            gitHubUser = @{ name = ''; email = '' }
        }

        $result = Set-ConfigurationGitHubUser -Config $moduleConfig
        $result.Status | Should -Be 'ERROR'
    }
}

AfterAll {
    $testRoot = Join-Path $env:TEMP 'dev-bootstrap-tests-configurations'
    if (Test-Path $testRoot) {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
