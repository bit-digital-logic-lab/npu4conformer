param([ValidatePattern('^[A-Za-z0-9_]+$')][string]$RunName='board_004_arpfix')
$ErrorActionPreference='Stop'
$regRoot=Split-Path -Parent $PSScriptRoot
$regFrozen=Join-Path (Split-Path -Parent $regRoot) 'releases\v2_20260922_pre_golden'
$regOutput=Join-Path $regRoot ('build\'+$RunName+'\core_regression')
New-Item -ItemType Directory -Force -Path $regOutput | Out-Null
$regCompiler='D:\app\iverilog\iverilog\bin\iverilog.exe'
$regRuntime='D:\app\iverilog\iverilog\bin\vvp.exe'
$regCases=@(
    @{Top='tb_udp_command_bridge'; Sources=@(
        (Join-Path $regRoot 'sim\tb_udp_command_bridge.sv'),
        (Join-Path $regRoot 'rtl\asr_udp_command_bridge.sv'),
        (Join-Path $regFrozen 'v2\rtl\asr_command_engine_v2.sv'),
        (Join-Path $regFrozen 'rtl\asr_i16_mac.sv'),
        (Join-Path $regFrozen 'rtl\asr_requant.sv'),
        (Join-Path $regFrozen 'rtl\asr_fp32_alu.sv'))},
    @{Top='tb_udp_rx_guard'; Sources=@(
        (Join-Path $regRoot 'sim\tb_udp_rx_guard.sv'),
        (Join-Path $regRoot 'rtl\asr_udp_rx_guard.sv'))},
    @{Top='tb_ksz9031_init'; Sources=@(
        (Join-Path $regRoot 'sim\tb_ksz9031_init.sv'),
        (Join-Path $regRoot 'rtl\asr_ksz9031_init.sv'))}
)
foreach($regCase in $regCases){
    $regImage=Join-Path $regOutput ($regCase.Top+'.vvp')
    & $regCompiler -g2012 -s $regCase.Top -o $regImage @($regCase.Sources)
    if($LASTEXITCODE -ne 0){throw "Compilation failed: $($regCase.Top)"}
    $regLog=& $regRuntime $regImage 2>&1
    $regExit=$LASTEXITCODE
    $regLog | Tee-Object -FilePath (Join-Path $regOutput ($regCase.Top+'.log'))
    if($regExit -ne 0 -or -not ($regLog -match 'PASS')){throw "Simulation failed: $($regCase.Top)"}
}
Write-Output 'V4_CORE_REGRESSION_PASS_NO_HARDWARE'
