# Read-only ownership/DDR/idle audit. Never initializes or resets any hardware.
set root [file normalize [file join [file dirname [info script]] ..]]
set tag [lindex $argv 0]
if {![regexp {^[a-z0-9_]+$} $tag]} {error "Safe fresh tag required"}
set out [file join $root reports $tag]
if {[file exists $out]} {error "Preserve prior audit; use fresh tag"}
file mkdir $out
proc rd {a} {
 set t [string trim [mrd -force $a]]
 if {![regexp {:\s+([0-9a-fA-F]{8})$} $t -> v]} {error "Read failed $a: $t"}
 scan $v %x v;expr {$v&0xffffffff}
}
connect -url tcp:127.0.0.1:3121
try {
 set chain [jtag targets];puts $chain
 if {![string match *210512180081* $chain]} {error "Expected board cable unavailable"}
 targets -set -filter {name == "PSU"};after 500
 set cores [targets];puts $cores
 if {[regexp {Cortex-A53 #0 \(Running} $cores] || [regexp -all {Cortex-A53 #[123] \((Power On Reset|APU Reset)} $cores]!=3 || [regexp -all {RPU Reset} $cores]!=2} {error "Expected owned halted/reset cores; another application may be active"}
 set values {}
 foreach a {0xFFFE0000 0xFFFE0004 0xFFFE0010 0xFFFE0068 0xFFFE006C 0xFFFE0078 0xFFFE007C 0xFD070000 0xFD070004 0xFD1A0100 0xFD615000 0xFD380000 0xFD380014 0xFD390000 0xFD390014 0xFD3A0000 0xFD3A0014 0xFD3B0000 0xFD3B0014 0xFD380004 0xFD380018 0xFD390004 0xFD390018 0xFD3A0004 0xFD3A0018 0xFD3B0004 0xFD3B0018 0xA0000000 0xA0000004 0xA4000000 0xA4000004 0xA8000000 0xA8000004 0xA800001C} {
  set value [rd $a];dict set values $a $value;puts [format "AUTONOMY_AUDIT_RO %08X=%08X" $a $value]
 }
 if {[dict get $values 0xFFFE0000]!=0xA51A1301 || [dict get $values 0xFFFE0004]!=2 || [dict get $values 0xFFFE0010]!=0 || [dict get $values 0xFFFE0078]!=[dict get $values 0xFFFE0068] || [dict get $values 0xFFFE007C]!=[dict get $values 0xFFFE006C]} {error "Prior owned gateway/cache restoration not clean"}
 if {[dict get $values 0xFD070000]!=0x81040010 || ([dict get $values 0xFD070004]&7)!=1 || ([dict get $values 0xFD1A0100]&0x1f80)!=0} {error "DDR training/AFI reset mismatch; no reinitialization allowed"}
 foreach a {0xFD380000 0xFD380014 0xFD390000 0xFD390014 0xFD3A0000 0xFD3A0014 0xFD3B0000 0xFD3B0014} {if {([dict get $values $a]&3)!=0} {error "HP not128bit; do not reinitialize PS"}}
 if {[dict get $values 0xA0000000]!=0xA51A1001 || ([dict get $values 0xA0000004]&5)!=0 || [dict get $values 0xA4000000]!=0xA51A1310 || [dict get $values 0xA4000004]!=0} {error "Unknown or active nonmatrix/mailbox"}
 set matrix [dict get $values 0xA8000000];set copy 0
 if {$matrix!=0xA51A20C0 && $matrix!=0xA51A20A1 && $matrix!=0xA51A21C1} {error "Unknown matrix identity; do not access unmapped peripherals"}
 if {([dict get $values 0xA8000004]&5)!=0 || [dict get $values 0xA800001C]!=0} {error "Matrix busy/fault/error; preserve state"}
 if {$matrix==0xA51A21C1} {
  foreach a {0xA8000088 0xA8000090 0xA8000094 0xA8000098 0xA800009C 0xA80000A0 0xA80000A4} {set v [rd $a];dict set values $a $v;puts [format "V21_PRESERVE_RO %08X=%08X" $a $v]}
  if {[dict get $values 0xA8000088]!=0x10102131 || ([dict get $values 0xA8000090]&2)!=0} {error "V21 identity/parameter loading active"}
 } else {
  set copy [rd 0xAC000000];set copy_status [rd 0xAC000004]
  if {($matrix==0xA51A20C0&&$copy!=0xA51A2044) || ($matrix==0xA51A20A1&&$copy!=0xA51A2084) || ($copy_status&13)!=0} {error "COPY identity/busy/fault mismatch"}
 }
 if {$matrix==0xA51A20A1} {
  set j [rd 0xAE000000];set s [rd 0xAE000004]
  if {$j!=0xA51A2070 || ($s&5)!=0} {error "Autonomous supervisor busy/fault/identity mismatch"}
 }
 set f [open [file join $out receipt.txt] w]
 puts $f "AUTONOMY_BOARD_READONLY_AUDIT_PASS\nMATRIX_ID=$matrix COPY_ID=$copy\nCORES=$cores\nREGISTERS=$values\nNo PS reset/DDR init/clock/media/MIO/CSR writes."
 close $f
 puts AUTONOMY_BOARD_READONLY_AUDIT_PASS
} finally {disconnect}
exit
