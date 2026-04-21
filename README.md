# dev-bootstrap

Cross-platform environment bootstrap suite for PowerShell 7+.

`dev-bootstrap` is designed for first-time setup on a new machine and repeated update runs afterward. It installs required software, synchronizes repositories, and pulls container images through a modular orchestrator.

## Table of Contents

- [dev-bootstrap](#dev-bootstrap)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Execution Prerequisites](#execution-prerequisites)
  - [First-Time Setup](#first-time-setup)
    - [Windows](#windows)
    - [Linux](#linux)
  - [Configuration](#configuration)
    - [General](#general)
    - [GitHub Settings](#github-settings)
    - [DevOps Settings](#devops-settings)
    - [ACR Settings](#acr-settings)
    - [AppInstaller and Module Dependencies](#appinstaller-and-module-dependencies)
  - [Run Modes](#run-modes)
  - [Modules](#modules)
    - [appInstaller](#appinstaller)
    - [automation](#automation)
      - [Adding a new automation script](#adding-a-new-automation-script)
      - [Migration from `configurations`](#migration-from-configurations)
    - [github](#github)
    - [devops](#devops)
    - [acr](#acr)
  - [Token Guides](#token-guides)
  - [Logging and Report](#logging-and-report)
  - [Security](#security)
  - [Troubleshooting](#troubleshooting)
  - [Developer Documentation](#developer-documentation)
  - [Known Limitations](#known-limitations)
  - [License](#license)

## Overview

Main capabilities:

- Orchestrated full run or per-module execution.
- Application installation and dependency enforcement.
- GitHub repository synchronization.
- Azure DevOps repository synchronization (optional wiki sync).
- Azure Container Registry image pull.
- Persistent logging with standardized final report.

The tool is idempotent and intended for both:

- Initial workstation bootstrap.
- Ongoing update/sync runs.

## Execution Prerequisites

These are the **minimum prerequisites required to run dev-bootstrap itself**:

- PowerShell 7+
- Network access to package and git providers
- A supported OS: Windows or Linux

Use dedicated bootstrap scripts:

- Windows (PowerShell available): [scripts/install-prerequisites-windows.ps1](scripts/install-prerequisites-windows.ps1)
- Windows (no PowerShell): [scripts/install-powershell.cmd](scripts/install-powershell.cmd)
- Linux: [scripts/install-prerequisites-linux.sh](scripts/install-prerequisites-linux.sh)

If PowerShell is not installed at all (neither `pwsh` nor `powershell`), use the CMD-based installer:

```cmd
scripts\install-powershell.cmd
```

This script installs PowerShell 7 via `winget` from a plain CMD environment. After installation, close and reopen the terminal, then proceed with the normal setup flow.
- Linux: [scripts/install-prerequisites-linux.sh](scripts/install-prerequisites-linux.sh)

Module-specific dependencies are not listed as global prerequisites. They are automatically handled by `appInstaller` when the related modules are enabled.

## First-Time Setup

1. Clone the repository.
2. Install minimum prerequisites for your OS.
3. Create config and environment files.
4. Run full bootstrap.

### Windows

If PowerShell is already available:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-prerequisites-windows.ps1

# Option A: interactive configuration wizard
pwsh .\scripts\setup-config-interactive.ps1

# Option B: manual file copy
Copy-Item .\.env.example .\.env

pwsh -ExecutionPolicy Bypass .\dev-bootstrap.ps1
```

If PowerShell is **not installed** (new machine without `pwsh` or `powershell`):

```cmd
scripts\install-powershell.cmd
REM Close and reopen the terminal after installation, then continue:
powershell -ExecutionPolicy Bypass -File .\scripts\install-prerequisites-windows.ps1
pwsh -ExecutionPolicy Bypass .\dev-bootstrap.ps1
```

Execution policy note:

- `dev-bootstrap-launcher.cmd` uses `-ExecutionPolicy Bypass` for bootstrap convenience.
- In enterprise environments, prefer invoking with PowerShell 7 directly and stricter policy (for example `RemoteSigned`) when governance requires it.

Interactive wizard notes:

- In module selection, use arrow keys to move, space to select/unselect, enter to confirm.
- If `config/config.json` already exists, it is loaded and reused as defaults.
- Before writing changes, the previous config is saved as a timestamped backup (`config.json.bak.yyyyMMdd_HHmmss`).

### Linux

```bash
chmod +x ./scripts/install-prerequisites-linux.sh
./scripts/install-prerequisites-linux.sh

# Option A: interactive configuration wizard
pwsh ./scripts/setup-config-interactive.ps1

# Option B: manual file copy
cp .env.example .env

pwsh ./dev-bootstrap.ps1
```

Interactive wizard notes:

- In module selection, use arrow keys to move, space to select/unselect, enter to confirm.
- If `config/config.json` already exists, it is loaded and reused as defaults.
- Before writing changes, the previous config is saved as a timestamped backup (`config.json.bak.yyyyMMdd_HHmmss`).

## Configuration

Copy and edit:

```bash
cp config/config.example.json config/config.json
cp .env.example .env
```

Interactive alternative:

```powershell
pwsh .\scripts\setup-config-interactive.ps1
```

Schema support:

- JSON Schema is available at `config/config.schema.json`.
- You can reference it from config files with `"$schema": "./config.schema.json"` to enable editor validation.

The interactive wizard supports incremental updates:

- Existing values from `config/config.json` are preloaded as defaults.
- You can modify only what you need and keep the rest unchanged.
- The previous file is automatically backed up before each save.
- Disabled modules are saved in compact form (`"enabled": false` only); full module properties are restored automatically when re-enabled in the wizard.

### General

```json
"general": {
  "logDirectory": "log",
  "failFast": false,
  "silent": false,
  "debug": false,
  "noConfirm": false,
  "force": false
}
```

`general.force` behavior:

- `false` (default): app installation keeps idempotent mode and skips already installed apps.
- `true`: app installation attempts upgrade/reinstall behavior for already installed apps (where supported by package manager).
- Scope: `general.force` is a global default consumed by `appInstaller`.

### GitHub Settings

```json
"github": {
  "enabled": true,
  "path": "D:\\GitHub",
  "usersInclude": ["*"],
  "usersExclude": [],
  "organizationsInclude": ["*"],
  "organizationsExclude": [],
  "setFolderIcon": true
}
```

Behavior:

- `path` must be a full path (absolute path or `~` home-based path).
- For each filter pair, exclude wins over include.
- `usersInclude = ["*"]` and `usersExclude = []` sync all user-owned repositories.
- `usersInclude = ["*"]` and `usersExclude = ["exampleUser"]` sync all user-owned repositories except `exampleUser`.
- `usersInclude = ["exampleUser"]` and `usersExclude = []` sync only `exampleUser` user-owned repositories.
- The same include/exclude logic applies to organizations through `organizationsInclude` and `organizationsExclude`.
- Ambiguous filter cases are accepted with deterministic behavior and warning logs:
  - Include contains `*` plus explicit names: explicit names are redundant.
  - Exclude contains `*`: everything in that scope is excluded.
  - The same token appears in include and exclude: exclude wins.
- Path layout is always:
  - `<path>/<owner>/<repo>`

Example:

- `path = D:\\GitHub`
- Owner `my-org`, repo `platform-api`
- Result: `D:\GitHub\my-org\platform-api`

### DevOps Settings

```json
"devops": {
  "enabled": true,
  "path": "D:\\DevOps",
  "projectsInclude": ["*"],
  "projectsExclude": [],
  "includeWikis": false,
  "setFolderIcon": true
}
```

Behavior:

- `path` must be a full path (absolute path or `~` home-based path).
- Organizations must be provided through `AZURE_DEVOPS_ORGS` (comma-separated).
- `projectsInclude` / `projectsExclude` follow the same include/exclude rules used for GitHub filters.
- If `includeWikis` is true, all code wikis in scope are synced.
- If `includeWikis` is false, no wiki is synced.
- Path layout:
  - `<path>/<organization>/<project>/<repo>`

### ACR Settings

```json
"acr": {
  "enabled": true,
  "registries": ["youracr"],
  "imagesInclude": ["*"],
  "imagesExclude": [],
  "retryCount": 3,
  "retryDelaySeconds": 10
}
```

Behavior:

- `registries` defines the ACR registries to authenticate against.
- `imagesInclude` / `imagesExclude` follow the same include/exclude rules used for GitHub and DevOps filters.
- `imagesInclude = ["*"]` pulls all repositories from the configured registries.
- `imagesInclude = ["plrm-vscode", "plrm-jupyter"]` pulls only those images.
- If an image appears in both include and exclude, exclude wins.

### AppInstaller and Module Dependencies

`appInstaller` uses three app groups:

- Module-required apps: managed automatically from enabled modules.
- Recommended apps: enabled manually through booleans in config.
- Optional apps: enabled manually through booleans in config.

The complete app metadata (`wingetId`, `linuxPackage`, `linuxCommand`) is stored in:

- `config/appinstaller.catalog.json`

In `config/config.json`, app toggles are split into `recommendedApps` and `optionalApps`:

```json
"appInstaller": {
  "enabled": true,
  "force": false,
  "recommendedApps": {
    "gnuWin32Make": true,
    "notepadplusplus": true,
    "nvmWindows": true,
    "python31012": true,
    "vscode": true,
    "winget": true
  },
  "optionalApps": {
    "githubCopilot": false,
    "githubDesktop": false,
    "inkscape": false,
    "pythonLatest": false,
    "teamviewer": false
  }
}
```

When a module is enabled, module-required apps are automatically included and cannot be disabled by optional app toggles.

## Run Modes

```powershell
# Full run (enabled modules, default)
pwsh ./dev-bootstrap.ps1

# Equivalent explicit form
pwsh ./dev-bootstrap.ps1 -RunMode full

# Single module
pwsh ./dev-bootstrap.ps1 -RunMode appInstaller
pwsh ./dev-bootstrap.ps1 -RunMode automation
pwsh ./dev-bootstrap.ps1 -RunMode github
pwsh ./dev-bootstrap.ps1 -RunMode devops
pwsh ./dev-bootstrap.ps1 -RunMode acr

```

Common options:

- `-NoConfirm` (default is disabled; prompts are shown unless you enable this)
- `-Silent`
- `-Debug`
- `-FailFast`
- `-Force`
- `-ConfigPath <path>`

Developer-only version management and release notes are documented here:

- `docs/developer-versioning.md`

## Modules

### appInstaller

- Installs apps on Windows (winget) and Linux (apt/dnf/yum/zypper).
- Idempotent behavior with `INSTALLED`, `ALREADY_PRESENT`, `SKIPPED`, `ERROR` statuses.
- On Windows with winget, runtime logs and final report include best-effort version details (`Current`, `Latest`) when detectable.
- `PowerShell 7` is always treated as required baseline dependency when `appInstaller` runs.
- On subsequent runs, AppInstaller always attempts to update required apps and selected optional apps to the latest available version.
- `-Force` remains available for package managers/scenarios that require forced reinstall behavior.
- Enforces module-required apps for enabled modules.
- Recommended app toggles:
  - `gnuWin32Make`
  - `notepadplusplus`
  - `nvmWindows`
  - `python31012`
  - `vscode`
  - `winget`
- Optional app toggles:
  - `githubCopilot`
  - `githubDesktop`
  - `inkscape`
  - `pythonLatest`
  - `teamviewer`

`force` behavior and precedence:

- `modules.appInstaller.force = false`: keep normal idempotent behavior unless overridden.
- `modules.appInstaller.force = true`: force behavior always active for appInstaller.
- Effective force precedence is OR-based:
  - CLI `-Force`
  - `general.force`
  - `modules.appInstaller.force`

### automation

- General-purpose automation script runner. Executes `.ps1` scripts defined in `config/automation.catalog.json`.
- Each catalog entry specifies a `scriptFile` field pointing to a script in `src/automation/`.
- Built-in automation scripts (migrated from the former `configurations` module):
  - add `GnuWin32\bin` to user `PATH`
  - copy VS Code Copilot Chat keybindings template
  - set global git user name/email
  - create desktop shortcut for `dev-bootstrap`
- Runs idempotently with `UPDATED`, `NONE`, `SKIPPED`, `ERROR` statuses.
- Fully extensible: add new scripts without modifying the runner code.

#### Adding a new automation script

1. Create a `.ps1` script in `src/automation/` (e.g. `My-CustomTask.ps1`).
2. The script must accept two mandatory parameters and return a result hashtable:

   ```powershell
   param(
       [Parameter(Mandatory)][hashtable]$ModuleConfig,
       [Parameter(Mandatory)][string]$ProjectRoot
   )

   # ... your logic ...

   return @{ Status = 'UPDATED'; Message = 'Description of what was done.' }
   ```

   Valid `Status` values: `UPDATED`, `NONE`, `SKIPPED`, `ERROR`.

3. Add an entry to `config/automation.catalog.json`:

   ```json
   {
     "key": "myCustomTask",
     "name": "My Custom Task",
     "description": "Describe what this automation does.",
     "scriptFile": "My-CustomTask.ps1"
   }
   ```

4. Enable it in `config/config.json`:

   ```json
   "automation": {
     "enabled": true,
     "catalog": {
       "myCustomTask": true
     }
   }
   ```

5. Run:

   ```powershell
   pwsh ./dev-bootstrap.ps1 -RunMode automation
   ```

#### Migration from `configurations`

The former `configurations` module has been renamed to `automation`. If your `config/config.json` still uses `modules.configurations`, the tool automatically migrates it to `modules.automation` at load time with a deprecation warning. Update your config file to use `automation` directly to suppress the warning.

### github

- Syncs repositories visible to the authenticated token.
- **Public repositories are always included** regardless of token scope. The module supplements the primary API call with dedicated public repo fetches for the authenticated user and their organizations.
- Supports user and organization include/exclude filters.
- Full pagination and retry.
- Detects local orphan repositories.

### devops

- Syncs repositories in selected organizations/projects.
- Optional all-or-none code wiki synchronization.
- Retry and orphan detection.

### acr

- Verifies Azure CLI and Docker availability.
- Logs in to Azure and ACR registries.
- Pulls configured images with retry behavior.

## Token Guides

- GitHub module: configure `GITHUB_TOKEN` (see [docs/github-classic-token.md](docs/github-classic-token.md)).
- DevOps module: configure `AZURE_DEVOPS_PAT` and `AZURE_DEVOPS_ORGS` (see [docs/azure-devops-pat.md](docs/azure-devops-pat.md)).
- ACR module (this project): configure only `AZURE_TENANT_ID`.
  - Ask your IT Admin for the correct tenant id.
  - No client id/secret is required by this project.
  - The application will request Azure login whenever needed.
  - Details: [docs/acr-authentication.md](docs/acr-authentication.md)

## Logging and Report

Log file naming format:

- `YYYYMMDD_HHMMSS_log.log`

Example:

- `log/20260314_143022_log.log`

Final report statuses:

- `ADDED`
- `UPDATED`
- `NONE`
- `SKIPPED`
- `ERROR`
- `ORPHAN`
- `INSTALLED`
- `ALREADY_PRESENT`

## Security

- Secrets are sourced from environment variables and/or `.env`.
- Secrets are redacted from logs and console output.
- Do not commit `.env`.

## Troubleshooting

- `Configuration file not found: ...config/config.json`: create the file from template or run `pwsh .\scripts\setup-config-interactive.ps1`, then retry.
- `Environment file not found: .../.env`: create `.env` from `.env.example` unless all required tokens are already set as environment variables.
- `GITHUB_TOKEN is not set and .env file is missing: ...`: create `.env` from `.env.example`, then set `GITHUB_TOKEN`.
- `GITHUB_TOKEN is defined in .env but empty.`: assign a non-empty token.
- `GITHUB_TOKEN is not set in .env or environment variables.`: define token in `.env` or at user/machine level.
- `AZURE_DEVOPS_PAT is not set and .env file is missing: ...`: create `.env` from `.env.example`, then set `AZURE_DEVOPS_PAT`.
- `AZURE_DEVOPS_PAT is defined in .env but empty.`: assign a non-empty PAT.
- `AZURE_DEVOPS_PAT is not set in .env or environment variables.`: define PAT in `.env` or at user/machine level.
- `No DevOps organization resolved. Configure AZURE_DEVOPS_ORGS.`: set `AZURE_DEVOPS_ORGS` in environment or `.env`.
- `No supported package manager detected`: install a supported package manager for your OS.
- `Docker daemon is not available`: start Docker service.
- `Git Credential Manager` prompt appears during `github` sync:
  - run with `-NoConfirm` to avoid confirmation pauses,
  - clear process-scoped overrides before run: `[System.Environment]::SetEnvironmentVariable('GITHUB_TOKEN',$null,'Process')`,
  - verify the token loaded by the script via log line `GitHub token diagnostics`.
- Final report includes a `Recommended next steps` section when known `ERROR` patterns are detected.
- `winget ... failed with exit code -1978335189 (0x8A15002B)`: usually source/agreement issue. Run `winget source reset --force`, `winget source update`, then `winget list --accept-source-agreements`.
- `winget ... failed with exit code -1978334975 (0x8A150101)`: possible package/source metadata conflict. Run `winget show --id <packageId> --exact`, then retry.

## Developer Documentation

For contributors and maintainers:

- Versioning workflow: `docs/developer-versioning.md`
- App catalog authoring (where to find `wingetId`, `linuxPackage`, `linuxCommand`): `docs/developer-app-catalog.md`
- CI quality gates: `.github/workflows/ci.yml`
- Static analysis policy: `PSScriptAnalyzerSettings.psd1`

## Known Limitations

- macOS is not fully supported for automated installation paths.
- DevOps cross-organization discovery depends on configured organization scope.

## License

MIT. See [LICENSE](LICENSE).
