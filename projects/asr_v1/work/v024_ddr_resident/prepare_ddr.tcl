# Initialize only the PS using this synthesized platform's own generated setup.
# APU remains reset. No boot media or FPGA image is programmed by this script.
set root [file normalize [file dirname [info script]]]
set init [file join $root physical_native shell_run project resident.gen sources_1 bd ps_ddr ip ps_ddr_ps_0 psu_init.tcl]
if {$argc != 1 || ![file isfile $init]} {error "expected output directory and generated PS setup"}
set out [file normalize [lindex $argv 0]]
if {![file isdirectory $out]} {error "caller must create a fresh output directory"}
connect -url tcp:127.0.0.1:3121
try {
    set devices [jtag targets]
    puts $devices
    if {![string match *210512180081* $devices]} {error "designated cable absent"}
    set processors [targets -target-properties -filter {name == "Cortex-A53 #0" && jtag_cable_serial == "210512180081"}]
    if {[llength $processors] != 1} {error "designated A53 target absent or ambiguous"}
    set processor [lindex $processors 0]
    targets -set [dict get $processor target_id]
    puts "A53_TARGET=$processor"
    if {![regexp -nocase {reset} $processor]} {error "APU must be reset before initializing unused DDR"}
    set psus [targets -target-properties -filter {name == "PSU" && jtag_cable_serial == "210512180081"}]
    if {[llength $psus] != 1} {error "designated PSU target absent or ambiguous"}
    targets -set [dict get [lindex $psus 0] target_id]
    source $init
    psu_init
    set stat [mrd -force -value 0xfd070004]
    puts "DDRC_STAT=$stat"
    if {($stat & 7) != 1} {error "DDR controller did not enter normal operation"}
    set log [open [file join $out ddr_readback.tsv] w]
    puts $log "address\twritten\tread"
    set tested 0
    foreach base {0x07000000 0x07010000 0x17ff0000} {
        foreach seed {0x5a5aa5a5 0xa5a55a5a 0x00000000} {
            set words {}
            for {set i 0} {$i < 64} {incr i} {
                lappend words [format 0x%08x [expr {($seed ^ ($seed ? $base+4*$i : 0)) & 0xffffffff}]]
            }
            mwr -force $base $words
            set result [mrd -force -value $base 64]
            if {[llength $result] != 64} {error "DDR read count"}
            for {set i 0} {$i < 64} {incr i} {
                set actual [expr {[lindex $result $i] & 0xffffffff}]
                set expected [lindex $words $i]
                puts $log "[format %08x [expr {$base+4*$i}]]\t[format %08x $expected]\t[format %08x $actual]"
                if {$actual != $expected} {error "DDR mismatch at $base index $i"}
                incr tested
            }
            flush $log
        }
    }
    close $log
    puts "PS_DDR_INITIALIZATION_PASS TESTED_WORDS=$tested APU_RESET=1 NO_NEW_BITSTREAM"
} finally {
    disconnect
}
exit
