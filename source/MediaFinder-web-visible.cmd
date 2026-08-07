@echo off
rem MediaFinder web console - visible window mode (fallback if AV blocks hidden launch)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0MediaFinderServer.ps1"
