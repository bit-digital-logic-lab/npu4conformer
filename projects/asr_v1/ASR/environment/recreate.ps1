# 在新位置创建 ASR 环境；不删除或覆盖现有环境。
$ErrorActionPreference = 'Stop'
$AsrRoot = Split-Path -Parent $PSScriptRoot
$AsrPrefix = Join-Path $PSScriptRoot 'envs\ASR'
if (Test-Path -LiteralPath $AsrPrefix) { throw '环境目录已存在；正常运行不需要重建。' }
$AsrCondaCommand = Get-Command conda.exe -ErrorAction Stop
& $AsrCondaCommand.Source create --prefix $AsrPrefix --file (Join-Path $PSScriptRoot 'ASR-conda-explicit.txt') --yes
if ($LASTEXITCODE -ne 0) { throw 'Conda 创建失败。' }
$AsrPython = Join-Path $AsrPrefix 'python.exe'
& $AsrPython -m pip install --extra-index-url https://download.pytorch.org/whl/cu128 -r (Join-Path $PSScriptRoot 'requirements-ASR-lock.txt')
if ($LASTEXITCODE -ne 0) { throw '依赖安装失败。' }
& $AsrPython -m pip install --no-deps --no-build-isolation -e (Join-Path $AsrRoot 'third_party\espnet')
if ($LASTEXITCODE -ne 0) { throw '本地 ESPnet 安装失败。' }
& $AsrPython -m pip check
if ($LASTEXITCODE -ne 0) { throw '依赖校验失败。' }
Write-Host "环境已创建：$AsrPrefix"
Write-Host '请在 PyCharm 中选择该目录中的 python.exe。'
