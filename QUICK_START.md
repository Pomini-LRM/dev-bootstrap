# Quick Start (Windows)

## 1. Install Prerequisites

If PowerShell is already available:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-prerequisites-windows.ps1
```

If PowerShell is **not installed**:

```cmd
scripts\install-powershell.cmd
```

Close and reopen the terminal after installation.

## 2. Configure

Interactive wizard (recommended):

```powershell
pwsh -ExecutionPolicy Bypass .\scripts\setup-config-interactive.ps1
```

Or manually:

```powershell
Copy-Item .\config\config.example.json .\config\config.json
Copy-Item .\.env.example .\.env
```

Edit `config/config.json` and `.env` with your settings and tokens.

## 3. Run

```powershell
pwsh -ExecutionPolicy Bypass .\dev-bootstrap.ps1
```

Single module:

```powershell
pwsh -ExecutionPolicy Bypass .\dev-bootstrap.ps1 -RunMode github
```

For full documentation, see [README.md](README.md).
