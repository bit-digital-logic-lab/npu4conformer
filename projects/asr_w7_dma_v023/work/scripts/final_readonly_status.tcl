# Enumerated readable CSRs only. Never bulk-read holes or write-only START.
proc rd {a} {set t [string trim [mrd -force $a]];if {![regexp {:\s+([0-9a-fA-F]{8})$} $t -> v]} {error "Read failed $a"};scan $v %x v;expr {$v&0xffffffff}}
connect -url tcp:127.0.0.1:3121
try {
 if {![string match *210512180081* [jtag targets]]} {error "Wrong cable"}
 targets -set -filter {name == "PSU"};set cores [targets];puts $cores
 if {[regexp {Cortex-A53 #0 \(Running} $cores]} {error "CPU not halted; preserve state"}
 set values {}
 foreach a {0xFFFE0000 0xFFFE0004 0xFFFE0010 0xFFFE0068 0xFFFE006C 0xFFFE0078 0xFFFE007C 0xFD070000 0xFD070004 0xFF260020 0xA0000000 0xA0000004 0xA4000000 0xA4000004 0xA8000000 0xA8000004 0xA800001C 0xA8000028 0xA8000088 0xA8000090 0xA8000094 0xA8000098 0xA800009C 0xA80000A0 0xA80000A4 0xA9000000 0xA9000004 0xA9000014 0xA9000018 0xA900001C 0xA9000078 0xA900007C 0xA9000090 0xA9000094 0xA9000098 0xA900009C} {
  set v [rd $a];dict set values $a $v;puts [format "V022_FINAL_RO %08X=%08X" $a $v]
 }
 if {[dict get $values 0xFFFE0000]!=0xA51A1301||[dict get $values 0xFFFE0004]!=2||[dict get $values 0xFFFE0010]!=0||[dict get $values 0xFFFE0068]!=[dict get $values 0xFFFE0078]||[dict get $values 0xFFFE006C]!=[dict get $values 0xFFFE007C]||[dict get $values 0xFD070000]!=0x81040010||([dict get $values 0xFD070004]&7)!=1||[dict get $values 0xFF260020]!=33333000} {error "Gateway/cache/warmDDR/timer mismatch"}
 if {[dict get $values 0xA0000000]!=0xA51A1001||([dict get $values 0xA0000004]&5)!=0||[dict get $values 0xA4000004]!=0||[dict get $values 0xA8000000]!=0xA51A21C1||([dict get $values 0xA8000004]&5)!=0||[dict get $values 0xA800001C]!=0||[dict get $values 0xA9000000]!=0xA51A22D0||([dict get $values 0xA9000004]&5)!=0||[dict get $values 0xA900001C]!=0} {error "V022 identities/drain/fault mismatch"}
 if {[dict get $values 0xA8000090]!=1||[dict get $values 0xA9000090]!=1||[dict get $values 0xA80000A4]!=[dict get $values 0xA9000094]} {error "Parameter READY/generation mismatch"}
 puts V022_FINAL_READONLY_STOPPED_DRAINED_CACHE_READY_PASS
} finally {disconnect}
exit
