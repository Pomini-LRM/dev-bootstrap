#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        $env:TEMP = [System.IO.Path]::GetTempPath()
    }

    $projectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $projectRoot 'src' 'common' 'Logger.ps1')
    . (Join-Path $projectRoot 'src' 'common' 'Report.ps1')

    $testLogDir = Join-Path $env:TEMP 'dev-bootstrap-tests-report' 'log'
    Initialize-Logger -LogDirectory $testLogDir -Level 'Error' -Silent | Out-Null
    Clear-ReportEntries
}

Describe 'Report entries' {
    BeforeEach {
        Clear-ReportEntries
    }

    It 'creates a valid report entry' {
        $entry = New-ReportEntry -Module 'GitHub' -Item 'owner/repo' -Status 'ADDED' -Message 'Cloned'
        $entry.Module | Should -Be 'GitHub'
        $entry.Status | Should -Be 'ADDED'
    }

    It 'adds and clears report entries' {
        Add-ReportEntry -Entry (New-ReportEntry -Module 'Test' -Item 'x' -Status 'NONE')
        (Get-ReportEntries).Count | Should -Be 1
        Clear-ReportEntries
        (Get-ReportEntries).Count | Should -Be 0
    }
}

Describe 'Write-FinalReport' {
    BeforeEach {
        Clear-ReportEntries
    }

    It 'returns zero when no errors exist' {
        Add-ReportEntry -Entry (New-ReportEntry -Module 'Test' -Item 'x' -Status 'ADDED')
        (Write-FinalReport -TotalDuration ([TimeSpan]::FromSeconds(1))) | Should -Be 0
    }

    It 'returns number of errors' {
        Add-ReportEntry -Entry (New-ReportEntry -Module 'Test' -Item 'x' -Status 'ERROR')
        Add-ReportEntry -Entry (New-ReportEntry -Module 'Test' -Item 'y' -Status 'ERROR')
        (Write-FinalReport -TotalDuration ([TimeSpan]::FromSeconds(1))) | Should -Be 2
    }

    It 'writes ERROR entries using Error log level' {
        Mock -CommandName Write-Log

        Add-ReportEntry -Entry (New-ReportEntry -Module 'Test' -Item 'x' -Status 'ERROR' -Message 'boom')
        $null = Write-FinalReport -TotalDuration ([TimeSpan]::FromSeconds(1))

        Should -Invoke Write-Log -ParameterFilter {
            $Level -eq 'Error' -and $Message -match 'ERROR\s+x'
        } -Times 1
    }

    It 'adds remediation steps for known auth failures' {
        Mock -CommandName Write-Log

        Add-ReportEntry -Entry (New-ReportEntry -Module 'GitHub' -Item 'AUTH' -Status 'ERROR' -Message 'GITHUB_TOKEN is not set and .env file is missing: C:\tmp\.env')
        $null = Write-FinalReport -TotalDuration ([TimeSpan]::FromSeconds(1))

        Should -Invoke Write-Log -ParameterFilter {
            $Level -eq 'Warning' -and $Message -match 'Recommended next steps'
        } -Times 1

        Should -Invoke Write-Log -ParameterFilter {
            $Level -eq 'Warning' -and $Message -match 'Create \.env from \.env\.example and set GITHUB_TOKEN'
        } -Times 1
    }
}

AfterAll {
    $testRoot = Join-Path $env:TEMP 'dev-bootstrap-tests-report'
    if (Test-Path $testRoot) {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
