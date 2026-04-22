---
applyTo: 'tests/**/*.ps1'
---

# Test Maintenance Rules

- Use Pester 5 syntax and keep test names behavior-focused.
- Prefer deterministic tests with mocks for external tools such as `git`, `az`, `docker`, and web requests.
- When project defaults or catalogs change, update the affected tests in the same change.
- After changing tests or production PowerShell code, run `pwsh ./scripts/Invoke-CodeQuality.ps1`.
- Keep fixture setup minimal and restore environment variables or temporary files in `AfterAll`.
