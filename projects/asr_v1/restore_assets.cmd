@echo off
setlocal
if defined ASR_PYTHON goto run
set "ASR_PYTHON=%~dp0ASR\environment\envs\ASR\python.exe"
if exist "%ASR_PYTHON%" goto run
py -3 "%~dp0tools\restore_assets.py"
if errorlevel 1 pause
exit /b
:run
"%ASR_PYTHON%" "%~dp0tools\restore_assets.py"
if errorlevel 1 pause
