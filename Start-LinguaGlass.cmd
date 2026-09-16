@echo off
if exist "%~dp0src-tauri\target\debug\linguaglass.exe" (
  start "" "%~dp0src-tauri\target\debug\linguaglass.exe"
  exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\desktop.ps1"
if errorlevel 1 pause
