@echo off
setlocal
cd /d "%~dp0"
set "ASR_ENV=%~dp0..\..\..\ASR\environment\envs\ASR"
set "PATH=%ASR_ENV%;%ASR_ENV%\Library\bin;%ASR_ENV%\Scripts;%PATH%"
set "PYTHONUTF8=1"
"%ASR_ENV%\python.exe" "%~dp0server.py" --open
if errorlevel 1 pause
