@echo off
if not exist "%LOCALAPPDATA%\CmnCadTranslator\Updater\CMNUpdater.exe" (
  echo Install the translator first using Install.cmd.
  pause
  exit /b 1
)
"%LOCALAPPDATA%\CmnCadTranslator\Updater\CMNUpdater.exe" rollback
pause
