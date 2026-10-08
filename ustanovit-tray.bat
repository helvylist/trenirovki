@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0trenirovki-tray.ps1"
if errorlevel 1 pause
