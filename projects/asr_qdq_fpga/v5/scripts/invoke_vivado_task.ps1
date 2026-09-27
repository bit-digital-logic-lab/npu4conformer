param([Parameter(Mandatory=$true)][string]$Script)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
$oldRepo=$env:XILINX_TCLAPP_REPO
$oldData=$env:XILINX_LOCAL_USER_DATA
try {
    $env:XILINX_TCLAPP_REPO='D:/fpga/new2025/vitis/2025.2/Vivado/data/XilinxTclStore'
    $env:XILINX_LOCAL_USER_DATA='NO'
    Push-Location -LiteralPath $taskRoot
    try {
        & 'D:\fpga\new2025\vitis\2025.2\Vivado\bin\vivado.bat' -mode batch -nolog -nojournal -source (Join-Path $PSScriptRoot $Script)
        if($LASTEXITCODE -ne 0){throw 'Vivado task failed'}
    } finally { Pop-Location }
} finally {
    $env:XILINX_TCLAPP_REPO=$oldRepo
    $env:XILINX_LOCAL_USER_DATA=$oldData
}
