# No hardware commands: simulate an advancing and a stale SQRT output lane.
if {$argc != 1 || [file exists [lindex $argv 0]]} {error "pass a fresh temporary directory"}
set run [lindex $argv 0]
file mkdir $run
source [file join [file dirname [info script]] voice_server.tcl]
set witness 0x3f800000
set stale 0
proc resident_board::read32 {addr} {
    if {$addr == 0x04006808} {return $::witness}
    switch [format %x $addr] {a0000004 {return 2} a0000014 {return 7} a00000c4 {return 1} a0000020 {return 18000}}
    return 0
}
proc resident_board::load {addr count path} {
    if {$addr != 0x04002000 || $count != 3} {error "invalid input range"}
    binary scan [resident_board::contents $path] i* ::input
}
proc mwr {args} {
    if {$args ne {-force 0xa0000010 1}} {error "unexpected control write"}
    if {!$::stale} {set ::witness [expr {[lindex $::input end] == 0x40800000 ? 0x40000000 : 0x3f800000}]}
}
proc resident_board::dump {addr count path} {
    if {$addr != 0x04006800 || $count != 3} {error "invalid output range"}
    set f [open $path wb]
    puts -nonewline $f [binary format i* [list 0x40000000 0x40400000 $::witness]]
    close $f
}
set log [open [file join $run simulated_telemetry.tsv] w]
for {set i 1} {$i <= 3} {incr i} {
    set key [format %04d $i]
    voice::atomic [file join $run request_$key.hex] "40800000\n41100000"
    if {$i == 3} {
        set stale 1
        if {![catch {voice::request $run $i $log} message] || [file exists [file join $run response_$key.hex]]
            || ![string match "*witness*" $message]} {error "stale witness was accepted"}
    } else {
        voice::request $run $i $log
        set words [split [string trim [resident_board::contents [file join $run response_$key.hex]]] \n]
        if {[lmap value $words {string trim $value}] ne {40000000 40400000}} {error "wrong data or witness entered model"}
    }
}
close $log
puts "OFFLINE_ONLY_PASS two_consecutive_fresh_starts_and_stale_rejection; no board"
