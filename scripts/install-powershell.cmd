@echo off
setlocal
REM Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
REM
REM Installs PowerShell 7 via winget from a plain CMD environment.
REM Use this script when neither pwsh nor powershell are available on the system.

echo.
echo ============================================================
echo   dev-bootstrap - PowerShell 7 installer (CMD)
echo ============================================================
echo.

where winget >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: winget is not available on this system.
    echo.
    echo Install winget from the Microsoft Store (App Installer) or download it from:
    echo   https://github.com/microsoft/winget-cli/releases
    echo.
    echo After installing winget, re-run this script.
    goto :end
)

echo Detected winget. Installing PowerShell 7...
echo.
winget install --id Microsoft.PowerShell --accept-source-agreements --accept-package-agreements --silent
if %errorlevel% neq 0 (
    echo.
    echo WARNING: winget install exited with code %errorlevel%.
    echo If PowerShell 7 was already installed, this may be expected.
    echo Otherwise, check winget logs and retry.
) else (
    echo.
    echo PowerShell 7 installed successfully.
)

echo.
echo Verifying installation...
where pwsh >nul 2>nul
if %errorlevel%==0 (
    echo pwsh found on PATH. PowerShell 7 is ready.
    echo.
    echo Next steps:
    echo   1. Close and reopen your terminal to refresh PATH.
    echo   2. Run: pwsh -ExecutionPolicy Bypass .\dev-bootstrap.ps1
) else (
    echo pwsh was not found on PATH yet.
    echo Close and reopen your terminal, then verify with: pwsh --version
    echo If still not found, add the PowerShell install directory to PATH manually.
)

:end
echo.
pause
endlocal
