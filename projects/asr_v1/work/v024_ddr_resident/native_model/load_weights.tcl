# Cold-load the fixed encoder image into the already initialized board DDR.
if {$argc != 2} {error "usage: weights.bin NEW_OUTPUT"}
set image [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
if {[file exists $out] || ![file isfile $image] || [file size $image] != 84994048} {error "unexpected image or existing result"}
file mkdir $out
source [file join [file dirname [info script]] .. board_test capture_ddr.tcl]
connect -url tcp:127.0.0.1:3121
set failed [catch {
    resident_board::select_psu
    if {[resident_board::read32 0x08000000] != 0x50533234 ||
        [resident_board::read32 0x08000008] ni {1 3} ||
        [resident_board::read32 0x08000010] != [resident_board::read32 0x08000014]} {
        error "native runtime is absent or active"
    }
    set begin [clock milliseconds]
    puts "WEIGHTS_UPLOAD_BEGIN BYTES=[file size $image]"
    flush stdout
    resident_board::load 0x10100000 [expr {[file size $image]/4}] $image
    puts "WEIGHTS_UPLOAD_COMPLETE MS=[expr {[clock milliseconds]-$begin}]"
    flush stdout
    resident_board::dump 0x10100000 [expr {[file size $image]/4}] [file join $out weights_readback.bin]
    puts "WEIGHTS_RAW_READBACK_COMPLETE MS=[expr {[clock milliseconds]-$begin}]"
} message opts]
catch {disconnect}
if {$failed} {puts stderr [dict get $opts -errorinfo];exit 1}
exit
