#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $projectRoot 'src' 'common' 'Logger.ps1')
    . (Join-Path $projectRoot 'src' 'common' 'Config.ps1')
    . (Join-Path $projectRoot 'src' 'common' 'Utilities.ps1')

    $testLogDir = Join-Path $env:TEMP 'dev-bootstrap-tests' 'log'
    Initialize-Logger -LogDirectory $testLogDir -Level 'Error' -Silent | Out-Null
}

Describe 'Get-DefaultConfig' {
    It 'returns required sections and modules' {
        $config = Get-DefaultConfig
        $config.general | Should -Not -BeNullOrEmpty
        $config.modules.appInstaller | Should -Not -BeNullOrEmpty
        $config.modules.github | Should -Not -BeNullOrEmpty
        $config.modules.devops | Should -Not -BeNullOrEmpty
        $config.modules.acr | Should -Not -BeNullOrEmpty
    }

    It 'supports Windows and Linux module path styles' {
        $config = Get-DefaultConfig
        $config.modules.github.path | Should -Not -BeNullOrEmpty
        if ($IsWindows) {
            (Resolve-ConfiguredPath -Path 'D:\\GitHub') | Should -Match '^[Dd]:\\'
        }
        else {
            (Resolve-ConfiguredPath -Path '/opt/data/GitHub').StartsWith('/opt/data') | Should -BeTrue
        }
    }

    It 'defines optional app toggles for appInstaller' {
        $config = Get-DefaultConfig
        $config.modules.appInstaller.recommendedApps.winget | Should -BeTrue
        $config.modules.appInstaller.recommendedApps.vscode | Should -BeTrue
        $config.modules.appInstaller.recommendedApps.notepadplusplus | Should -BeTrue
        $config.modules.appInstaller.optionalApps.githubDesktop | Should -BeFalse
        $config.modules.appInstaller.optionalApps.inkscape | Should -BeFalse
        $config.modules.appInstaller.optionalApps.pythonLatest | Should -BeFalse
        $config.modules.appInstaller.optionalApps.teamviewer | Should -BeFalse
    }
}

Describe 'Merge-Hashtable' {
    It 'merges nested hashtables' {
        $result = Merge-Hashtable -Default @{ a = 1; n = @{ x = 1; y = 2 } } -Override @{ n = @{ y = 8 } }
        $result.a | Should -Be 1
        $result.n.x | Should -Be 1
        $result.n.y | Should -Be 8
    }
}

Describe 'Test-DevBootstrapConfig' {
    It 'passes for default config' {
        $config = Get-DefaultConfig
        (Test-DevBootstrapConfig -Config $config).Count | Should -Be 0
    }

    It 'fails when general is missing' {
        $errors = Test-DevBootstrapConfig -Config @{ modules = @{} }
        $errors | Should -Contain "Missing required section 'general'."
    }

    It 'fails when modules are missing' {
        $errors = Test-DevBootstrapConfig -Config @{ general = @{ logDirectory = 'log' } }
        $errors | Should -Contain "Missing required section 'modules'."
    }
}

AfterAll {
    $testRoot = Join-Path $env:TEMP 'dev-bootstrap-tests'
    if (Test-Path $testRoot) {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
