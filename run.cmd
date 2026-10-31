@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex (Get-Content '%~dp0init.ps1' -Encoding UTF8 -Raw)"
pause

