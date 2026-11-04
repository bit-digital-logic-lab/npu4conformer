# Read only. Run after a completed encode command on encoder_profile.elf.
if {$argc!=1} {error "usage: RUN_DIRECTORY"}
set run [file normalize [lindex $argv 0]]
set target [file join $run profile.raw]
if {![file isfile [file join $run mailbox.bin]] || [file exists $target]} {error "requires completed run and fresh sideband path"}
source [file join [file dirname [info script]] .. .. board_test capture_ddr.tcl]
connect -url tcp:127.0.0.1:3121
set failed [catch {
    resident_board::select_psu
    if {[resident_board::read32 0x08000040]!=0x50465231 || [resident_board::read32 0x08000018]!=2 ||
        [resident_board::read32 0x08000008]!=3 || [resident_board::read32 0x08000014]!=[resident_board::read32 0x08000048]} {
        error "no completed, sequence-bound profile available"
    }
    resident_board::dump 0x08000040 34 $target
} msg opts]
catch {disconnect}
if {$failed} {puts stderr [dict get $opts -errorinfo]; exit 1}
exit
