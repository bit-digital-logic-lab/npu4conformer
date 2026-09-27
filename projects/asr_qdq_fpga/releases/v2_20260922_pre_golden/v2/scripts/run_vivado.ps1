param(
    [ValidateSet('board_build','program_board')][string]$Mode = 'board_build',
    [ValidateSet(115200,460800,921600)][int]$Baud = 921600,
    [string]$Vivado = 'D:\fpga\new2025\vitis\2025.2\Vivado\bin\vivado.bat'
)
$ErrorActionPreference = 'Stop'
$asrV2Root = Split-Path -Parent $PSScriptRoot
$asrV2ToolRoot = Split-Path -Parent (Split-Path -Parent $Vivado)
$asrV2Repo = Join-Path $asrV2ToolRoot 'data\XilinxTclStore'
$asrV2Out = Join-Path $asrV2Root "build\${Mode}_${Baud}"
New-Item -ItemType Directory -Force -Path $asrV2Out | Out-Null
$asrV2PreviousRepo = $env:XILINX_TCLAPP_REPO
$asrV2PreviousData = $env:XILINX_LOCAL_USER_DATA
try {
    $env:XILINX_TCLAPP_REPO = $asrV2Repo.Replace('\','/')
    $env:XILINX_LOCAL_USER_DATA = 'NO'
    Push-Location -LiteralPath $asrV2Out
    try {
        & $Vivado -mode batch -source (Join-Path $PSScriptRoot "$Mode.tcl") `
            -log (Join-Path $asrV2Out 'vivado.log') -journal (Join-Path $asrV2Out 'vivado.jou') -tclargs $Baud
        if ($LASTEXITCODE -ne 0) { throw "Vivado failed; see $asrV2Out\vivado.log" }
    } finally { Pop-Location }
} finally {
    $env:XILINX_TCLAPP_REPO = $asrV2PreviousRepo
    $env:XILINX_LOCAL_USER_DATA = $asrV2PreviousData
}
