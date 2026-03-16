# Developer App Catalog Guide

This guide is for maintainers who need to add or update entries in `config/appinstaller.catalog.json`.

## Purpose

Each app entry defines metadata used by `appInstaller` across platforms:

```json
{
  "key": "inkscape",
  "name": "Inkscape",
  "category": "optional",
  "wingetId": "Inkscape.Inkscape",
  "linuxPackage": "inkscape",
  "linuxCommand": "inkscape"
}
```

## Field Meaning

- `key`: internal unique identifier (lowerCamelCase; stable over time).
- `name`: display name in logs and reports.
- `category`: one of `required`, `recommended`, `optional`.
- `wingetId`: package ID for Windows (`winget`).
- `linuxPackage`: package name used by Linux package manager.
- `linuxCommand`: executable command expected after install.
- `supportedPlatforms` (optional): restrict app to specific platforms (for example `"Windows"`).

## Where To Find Values

### wingetId (Windows)

Use official Windows Package Manager sources:

1. Microsoft winget website: https://winget.run
2. Winget package community repo: https://github.com/microsoft/winget-pkgs
3. Local CLI checks:

```powershell
winget search "Inkscape"
winget show --id Inkscape.Inkscape --exact
```

Pick the ID shown in `Id` from `winget show`.

### linuxPackage and linuxCommand (Linux)

Validate against target distro repositories:

- Ubuntu/Debian (`apt`):

```bash
apt search inkscape
apt show inkscape
```

- Fedora/RHEL (`dnf`):

```bash
dnf search inkscape
dnf info inkscape
```

- openSUSE (`zypper`):

```bash
zypper search inkscape
```

The package name usually maps to the executable, but always verify with:

```bash
command -v <linuxCommand>
```

## Category Rules

- `required`: auto-included by module dependency mapping (`requiredByModule`).
- `recommended`: user-facing defaults in `modules.appInstaller.recommendedApps`.
- `optional`: disabled-by-default extras in `modules.appInstaller.optionalApps`.

If an app is moved between categories, update defaults in:

- `src/common/Config.ps1`
- `config/config.example.json`

## Validation Checklist

1. Add or update entry in `config/appinstaller.catalog.json`.
2. Keep app ordering by group, then alphabetical within the group.
3. Ensure `key` uniqueness.
4. Run tests:

```powershell
Invoke-Pester -Path ./tests/
```

5. Optional runtime verification:

```powershell
pwsh ./dev-bootstrap.ps1 -RunMode appInstaller -NoConfirm
```

## Notes on Removal

If an app is removed from catalog but still present in old user configs, runtime behavior is:

- marked as `SKIPPED`
- message: `Requested app '<key>' is no longer available in the catalog.`

This avoids hard failures with legacy config files.
