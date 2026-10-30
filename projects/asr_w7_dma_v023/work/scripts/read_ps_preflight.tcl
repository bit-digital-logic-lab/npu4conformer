# Read-only warm PS/DDR/gateway ownership inspection. No halt/reset/write/init.
proc rd {a} {set t [string trim [mrd -force $a]];if {![regexp {:\s+([0-9a-fA-F]{8})$} $t -> v]} {error "Read failed $a"};scan $v %x v;expr {$v&0xffffffff}}
connect -url tcp:127.0.0.1:3121
try {
 if {![string match *210512180081* [jtag targets]]} {error "Wrong cable"}
 targets -set -filter {name == "PSU"};puts [targets]
 foreach a {0xFF5E0200 0xFD070000 0xFD070004 0xFF260020 0xFF5E0238 0xFD1A0100 0xFFFE0000 0xFFFE0004 0xFFFE0010 0xFFFE0068 0xFFFE006C 0xFFFE0078 0xFFFE007C 0xA0000000 0xA0000004 0xA4000000 0xA4000004 0xA8000000 0xA8000004 0xA800001C 0xA8000088 0xA8000090 0xFD615000 0xFD380000 0xFD380014 0xFD380004 0xFD380018} {puts [format "V022_PREFLIGHT %08X=%08X" $a [rd $a]]}
 puts V022_PS_READONLY_PREFLIGHT_DONE
} finally {disconnect}
exit
