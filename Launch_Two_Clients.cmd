@echo off
setlocal
set "CARDLINK_GODOT=%USERPROFILE%\Desktop\Godot_v4.7.2-stable_win64.exe"
if not exist "%CARDLINK_GODOT%" (
  echo Godot was not found at %CARDLINK_GODOT%
  echo Edit CARDLINK_GODOT in this launcher to point to your Godot executable.
  pause
  exit /b 1
)
start "CardLink client 1" "%CARDLINK_GODOT%" --path "%~dp0."
start "CardLink client 2" "%CARDLINK_GODOT%" --path "%~dp0."
