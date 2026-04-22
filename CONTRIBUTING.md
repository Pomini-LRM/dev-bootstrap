# Contributing to dev-bootstrap

Thank you for your interest in contributing. This guide covers the basics for running checks locally and submitting changes.

## Prerequisites

- [PowerShell 7+](https://github.com/PowerShell/PowerShell)
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
- [Pester 5+](https://pester.dev/)

Install the required modules:

```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
Install-Module -Name Pester -MinimumVersion 5.0 -Scope CurrentUser -Force
```

## Lint

Run the local quality gate:

```powershell
pwsh ./scripts/Invoke-CodeQuality.ps1
```

VS Code users can run the same commands from `.vscode/tasks.json`.

If formatting drift is reported, apply formatting and rerun the quality gate:

```powershell
pwsh ./scripts/Invoke-CodeQuality.ps1 -FixFormat
```

If you only need static analysis, run PSScriptAnalyzer against the project targets:

```powershell
$targets = @('dev-bootstrap.ps1', 'DevBootstrap.psm1', 'DevBootstrap.psd1', 'scripts', 'src', 'tests')
foreach ($target in $targets) {
	Invoke-ScriptAnalyzer -Path $target -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
}
```

Error-severity issues must be resolved before merge. Warnings should be addressed when practical.

## Tests

Run the Pester test suite:

```powershell
Invoke-Pester -Path .\tests -Output Detailed
```

All tests must pass on both Linux and Windows.

## Style Conventions

- Target PowerShell 7.0+ syntax only.
- Use 4-space indentation (no tabs).
- Follow the rules in `.github/linters/PSScriptAnalyzerSettings.psd1`.
- Apply formatting with `pwsh ./scripts/Format-Code.ps1`.
- Use approved verbs (`Get-Verb`) for function names.
- Add `[CmdletBinding()]` and `param()` blocks to all advanced functions.

## Submitting Changes

1. Fork the repository and create a feature branch from `main`.
2. Make your changes and verify format + lint + tests pass locally.
3. Open a pull request against `main`.
4. Fill in the PR template checklist.

## License

By contributing you agree that your contributions will be licensed under the [MIT License](LICENSE).
