@echo off
setlocal
where pwsh >nul 2>nul
if %errorlevel%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-bootstrap.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-bootstrap.ps1" %*
)
endlocal
