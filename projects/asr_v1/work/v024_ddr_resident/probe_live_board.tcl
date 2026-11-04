# Read-only inventory before selecting the physical experiment route.
connect -url tcp:127.0.0.1:3121
try {
    set cable [jtag targets]
    puts $cable
    if {![string match *210512180081* $cable]} {error "designated Digilent cable not present"}
    puts [targets]
    targets -set -filter {name == "PSU"}
    if {![catch {mrd -force -value 0xfd070004} status]} {puts "DDRC_STAT=$status"}
    targets -set -filter {name == "Cortex-A53 #0"}
    if {![catch {rrd pc} pc]} {puts "A53_PC=$pc"}
} finally {disconnect}
exit
