@echo off
rem Ogneliss - Windows build. Arguments are passed to scripts\build_windows.ps1:
rem   build_windows.bat          release build
rem   build_windows.bat -Run     debug run (hot reload)
rem   build_windows.bat -Clean   clean build
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_windows.ps1" %*
if errorlevel 1 pause
