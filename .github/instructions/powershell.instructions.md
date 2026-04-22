---
applyTo: '**/*.{ps1,psm1,psd1}'
---

# PowerShell Implementation Rules

- Write code, comments, log messages, commit messages, and user-facing text in professional, concise English.
- Target PowerShell 7.0+ only.
- Use approved verbs, meaningful names, small functions, and clear control flow.
- Add `[CmdletBinding()]` and a typed `param()` block to every advanced function.
- Use `Write-Log` for persisted module logging. Use `Write-ConsoleStatus` only for console-only progress output.
- Avoid aliases and positional parameters.
- After changing PowerShell code, run `pwsh ./scripts/Invoke-CodeQuality.ps1`. If formatting is needed, run `pwsh ./scripts/Invoke-CodeQuality.ps1 -FixFormat` first.
- When modifying automation defaults, keep `src/automation/`, `config/automation.catalog.json`, `config/config.example.json`, tests, and README aligned.
