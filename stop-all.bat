@echo off
rem aki_sys stop all services (ASCII launcher -> PowerShell script)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop-all.ps1"
