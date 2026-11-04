# All called hardware APIs below are replaced by in-memory stubs before use.
# The saved receipt is explicitly in_memory_test_only and must be rejected by
# the production physical-board verifier, even when acquisition flow completes.
source [file join [file dirname [info script]] load_run_verify.tcl]
namespace eval flowmock {
    variable memory [dict create]
    variable txns [dict create]
    variable alias 0
}
if {$argc == 1 && [lindex $argv 0] eq "alias"} {set flowmock::alias 1}
proc get_hw_axis {args} {return mock_axi}
proc create_hw_axi_txn {name axi args} {
    set d [dict create DATA {}]
    for {set i 0} {$i < [llength $args]} {incr i} {
        set k [lindex $args $i]
        if {$k eq "-force"} {continue}
        incr i
        dict set d $k [lindex $args $i]
    }
    dict set flowmock::txns $name $d
    return $name
}
proc run_hw_axi {name} {
    set d [dict get $flowmock::txns $name]
    set addr [expr "0x[dict get $d -address]"]
    if {$flowmock::alias && $addr >= 0x10000000 && $addr < 0x10010000} {
        set addr [expr {0x04000000+$addr-0x10000000}]
    }
    set count [dict get $d -len]
    if {[dict get $d -type] eq "WRITE"} {
        set words [lreverse [split [dict get $d -data] _]]
        for {set i 0} {$i < $count} {incr i} {
            dict set flowmock::memory [expr {$addr+4*$i}] [lindex $words $i]
        }
        if {$addr == 0xa0000010} {
            foreach {a v} {
                0xa1000010 0x30 0xa1000018 7 0xa100001c 5 0xa1000020 1000
                0xa1000038 2048 0xa0000004 2 0xa0000014 7 0xa0000020 1000
            } {dict set flowmock::memory [expr {$a+0}] [format %08x $v]}
        }
    } else {
        set words {}
        for {set i 0} {$i < $count} {incr i} {
            set a [expr {$addr+4*$i}]
            if {[dict exists $flowmock::memory $a]} {
                lappend words [dict get $flowmock::memory $a]
            } else {lappend words 00000000}
        }
        dict set flowmock::txns $name DATA [join [lreverse $words] {}]
    }
}
proc list_property {object} {return {CLASS}}
proc get_property {property object} {
    if {$property eq "CLASS"} {return in_memory_mock}
    return [dict get $flowmock::txns $object $property]
}
foreach {a v} {
    0xa1000000 0xa51a2480 0xa1000004 128 0xa1000010 0x10
    0xa0000000 0xa51a22d0 0xa0000090 1 0xa00000c4 1
} {dict set flowmock::memory [expr {$a+0}] [format %08x $v]}
rename v024host::body v024host::production_body
proc v024host::body {timeout_ms} {
    variable receipt
    dict set receipt evidence_kind in_memory_test_only
    production_body $timeout_ms
}
set test_dir [file join [file dirname [info script]] tests flow_[clock milliseconds]]
set failed [catch {v024_board_verify mock_axi $test_dir 1000} message]
if {$flowmock::alias} {
    if {!$failed || ![string match {*arena full readback mismatch*} $message]} {
        error "expected memory-alias rejection, got: $message"
    }
    if {[dict exists $v024host::receipt start_issued] || [dict get $flowmock::memory [expr {0xa1000008+0}]] ne "00000000"} {
        error "alias case released core reset or issued START"
    }
    set report_name flow_alias_test_result.json
} else {
    if {!$failed || ![string match {*receipt is not a hardware acquisition*} $message]} {
        error "expected physical-evidence boundary rejection, got: $message"
    }
    if {[dict get $v024host::receipt board_status] != 0x30 ||
        [dict get $v024host::receipt csr_status] != 2 ||
        [dict get $v024host::receipt poll_timed_out] != 0} {
        error "completed CSR must be detected when board done pulse is already gone"
    }
    set report_name flow_test_result.json
}
set f [open [file join [file dirname [info script]] tests $report_name] w]
puts $f "\{\"pass\":true,\"hardware_access\":false,\"alias_case\":$flowmock::alias,\"failure_boundary\":[v024host::json_string $message],\"run_directory\":[v024host::json_string [file normalize $test_dir]]\}"
close $f
puts "TCL_FLOW_TEST_PASS: alias=$flowmock::alias, expected rejection, no hardware access"
exit
