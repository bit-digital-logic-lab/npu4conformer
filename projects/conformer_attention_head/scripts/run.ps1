# 中文说明：完整 head 的 HLS/Vivado 构建与下载入口。
param(
 [ValidateSet('Create','Build','Hls','Cosim','Program','Open')][string]$Action='Build',
 [string]$Vivado='C:\Academic_Application\Vivado\2025.2\Vivado\bin\vivado.bat',
 [string]$VitisHls='C:\Academic_Application\Vivado\2025.2\Vitis\bin\vitis-run.bat'
)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
 switch($Action) {
  'Hls' {& $VitisHls --mode hls --tcl scripts\hls.tcl}
  'Cosim' {& $VitisHls --mode hls --tcl scripts\cosim.tcl}
  'Open' {& $Vivado -mode gui build\vivado\modelA_conformer_head_full_fpga.xpr}
  default {
   $scriptName=@{Create='create_project';Build='build';Program='program'}[$Action]
   & $Vivado -mode batch -nojournal -log "artifacts\run_$scriptName.log" -source "scripts\$scriptName.tcl"
  }
 }
 if($LASTEXITCODE -ne 0){throw "$Action failed: $LASTEXITCODE"}
} finally {Pop-Location}
