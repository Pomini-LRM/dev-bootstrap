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

## Build Windows Executable Package

Create distributable assets (`.exe` + `.env` template + `config` folder):

```powershell
pwsh ./scripts/Build-WindowsReleasePackage.ps1
```

Output is generated under `artifacts/` with:

- `dev-bootstrap-windows-vX.Y.Z.zip`
- `dev-bootstrap-windows-vX.Y.Z.zip.sha256`

Package characteristics:

- The ZIP is built for distribution without shipping `.ps1/.psm1/.psd1` source files.
- Runtime logic is bundled into `dev-bootstrap.exe`.
- Keep `modules.automation.enabled = false` in the distributed config unless you distribute source scripts separately.

## Publish GitHub Release (Automated)

For maintainers, this command automates:

1. version bump,
2. quality gate,
3. commit,
4. git tag creation,
5. push to GitHub.

Then GitHub Actions `Release` workflow publishes the release assets automatically.

Use **GitHub Releases** for this project distribution:

- `dev-bootstrap.exe`
- `dev-bootstrap-windows-vX.Y.Z.zip`
- `dev-bootstrap-windows-vX.Y.Z.zip.sha256`

Do **not** use GitHub Packages for this installer payload. Packages are intended for package ecosystems and registries (for example container images, npm, NuGet), while this project publishes downloadable desktop artifacts.

```powershell
pwsh ./scripts/Publish-GitHubRelease.ps1 -Part patch
```

Alternative version increments:

```powershell
pwsh ./scripts/Publish-GitHubRelease.ps1 -Part minor
pwsh ./scripts/Publish-GitHubRelease.ps1 -Part major
```

Useful switches:

- `-SkipVersionBump` if version was already updated.
- `-SkipQualityGate` only for emergency/manual scenarios.
- `-SkipPush` to create commit/tag locally and push later.

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
