# Copilot Agents for dev-bootstrap

## Code Review Agent

When reviewing PowerShell code in this project:

1. Verify `#Requires -Version 7.0` is present in all `.ps1` files.
2. Ensure functions use `[CmdletBinding()]` and typed `param()` blocks.
3. Check that `Write-Log` is used instead of `Write-Host` in module code.
4. Confirm no aliases are used (PSScriptAnalyzer rule: `PSAvoidUsingCmdletAliases`).
5. Verify secrets are never hard-coded or logged.
6. Check that new functions follow the existing report entry pattern (`New-ReportEntry`).
7. Ensure error handling uses `try/catch` at operation boundaries, not defensively everywhere.

## Testing Agent

When writing or updating tests:

1. Use Pester 5+ syntax with `Describe`, `Context`, `It`, `BeforeAll`, `AfterAll`.
2. Place test files in `tests/` with the naming convention `<Feature>.Tests.ps1`.
3. Source required modules in `BeforeAll` using dot-sourcing from `$script:projectRoot`.
4. Initialize a temporary logger with `Initialize-Logger -LogDirectory $testLogDir -Level 'Error' -Silent`.
5. Clean up temporary files in `AfterAll`.
6. Restore environment variables modified during tests.
7. Use `Mock` for external dependencies (API calls, filesystem, git).

## Documentation Agent

When updating documentation:

1. Keep `README.md` as the single source of truth for user-facing docs.
2. Place developer/contributor docs in `docs/` or `CONTRIBUTING.md`.
3. Use consistent Markdown formatting with ATX-style headers.
4. Update the Table of Contents in README when adding/removing sections.
5. Keep configuration examples in sync with `config/config.example.json`.
