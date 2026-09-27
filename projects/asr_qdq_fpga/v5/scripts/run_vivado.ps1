param([ValidateSet('build','program')][string]$Mode='build',
      [ValidatePattern('^[A-Za-z0-9_]+$')][string]$RunName='board_001')
$ErrorActionPreference='Stop'
$v4Root=Split-Path -Parent $PSScriptRoot
$v4LogDir=Join-Path $v4Root ('build\'+$RunName+'_'+$Mode+'_logs')
New-Item -ItemType Directory -Force -Path $v4LogDir | Out-Null
$v4OldRepo=$env:XILINX_TCLAPP_REPO
$v4OldData=$env:XILINX_LOCAL_USER_DATA
try {
    $env:XILINX_TCLAPP_REPO='D:/fpga/new2025/vitis/2025.2/Vivado/data/XilinxTclStore'
    $env:XILINX_LOCAL_USER_DATA='NO'
    Push-Location -LiteralPath $v4LogDir
    try {
        $v4Script=if($Mode -eq 'build'){'build_board.tcl'}else{'program_board.tcl'}
        & 'D:\fpga\new2025\vitis\2025.2\Vivado\bin\vivado.bat' -mode batch -source (Join-Path $PSScriptRoot $v4Script) -tclargs $RunName
        if($LASTEXITCODE -ne 0){throw "Vivado $Mode failed"}
    } finally {Pop-Location}
} finally {
    $env:XILINX_TCLAPP_REPO=$v4OldRepo
    $env:XILINX_LOCAL_USER_DATA=$v4OldData
}
