param(
    [ValidateSet('synth','create_project','board_build','program_board','probe_hardware')][string]$Mode = 'synth',
    [string]$Vivado = 'D:\fpga\new2025\vitis\2025.2\Vivado\bin\vivado.bat'
)
$ErrorActionPreference = 'Stop'
$asrRoot = Split-Path -Parent $PSScriptRoot
$asrToolRoot = Split-Path -Parent (Split-Path -Parent $Vivado)
$asrRepo = Join-Path $asrToolRoot 'data\XilinxTclStore'
if (!(Test-Path -LiteralPath $Vivado)) { throw "Vivado not found: $Vivado" }
if (!(Test-Path -LiteralPath $asrRepo)) { throw "Bundled Tcl repository not found: $asrRepo" }
$asrOut = Join-Path $asrRoot "build\$Mode"
New-Item -ItemType Directory -Force -Path $asrOut | Out-Null
$asrPreviousRepo = $env:XILINX_TCLAPP_REPO
$asrPreviousUserData = $env:XILINX_LOCAL_USER_DATA
try {
    # Official Tcl Store process-level controls. Work around the sandbox's
    # user-cache path lookup without altering installation files or global settings.
    $env:XILINX_TCLAPP_REPO = $asrRepo.Replace('\','/')
    $env:XILINX_LOCAL_USER_DATA = 'NO'
    Push-Location -LiteralPath $asrOut
    try {
        & $Vivado -mode batch -source (Join-Path $PSScriptRoot "$Mode.tcl") `
            -log (Join-Path $asrOut 'vivado.log') -journal (Join-Path $asrOut 'vivado.jou')
        if ($LASTEXITCODE -ne 0) { throw "Vivado failed with exit code $LASTEXITCODE; see $asrOut\vivado.log" }
    } finally { Pop-Location }
} finally {
    $env:XILINX_TCLAPP_REPO = $asrPreviousRepo
    $env:XILINX_LOCAL_USER_DATA = $asrPreviousUserData
}
