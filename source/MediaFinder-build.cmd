@echo off
rem Build MediaFinder.exe (single portable executable)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MediaFinder-build.ps1"
pause
