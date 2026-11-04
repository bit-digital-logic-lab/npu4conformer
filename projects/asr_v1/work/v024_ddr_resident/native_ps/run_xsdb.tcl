# XSDB run_xsdb.tcl boot|selftest|pltest|encode OUT_NEW [ELF_OR_F32_INPUT]
if {$argc < 2 || $argc > 3} {error "MODE NEW_DIR [ELF or raw F32 logmel]"}
lassign $argv mode output arg
if {$mode ni {boot selftest pltest encode} || [file exists $output]} {error "invalid mode or existing run"}
if {($mode in {boot encode}) != ($argc == 3)} {error "boot/encode require a file; selftest/pltest do not"}
set here [file normalize [file dirname [info script]]]
source [file join $here .. board_test capture_ddr.tcl]
set output [file normalize $output]; file mkdir $output
set base 0x08000000
proc w {off value} {mwr -force -size w [expr {$::base+$off}] $value}
proc r {off} {return [resident_board::read32 [expr {$::base+$off}]]}
proc receipt {path} {
    resident_board::dump $::base 16 [file join $path mailbox.bin]
    set f [open [file join $path mailbox.tsv] w]
    try {
        foreach key {magic abi state capabilities request_seq response_seq command feature_frames result encoder_frames pl_calls stage ticks_lo ticks_hi timer_hz selftest_mask} \
                val [mrd -force -size w -value $::base 16] {puts $f "$key\t[expr {$val & 0xffffffff}]"}
    } finally {close $f}
}
connect -url tcp:127.0.0.1:3121
set rc [catch {
    resident_board::select_psu
    if {([resident_board::read32 0xfd070004] & 15) != 1} {error "DDR controller not ready"}
    if {$mode eq "boot"} {
        set arg [file normalize $arg]
        set targets [targets -target-properties -filter {name =~ "Cortex-A53 #*" && jtag_cable_serial == "210512180081"}]
        if {[llength $targets] != 4} {error "expected four A53 processors"}
        foreach target $targets {
            if {[dict get $target state_reason] ne "APU Reset"} {error "A53 already released; existing firmware preserved"}
        }
        if {[resident_board::read32 0xff260020] != 33333000 || ([resident_board::read32 0xff260000] & 1)!=1} {error "system counter not running at expected configuration"}
        resident_board::dump 0xfffc0000 16384 [file join $output ocm_before.bin]
        resident_board::dump 0x0f000000 32768 [file join $output code_before.bin]
        resident_board::dump $base 16 [file join $output mailbox_before.bin]
        w 0 0
        targets -set -filter {name == "Cortex-A53 #0" && jtag_cable_serial == "210512180081"}
        rst -processor
        dow $arg
        verify $arg
        con
        resident_board::select_psu
        set deadline [expr {[clock milliseconds]+15000}]
        while {[r 0]!=0x50533234 && [clock milliseconds]<$deadline} {after 20}
        receipt $output
        if {[r 0]!=0x50533234 || [r 4]!=1 || [r 8]!=1} {error "A53 firmware did not reach READY"}
        puts "NATIVE_BOOT_PASS ABI=[r 4] CAPABILITIES=[r 12]"
    } else {
        if {[r 0]!=0x50533234 || [r 4]!=1 || [r 8] ni {1 3 4} || [r 16]!=[r 20]} {error "A53 mailbox unavailable or busy"}
        set capability [r 12]
        if {$mode eq "selftest"} {set cmd 1; set frames 0}
        if {$mode eq "pltest"} {if {!($capability & 4)} {error "ELF lacks PL selftest"}; set cmd 3; set frames 0}
        if {$mode eq "encode"} {
            if {!($capability & 2)} {error "ELF lacks encoder"}
            set arg [file normalize $arg]; set bytes [file size $arg]; set frames [expr {$bytes/320}]
            if {$frames<7 || $frames>1876 || $bytes!=$frames*320} {error "expected contiguous float32 [frames,80]"}
            resident_board::load 0x08010000 [expr {$bytes/4}] $arg
            set cmd 2
        }
        set seq [expr {([r 20]+1) & 0xffffffff}]
        w 24 $cmd; w 28 $frames; w 16 $seq
        set deadline [expr {[clock milliseconds]+($cmd==2 ? 3600000 : 60000)}]
        set last_stage -1
        while {[r 20]!=$seq && [clock milliseconds] < $deadline} {
            set progress [r 44]
            if {$last_stage!=$progress} {puts "NATIVE_STAGE=$progress"; set last_stage $progress}
            after [expr {$cmd==2?100:10}]
        }
        receipt $output
        if {[r 20]!=$seq || [r 8]!=3 || [r 32]!=0} {error "native command incomplete or failed; state=[r 8] result=[r 32] stage=[r 44]"}
        if {$mode eq "selftest" && [r 60]!=31} {error "one or more real A53 kernel checks failed"}
        if {$mode eq "pltest"} {resident_board::dump 0x07c40000 [expr {35*129}] [file join $output matrix_output.bin]}
        if {$mode eq "encode"} {
            if {[r 36] != (($frames-1)/2-1)/2 || [r 40]<1} {error "incorrect encoder shape or no PL calls"}
            resident_board::dump 0x08100000 [expr {[r 36]*512}] [file join $output encoder_output_f32.bin]
        }
        puts "NATIVE_COMMAND_PASS mode=$mode seq=$seq pl_calls=[r 40] ticks_low=[r 48]"
    }
} err opts]
catch {disconnect}
if {$rc} {puts stderr [dict get $opts -errorinfo]; exit 1}
exit
