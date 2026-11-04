# Standalone Tcl transport checks. This interpreter has no XSDB connection.
if {[llength $argv] != 1 || [file exists [lindex $argv 0]]} {error "pass a fresh temporary output directory"}
set run [lindex $argv 0]
file mkdir $run
source [file join [file dirname [info script]] capture_ddr.tcl]
set ::writes 0
array set ::memory {}
proc mwr {args} {
    incr ::writes
    if {"-bin" in $args} {
        set data [resident_board::contents [lindex $args end-2]]
        set ::memory([expr {[lindex $args end-1]}]) $data
    } else {
        set addr [expr {[lindex $args end-1]}]
        set ::memory($addr) [string replace $::memory($addr) 0 3 [binary format i [lindex $args end]]]
    }
}
proc mrd {args} {
    if {"-bin" in $args} {
        set fp [open [lindex $args end-2] wb]
        puts -nonewline $fp $::memory([expr {[lindex $args end-1]}])
        close $fp
    } else {
        binary scan $::memory([expr {[lindex $args end]}]) i result
        return $result
    }
}
set resident_board::receipt [open [file join $run offline_csr.tsv] w]
foreach {name addr seed} {arena 0x0400f000 0xab012303 param 0x1000f000 0x5d5aa5a5 extended 0x1004f000 0xf0003050} {
    set initial [string repeat "\x11" 64]
    set ::memory([expr {$addr}]) $initial
    set pattern [lrepeat 16 $seed]
    set file [open [file join $run probe_${name}.bin] wb]
    puts -nonewline $file [binary format i* $pattern]
    close $file
}
resident_board::probe_ddr $run
foreach addr {0x0400f000 0x1000f000 0x1004f000} {
    if {$::memory([expr {$addr}]) ne $initial} {error "scratch restoration failed"}
}
foreach {addr val} {0xfd070004 1 0xff5e00c0 0x01011602 0xa1000000 0xa51a2480 0xa1000004 128 0xa1000008 1} {
    set ::memory([expr {$addr}]) [binary format i $val]
}
set before $::writes
if {![catch {resident_board::body $run} msg] || ![string match "*not a fresh*" $msg] || $before != $::writes} {
    error "warm state was not rejected before any write"
}
close $resident_board::receipt
puts "OFFLINE_ONLY_PASS signed_and_decimal_mrd binary_upload independent_address_challenges scratch_restore warm_refusal; no board access"
