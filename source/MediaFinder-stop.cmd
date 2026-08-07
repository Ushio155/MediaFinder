@echo off
rem Stop the MediaFinder background server
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = Get-CimInstance Win32_Process -Filter `"Name='powershell.exe'`" | Where-Object { $_.CommandLine -like '*MediaFinderServer.ps1*' }; if ($p) { $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; Write-Host 'MediaFinder server stopped' } else { Write-Host 'MediaFinder server is not running' }"
pause
