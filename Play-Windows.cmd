@echo off
title Jianghu Weiyuan Martial - Game Launcher
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\serve_web_windows.ps1"
if errorlevel 1 pause
