@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0nova_studio.ps1"
if errorlevel 1 pause
