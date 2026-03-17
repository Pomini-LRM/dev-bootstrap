@echo off
setlocal
where pwsh >nul 2>nul
if %errorlevel%==0 (
  pwsh -NoProfile -Command "if ($PSVersionTable.PSVersion.Major -ge 7) { exit 0 } else { exit 1 }"
  if errorlevel 1 (
    echo PowerShell 7+ is required. Found an unsupported pwsh version.
    echo Install or update PowerShell 7, then retry.
    goto :offerInstall
  )
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-bootstrap.ps1" %*
  goto :end
) else (
  echo PowerShell 7+ is required. 'pwsh' was not found on PATH.
  echo Install PowerShell 7 and retry.
  goto :offerInstall
)
:offerInstall
echo.
set /p RUN_PREP=Do you want to run scripts\install-prerequisites-windows.ps1 now? [Y/n]: 
if /I "%RUN_PREP%"=="" goto :runInstall
if /I "%RUN_PREP%"=="y" goto :runInstall
if /I "%RUN_PREP%"=="yes" goto :runInstall
goto :end

:runInstall
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-prerequisites-windows.ps1"
echo.
echo Prerequisite installer completed. Re-run dev-bootstrap launcher.
:end
echo.
pause
endlocal
