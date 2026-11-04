# Pure in-memory transport tests. No hardware commands are loaded or invoked.
source [file join [file dirname [info script]] load_run_verify.tcl]
namespace eval mock {
    variable memory [dict create]
    variable txns [dict create]
    variable read_order descending
    variable write_order descending
}
proc create_hw_axi_txn {name axi args} {
    set d [dict create DATA {}]
    for {set i 0} {$i < [llength $args]} {incr i} {
        set k [lindex $args $i]
        if {$k eq "-force"} {continue}
        incr i
        dict set d $k [lindex $args $i]
    }
    dict set mock::txns $name $d
    return $name
}
proc run_hw_axi {name} {
    set d [dict get $mock::txns $name]
    scan [dict get $d -address] %x addr
    set count [dict get $d -len]
    if {[dict get $d -type] eq "WRITE"} {
        set words [split [dict get $d -data] _]
        if {$mock::write_order eq "descending"} {set words [lreverse $words]}
        for {set i 0} {$i < $count} {incr i} {
            dict set mock::memory [expr {$addr+4*$i}] [lindex $words $i]
        }
    } else {
        set words {}
        for {set i 0} {$i < $count} {incr i} {
            lappend words [dict get $mock::memory [expr {$addr+4*$i}]]
        }
        if {$mock::read_order eq "descending"} {set words [lreverse $words]}
        dict set mock::txns $name DATA [join $words {}]
    }
}
proc list_property {object} {return {CLASS}}
proc get_property {property object} {
    if {$property eq "CLASS"} {return in_memory_mock}
    return [dict get $mock::txns $object $property]
}
set test_root [file join [file dirname [info script]] tests tcl_mock]
file mkdir $test_root
set case_count 0
foreach ro {ascending descending} {
    foreach wo {ascending descending} {
        set mock::read_order $ro
        set mock::write_order $wo
        set v024host::read_order uncalibrated
        set v024host::write_order uncalibrated
        set v024host::axi mock_axi
        set v024host::run_dir [file join $test_root ${ro}_${wo}]
        file mkdir $v024host::run_dir
        set v024host::log [open [file join $v024host::run_dir mock_transactions.tsv] w]
        set v024host::receipt [dict create schema 1 evidence_kind in_memory_test_only]
        v024host::calibrate
        v024host::ensure {$v024host::read_order eq $ro && $v024host::write_order eq $wo} "order detection failed"
        set words {}
        for {set i 0} {$i < 16384} {incr i} {
            lappend words [format %08x [expr {(0x12345678 + $i*0x314159) & 0xffffffff}]]
        }
        v024host::upload_and_verify arena 0x04000000 $words
        v024host::ensure {[dict get $v024host::receipt arena_verified_words] == 16384} "full length not verified"
        # Ascending raw memory proves bulk upload did not reverse each chunk.
        for {set i 0} {$i < 16384} {incr i} {
            v024host::ensure {[dict get $mock::memory [expr {0x04000000+4*$i}]] eq [lindex $words $i]} "physical order mismatch"
        }
        close $v024host::log
        incr case_count
    }
}
foreach script {
    {v024host::safe_address 0xff260020 1}
    {v024host::safe_address 0x04000001 1}
    {v024host::safe_address 0x04000000 257}
    {v024host::safe_address 0x04000ffc 2}
    {v024host::safe_address 0xa0000000 2}
    {v024host::safe_address 0x10010000 1}
} {
    if {![catch $script]} {error "unsafe address/count accepted: $script"}
    incr case_count
}
set f [open [file join $test_root result.json] w]
puts $f "\{\"pass\":true,\"hardware_access\":false,\"cases\":$case_count\}"
close $f
puts "TCL_MOCK_TEST_PASS: $case_count cases, no hardware access"
exit
