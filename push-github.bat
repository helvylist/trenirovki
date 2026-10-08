@echo off
chcp 65001 >nul
set "S=%~dp0trenirovki-tray.ps1"
if not exist "%S%" set "S=%LOCALAPPDATA%\Trenirovki\trenirovki-tray.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%S%" -Push
pause
