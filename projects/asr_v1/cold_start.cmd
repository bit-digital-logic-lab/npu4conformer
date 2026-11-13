@echo off
setlocal
if not defined ASR_PYTHON set "ASR_PYTHON=%~dp0ASR\environment\envs\ASR\python.exe"
set "PYTHONUTF8=1"
"%ASR_PYTHON%" "%~dp0work\v024_ddr_resident\cold_start.py"
pause
