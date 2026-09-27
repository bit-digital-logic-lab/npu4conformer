$ErrorActionPreference='Stop'
$simRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$v4Root = Split-Path -Parent $simRoot
$vendorRoot = Join-Path $v4Root 'vendor/verilog-ethernet/rtl'
$imagePath = Join-Path $simRoot 'tb_arp_direct_link.vvp'
$sources = @((Join-Path $simRoot 'tb_arp_direct_link.sv'))
foreach ($moduleName in @('arp','arp_cache','arp_eth_rx','arp_eth_tx','lfsr')) {
    $sources += Join-Path $vendorRoot ($moduleName+'.v')
}
& 'D:/app/iverilog/iverilog/bin/iverilog.exe' -g2012 -s tb_arp_direct_link -o $imagePath @sources
if ($LASTEXITCODE -ne 0) { throw 'ARP simulation compilation failed' }
$simulationOutput = & 'D:/app/iverilog/iverilog/bin/vvp.exe' $imagePath 2>&1
$simulationExitCode = $LASTEXITCODE
$simulationOutput | Write-Output
if ($simulationExitCode -ne 0 -or -not ($simulationOutput -match 'PASS tb_arp_direct_link')) {
    throw 'ARP direct-link simulation failed'
}
