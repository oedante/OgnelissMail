@echo off
rem Ogneliss - Android build. Arguments are passed to scripts\build_android.ps1:
rem   build_android.bat               App Bundle and APK (release)
rem   build_android.bat -Target apk   APK only (aab - App Bundle only)
rem   build_android.bat -Run          run on a phone or emulator
rem   build_android.bat -Clean        clean build
rem   build_android.bat -KeepLock     keep package versions from pubspec.lock
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_android.ps1" %*
if errorlevel 1 pause
