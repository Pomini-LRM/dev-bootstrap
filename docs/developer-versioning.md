# Developer Versioning Guide

This document is for maintainers and contributors.

## Purpose

The versioning workflow is based on:

- `config/version.json` as the single source of script version
- `scripts/bump-version.ps1` for semantic version increments

## Check Current Version

```powershell
pwsh ./dev-bootstrap.ps1 -ShowVersion
```

## Bump Version

Supported parts:

- `patch`
- `minor`
- `major`

Examples:

```powershell
# Preview next patch version without writing files
pwsh ./scripts/bump-version.ps1 -Part patch -PrintOnly

# Apply patch bump
pwsh ./scripts/bump-version.ps1 -Part patch

# Apply minor bump
pwsh ./scripts/bump-version.ps1 -Part minor

# Apply major bump
pwsh ./scripts/bump-version.ps1 -Part major
```

## Debug Mode for Scripts

All scripts with `CmdletBinding()` support common PowerShell debug switches.

Run with `-Debug`:

```powershell
# Main orchestrator debug
pwsh ./dev-bootstrap.ps1 -RunMode full -Debug

# Interactive setup debug
pwsh ./scripts/setup-config-interactive.ps1 -Debug

# Version bump debug
pwsh ./scripts/bump-version.ps1 -Part patch -PrintOnly -Debug
```

Optional verbose tracing:

```powershell
pwsh ./dev-bootstrap.ps1 -RunMode full -Verbose
```

For deep troubleshooting in a local shell session:

```powershell
Set-PSDebug -Trace 1
pwsh ./dev-bootstrap.ps1 -RunMode full
Set-PSDebug -Off
```
