@echo off
if not exist "%~dp0CMNSetup.exe" (
  echo Extract the complete customer download before running Install.cmd.
  pause
  exit /b 1
)
start "" "%~dp0CMNSetup.exe"
