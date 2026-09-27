# 中文说明：在工程内创建独立 Python 环境，不修改系统环境。
param([string]$Python = 'python')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not (Test-Path '.venv\Scripts\python.exe')) {
        & $Python -m venv .venv
        if ($LASTEXITCODE -ne 0) {throw 'Cannot create Python virtual environment'}
    }
    & .\.venv\Scripts\python.exe -m pip install --index-url https://download.pytorch.org/whl/cpu torch==2.14.0
    if ($LASTEXITCODE -ne 0) {throw 'Cannot install CPU PyTorch'}
    & .\.venv\Scripts\python.exe -m pip install pyserial==3.5 numpy==2.5.2
    if ($LASTEXITCODE -ne 0) {throw 'Cannot install pyserial'}
} finally {Pop-Location}
