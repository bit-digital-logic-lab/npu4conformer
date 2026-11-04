# Persistent PSU/DAP session for an already running 2493 A53 encoder.
source [file join [file dirname [info script]] .. board_test capture_ddr.tcl]
namespace eval enc { variable mb 0x08000000 }
proc enc::r {offset} {variable mb; resident_board::read32 [expr {$mb+$offset}]}
proc enc::w {offset value} {variable mb; mwr -force -size w [expr {$mb+$offset}] $value}
proc enc::readtext {p} {
    set f [open $p r]; fconfigure $f -encoding utf-8
    try {return [string trimright [read $f] "\r\n"]} finally {close $f}
}
proc enc::publish {path value} {
    set f [open $path.part w]; fconfigure $f -encoding utf-8
    try {puts $f $value} finally {close $f}
    file rename -force $path.part $path
}
proc enc::alive {control} {
    expr {![file exists [file join $control STOP]] && [file isfile [file join $control lease]]
          && [clock seconds]-[file mtime [file join $control lease]] < 45}
}
proc enc::idle {} {
    set last [r 20]
    if {[r 0]!=0x50533234 || [r 4]!=1 || ([r 12]&7)!=7 ||
        [r 8] ni {1 3 4} || [r 16]!=$last} {error "A53 encoder unavailable or processing another request"}
    return $last
}
proc enc::start {control} {
    resident_board::select_psu
    if {([resident_board::read32 0xfd070004]&15)!=1 ||
        ([resident_board::read32 0xff5e00c0]&0x013f3f07)!=0x01011602} {error "DDR or PL0 clock unavailable"}
    set previous [idle]
    if {$previous==0} {error "missing qualified A53 firmware session"}
    set n 0
    foreach {addr expected} [readtext [file join $control fingerprints]] {
        if {[resident_board::read32 $addr] != $expected} {error "resident weight fingerprint mismatch at $addr"}
        incr n
    }
    if {$n!=6} {error "incomplete resident weight fingerprint"}
    publish [file join $control READY] "[pid] $previous"
}
proc enc::run {control dir} {
    set raw [file join $dir input_f32.bin]; set bytes [file size $raw]
    set frames [expr {$bytes/320}]
    if {$frames<7 || $frames>1876 || $frames*320!=$bytes ||
        [file exists [file join $dir mailbox.bin]]} {error "invalid feature file or reused directory"}
    set seq [expr {([idle]+1)&0xffffffff}]
    set start [clock milliseconds]
    resident_board::load 0x08010000 [expr {$bytes/4}] $raw
    w 24 2; w 28 $frames; w 16 $seq
    set deadline [expr {$start+3600000}]
    set stage -1; set next_progress 0
    while {[r 20]!=$seq} {
        set now [clock milliseconds]
        if {![alive $control]} {error "host lease ended while A53 was working"}
        if {$now >= $deadline} {error "A53 encoder request timed out"}
        if {$now >= $next_progress} {
            set s [r 44]
            if {$stage != $s && ![catch {publish [file join $dir STAGE] $s}]} {set stage $s}
            set next_progress [expr {$now+500}]
        }
        after 20
    }
    resident_board::dump 0x08000000 16 [file join $dir mailbox.bin]
    if {[r 8]!=3 || [r 32]!=0 || [r 44]!=300} {error "A53 failed result=[r 32] stage=[r 44]"}
    set t [expr {(($frames-1)/2-1)/2}]
    if {[r 36]!=$t || [r 40]==0} {error "invalid output shape or PL coverage"}
    resident_board::dump 0x08100000 [expr {$t*512}] [file join $dir encoder_output_f32.bin]
    publish [file join $dir DONE] $seq
}
proc enc::serve {control} {
    connect -url tcp:127.0.0.1:3121
    start $control
    for {set i 1} {[alive $control]} {incr i} {
        set job [file join $control [format "job_%08d" $i]]
        while {![file isfile $job]} {if {![alive $control]} {return}; after 10}
        set dir [readtext $job]
        if {![file isdirectory $dir]} {error "missing host job directory"}
        if {[catch {run $control $dir} msg opts]} {
            publish [file join $dir FAILED] $msg
            return -options $opts $msg
        }
    }
}
if {$argc==1} {
    set control [file normalize [lindex $argv 0]]
    set rc [catch {enc::serve $control} msg opts]
    if {$rc} {enc::publish [file join $control FAILED] [dict get $opts -errorinfo]}
    catch {disconnect}
    exit $rc
}
