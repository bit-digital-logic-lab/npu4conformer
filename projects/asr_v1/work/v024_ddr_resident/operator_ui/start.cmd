@echo off
setlocal
cd /d "%~dp0"
if not defined ASR_PYTHON set "ASR_PYTHON=%~dp0..\..\..\ASR\environment\envs\ASR\python.exe"
for %%I in ("%ASR_PYTHON%") do set "ASR_ENV=%%~dpI"
set "PATH=%ASR_ENV%;%ASR_ENV%\Library\bin;%ASR_ENV%\Scripts;%PATH%"
set "PYTHONUTF8=1"
"%ASR_PYTHON%" "%~dp0server.py" --open
if errorlevel 1 pause
