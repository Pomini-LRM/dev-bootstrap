# Fresh-Install Troubleshooting

## Issue 1: VS Code does not add "Open with Code" to the context menu

### Root cause
When VS Code is installed through `winget` with `--silent`, the installer post-install actions may not run. The Explorer context-menu entries are normally created by those post-install steps and require **Administrator** rights because they write to the Windows registry.

### Fix
Create the registry entries explicitly after a successful VS Code installation. The relevant keys are:

```text
HKEY_CLASSES_ROOT\*\shell\VSCode
HKEY_CLASSES_ROOT\Directory\shell\VSCode
HKEY_CLASSES_ROOT\Directory\Background\shell\VSCode
```

Recommended implementation:
1. Add `Add-VSCodeContextMenu` to `src/common/Utilities.ps1`.
2. Call it after a successful VS Code install in `Install-ViaWinget`.
3. Use registry writes, not the installer defaults, to keep the behavior deterministic.

## Issue 2: Git and NVM are available only in an elevated terminal

### Root cause
This usually indicates a PATH scope problem, not a missing installation. On one machine the script likely ran without admin rights, so the installers updated only the current process or user session. A new non-elevated terminal then did not inherit the updated system PATH. The different behavior on the second machine is consistent with either an elevated run or pre-existing global installs.

### Fix
Enforce the following:

1. Run `dev-bootstrap.ps1` with Administrator privileges.
2. Refresh the current PowerShell session after installing tools that change PATH.
3. Show a clear post-install note telling the user to open a new terminal before validating `git`, `nvm`, `docker`, or `code`.

Recommended implementation:
1. Add an admin check and elevation prompt at the start of `dev-bootstrap.ps1`.
2. Add `Sync-EnvironmentVariablesFromSystem` in `src/common/Utilities.ps1`.
3. Invoke the sync step after installing path-dependent tools such as Git, NVM, Docker, Azure CLI, and PowerShell 7.
4. Add a short post-install message that tells users to restart the terminal or VS Code if tools are still missing.

## Verification commands

After installation, verify that these commands are available from a new terminal:

- `git --version`
- `nvm --version`
- `docker --version`
- `code --version`
- `pwsh --version`

## Recommendation

Treat Administrator execution as the default requirement for first-run bootstrap on a fresh Windows machine. That removes the ambiguity between per-user and system-wide PATH updates and avoids inconsistent behavior across newly formatted PCs.
