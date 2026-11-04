# Source-only library. Requires an already connected XSDB session.
namespace eval resident_board {
    variable here [file normalize [file dirname [info script]]]
    variable serial 210512180081
}
proc resident_board::need {expr_text reason} {
    if {![uplevel 1 [list expr $expr_text]]} {error $reason}
}
proc resident_board::contents {path} {
    set ch [open $path rb]
    try {return [read $ch]} finally {close $ch}
}
proc resident_board::select_psu {} {
    variable serial
    set both [jtag targets -target-properties -filter {name == "xczu15" && jtag_cable_serial == "210512180081"}]
    need {[llength $both] == 1} "assigned xczu15 device not uniquely present"
    set ps [targets -target-properties -filter {name == "PSU" && jtag_cable_serial == "210512180081"}]
    need {[llength $ps] == 1} "assigned PSU DAP not uniquely present"
    targets -set [dict get [lindex $ps 0] target_id]
    return [lindex $ps 0]
}
proc resident_board::read32 {addr} {
    return [expr {wide([mrd -force -value -size w $addr]) & 0xffffffff}]
}
proc resident_board::record {key value} {
    variable receipt
    puts $receipt "$key\t[format 0x%llx $value]"
    flush $receipt
    return $value
}
proc resident_board::rd {key addr} {return [record $key [read32 $addr]]}
proc resident_board::dump {addr count path} {
    mrd -force -size w -bin -file $path $addr $count
    need {[file size $path] == 4*$count} "incomplete XSDB binary acquisition: $path"
}
proc resident_board::load {addr count path} {
    need {[file size $path] == 4*$count} "incorrect input size: $path"
    mwr -force -size w -bin -file $path $addr $count
}
proc resident_board::probe_ddr {run} {
    set locations {arena 0x0400f000 param 0x1000f000 extended 0x1004f000}
    foreach {name addr} $locations {dump $addr 16 [file join $run probe_${name}_prior.bin]}
    try {
        foreach {name addr} $locations {
            binary scan [contents [file join $run probe_${name}.bin]] i signed
            set word [expr {wide($signed) & 0xffffffff}]
            mwr -force -size w $addr $word
            need {[rd probe_${name}_scalar $addr] == $word} "single word mwr/mrd failed at $name"
        }
        foreach {name addr} $locations {load $addr 16 [file join $run probe_${name}.bin]}
        foreach {name addr} $locations {
            dump $addr 16 [file join $run probe_${name}_raw.bin]
            need {[contents [file join $run probe_${name}_raw.bin]] eq [contents [file join $run probe_${name}.bin]]} \
                "DDR readback differs after three independent writes: $name"
        }
    } finally {
        foreach {name addr} $locations {load $addr 16 [file join $run probe_${name}_prior.bin]}
    }
}
proc resident_board::body {run} {
    variable receipt
    need {([rd ddrc_stat 0xfd070004] & 15) == 1} "DDRC is not in normal operation"
    need {([rd pl0_ref 0xff5e00c0] & 0x013f3f07) == 0x01011602} "PL0 clock configuration differs from implemented shell"
    need {[rd board_magic 0xa1000000] == 0xa51a2480 && [rd capacity 0xa1000004] == 128} "bad board controller"
    # Document that the FIRST run begins from the hardware reset default.
    # Refuse a previously released core; writing a reset now would conceal it.
    foreach {name addr} {
        cold_release 0xa1000008 cold_completed 0xa1000018 cold_cycles_low 0xa1000020
        cold_cycles_high 0xa1000024 cold_rd 0xa1000028 cold_wr 0xa100002c cold_b 0xa1000030
    } {need {[rd $name $addr] == 0} "not a fresh and idle 2493 image: $name"}
    need {([rd cold_status 0xa1000010] & 0x0f) == 0} "cold board status not idle"
    puts "DDR_PHASE INPUT"
    probe_ddr $run
    foreach {name addr} {arena 0x04000000 param 0x10000000} {load $addr 16384 [file join $run $name.bin]}
    foreach {name addr} {arena 0x04000000 param 0x10000000} {
        dump $addr 16384 [file join $run ${name}_raw.bin]
        need {[contents [file join $run ${name}_raw.bin]] eq [contents [file join $run $name.bin]]} "input mismatch: $name"
        record ${name}_verified_words 16384
    }
    mwr -force 0xa1000008 1
    need {[rd release_reset_readback 0xa1000008] == 1} "core reset still asserted"
    need {[rd csr_magic 0xa0000000] == 0xa51a22d0} "core CSR magic mismatch"
    binary scan [contents [file join $run pc.bin]] i* pc
    need {[llength $pc] == 64} "invalid parameter shadow count"
    set offset 0
    foreach word $pc {
        mwr -force -size w [expr {0xa1000100+$offset}] [expr {wide($word) & 0xffffffff}]
        incr offset 4
    }
    set readback [open [file join $run pc_raw.bin] wb]
    try {
        for {set i 0} {$i < 64} {incr i} {
            set value [read32 [expr {0xa1000100+4*$i}]]
            puts -nonewline $readback [binary format i $value]
        }
    } finally {close $readback}
    need {[contents [file join $run pc_raw.bin]] eq [contents [file join $run pc.bin]]} "parameter shadow mismatch"
    record pc_verified_words 64
    need {[rd parameter_ready 0xa0000090] == 1 && [rd prestart_status 0xa0000004] == 0} "core not ready"
    mwr -force 0xa0000008 0x10008000
    mwr -force 0xa000000c 1
    need {[rd plan_base_readback 0xa0000008] == 0x10008000 && [rd plan_count_readback 0xa000000c] == 1} "bad plan"
    puts "DDR_PHASE FIRST_GRAPH"
    mwr -force 0xa0000010 1
    record start_count 1
    record start_issued 1
    set deadline [expr {[clock milliseconds]+60000}]
    while {([read32 0xa0000004] & 6) == 0 && ([read32 0xa1000010] & 12) == 0 && [clock milliseconds] < $deadline} {after 5}
    record poll_timed_out [expr {[clock milliseconds] >= $deadline}]
    foreach {name offset} {
        board_status 0x10 error 0x14 completed 0x18 last_node 0x1c cycles_low 0x20
        cycles_high 0x24 rd_pending 0x28 wr_pending 0x2c b_pending 0x30 c48_bytes 0x34 a16_bytes 0x38
    } {rd $name [expr {0xa1000000+$offset}]}
    foreach {name offset} {
        csr_status 0x04 csr_completed 0x14 csr_error 0x1c csr_cycles_low 0x20 csr_cycles_high 0x24
        csr_requires_reset_isolation 0xb0 csr_rd_pending 0xb4 csr_wr_pending 0xb8 csr_b_pending 0xbc csr_quiesced 0xc4
    } {rd $name [expr {0xa0000000+$offset}]}
    dump 0x04004000 8192 [file join $run output_raw.bin]
    record output_words 8192
}
proc resident_board::run {run identity python {release 0}} {
    variable here
    variable receipt
    set run [file normalize $run]
    set script [file join $here verify_ddr.py]
    need {$release in {0 1}} "release must be 0 or 1"
    puts [exec $python -I $script prepare $run [file normalize $identity] 2>@1]
    set ps [select_psu]
    set log [open [file join $run psu_target.txt] w]
    puts $log $ps
    close $log
    if {$release} {
        # This file is emitted by precisely the new linked PS block. Source at
        # global scope because its generated procedures use global variables.
        set init [file join $here .. physical_native shell_run project resident.gen sources_1 bd ps_ddr ip ps_ddr_ps_0 psu_init.tcl]
        need {([read32 0xfd070004] & 15) == 1} "DDRC must already be initialized by the deployment flow"
        uplevel #0 [list source $init]
        ::psu_ps_pl_isolation_removal
        ::psu_ps_pl_reset_config
    }
    set receipt [open [file join $run csr.tsv] {WRONLY CREAT EXCL}]
    try {
        record xsdb_cable_serial [dict get $ps jtag_cable_serial]
        body $run
    } finally {close $receipt}
    puts [exec $python -I $script verify $run 2>@1]
    return $run
}
