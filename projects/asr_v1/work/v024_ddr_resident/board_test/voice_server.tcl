# One authorized audio session on an already running/verified 2493 DDR image.
# The core keeps the qualified seven-node plan; each START consumes new SQRT data.
source [file join [file dirname [info script]] capture_ddr.tcl]
namespace eval voice {}
proc voice::atomic {path text} {
    set ch [open "$path.tmp" {WRONLY CREAT EXCL}]
    try {puts $ch $text} finally {close $ch}
    file rename "$path.tmp" $path
}
proc voice::check_idle {} {
    foreach {addr expected} {0xa0000004 2 0xa0000014 7 0xa000001c 0 0xa00000c4 1
                             0xa1000028 0 0xa100002c 0 0xa1000030 0} {
        if {[resident_board::read32 $addr] != $expected} {error "unexpected core state at $addr"}
    }
}
proc voice::check_plan {run inputs} {
    foreach {addr expected} {0xa1000000 0xa51a2480 0xa1000004 128 0xa1000008 1
                             0xa0000000 0xa51a22d0 0xa0000090 1 0xa0000008 0x10008000 0xa000000c 1} {
        if {[resident_board::read32 $addr] != $expected} {error "resident plan incorrectly configured at $addr"}
    }
    check_idle
    resident_board::dump 0x10000000 16384 [file join $run param_live.bin]
    if {[resident_board::contents [file join $run param_live.bin]] ne
        [resident_board::contents [file join $inputs fused_param64k.bin]]} {error "resident plan/parameters changed"}
    binary scan [resident_board::contents [file join $inputs fused_pc64.bin]] i* params
    if {[llength $params] != 64} {error "invalid frozen scale/bias file"}
    for {set i 0} {$i < 64} {incr i} {
        if {[resident_board::read32 [expr {0xa1000100 + 4*$i}]] != ([lindex $params $i] & 0xffffffff)} {
            error "resident scale/bias changed at word $i"
        }
    }
}
proc voice::request {run id log} {
    set key [format %04d $id]
    set lines [split [string trim [resident_board::contents [file join $run request_$key.hex]]] \n]
    set count [llength $lines]
    if {$count < 1 || $count >= 1024} {error "request plus witness must fit 1024 lanes"}
    set words {}
    foreach line $lines {
        set line [string trim $line]
        if {![regexp {^[0-9a-fA-F]{8}$} $line]} {error "invalid SQRT input word"}
        lappend words [expr "0x$line"]
    }
    # The witness is lane count, outside the model's data. Select 1 or 4 so
    # its FP32 square root is observably different from that lane before START.
    set before [resident_board::read32 [expr {0x04006800 + 4*$count}]]
    set near_one [expr {$before >= 0x3f7fff00 && $before <= 0x3f800100}]
    set target [expr {$near_one ? 0x40000000 : 0x3f800000}]
    lappend words [expr {$near_one ? 0x40800000 : 0x3f800000}]
    set inpath [file join $run input_$key.bin]
    set ch [open $inpath wb]
    try {puts -nonewline $ch [binary format i* $words]} finally {close $ch}
    resident_board::load 0x04002000 [expr {$count+1}] $inpath
    mwr -force 0xa0000010 1
    set deadline [expr {[clock milliseconds]+60000}]
    while {([resident_board::read32 0xa0000004] & 6) == 0} {
        if {[clock milliseconds] >= $deadline} {error "timed out waiting for $key"}
        after 1
    }
    check_idle
    set cycles [expr {[resident_board::read32 0xa0000020] | ([resident_board::read32 0xa0000024] << 32)}]
    if {$cycles <= 0} {error "empty graph cycle count"}
    set outpath [file join $run output_$key.bin]
    resident_board::dump 0x04006800 [expr {$count+1}] $outpath
    binary scan [resident_board::contents $outpath] i* raw
    set witness [expr {[lindex $raw end] & 0xffffffff}]
    binary scan [binary format i $witness] r observed
    set goal [expr {$near_one ? 2.0 : 1.0}]
    if {$witness == $before || !($observed > 0 && abs($observed - $goal) <= 0.000006*$goal)} {
        error "output does not carry this START's SQRT witness: $key"
    }
    set hex {}
    foreach val [lrange $raw 0 end-1] {lappend hex [format %08x [expr {$val & 0xffffffff}]]}
    puts $log "$id\t$count\t$cycles\t[format %08x $before]\t[format %08x $target]\t[format %08x $witness]"
    flush $log
    atomic [file join $run response_$key.hex] [join $hex \n]
}
proc voice::serve {run inputs} {
    resident_board::select_psu
    if {([resident_board::read32 0xfd070004] & 15) != 1 ||
        ([resident_board::read32 0xff5e00c0] & 0x013f3f07) != 0x01011602} {error "DDR/PL clock is not initialized"}
    check_plan $run $inputs
    set log [open [file join $run telemetry.tsv] {WRONLY CREAT EXCL}]
    try {
        puts $log "id\twords\tcycles\twitness_before\twitness_target\twitness_after"
        flush $log
        atomic [file join $run READY] 1
        for {set id 1} {1} {incr id} {
            set req [file join $run request_[format %04d $id].hex]
            set deadline [expr {[clock milliseconds]+240000}]
            while {![file exists $req]} {
                if {[file isfile [file join $run STOP]]} {return}
                if {[clock milliseconds] >= $deadline} {error "no SQRT request within 240 seconds"}
                after 2
            }
            request $run $id $log
        }
    } finally {close $log}
}
if {[info exists argv0] && [file normalize $argv0] eq [file normalize [info script]] || [llength $argv] && [lindex $argv 0] eq "--live-sqrt"} {
    if {$argc != 3 || [lindex $argv 0] ne "--live-sqrt"} {error "requires --live-sqrt ACTIVE_RUN INPUTS_DIR"}
    lassign $argv opt run inputs
    set rc [catch {
        connect -url tcp:127.0.0.1:3121
        voice::serve $run $inputs
    } msg options]
    if {$rc} {voice::atomic [file join $run FAILED] [dict get $options -errorinfo]; puts stderr $msg}
    catch {disconnect}
    exit $rc
}
