set work [file normalize [file dirname [info script]]]
set base [file dirname $work]
set b [file join $work build]
set r [file join $work reports]
set_param general.maxThreads 8
puts "PHYSICAL_THREADS_LIMIT=[get_param general.maxThreads]"
set stages {input optimized placed physopt routed}
set from [lindex $argv 0]
set rank [lsearch -exact $stages $from]
if {$rank < 0} {error "unknown resume point: $from"}
proc readfile {p} {set f [open $p]; set data [read $f]; close $f; return $data}
proc xdc_commands {p} {
    set result {}
    foreach line [split [readfile $p] \n] {
        set line [string trim $line]
        if {$line ne "" && ![string match "#*" $line]} {lappend result $line}
    }
    return $result
}
if {$rank == 0} {
    open_checkpoint [file join $base build ps_ddr_synth.dcp]
    write_xdc -force -type timing [file join $r input.xdc]
    if {[xdc_commands [file join $r input.xdc]] ne [xdc_commands [file join $base build shell_timing.xdc]]} {
        error "new system timing constraint commands differ from its signed PS shell"
    }
    set_property BITSTREAM.CONFIG.USR_ACCESS 0xA51A2493 [current_design]
    set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
} else {
    open_checkpoint [file join $b $from.dcp]
}
proc identity {} {
    # current_design returns a Vivado in-memory design handle, not the RTL top.
    set summary [report_utilization -return_string]
    if {![regexp -line {^\| Design\s*:\s*ps_ddr_wrapper\s*$} $summary] || ![regexp -line {^\| Device\s*:\s*xczu15eg-ffvb1156-2-i\s*$} $summary]} {error "wrong top or part in design report"}
    if {[llength [get_ports -quiet *]] || [llength [get_cells -quiet -hier -filter {REF_NAME == PS8}]] != 1} {error "unexpected PL pins or PS8 count"}
    if {[llength [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]]} {error "unlinked blackbox"}
    if {[get_property BITSTREAM.CONFIG.USR_ACCESS [current_design]] != 0xA51A2493} {error "unexpected user access ID"}
    set clocks [get_clocks -quiet *]
    if {$clocks ne "clk_pl_0" || abs([get_property PERIOD $clocks] - 20.625) > 0.0001} {error "wrong PS clock"}
}
identity
if {$rank == 0 && [llength [get_cells -quiet -hier -filter {REF_NAME =~ pe_w7_c48_cfg*}]] != 256} {error "wrong PE count"}
if {$rank < 1} {
    opt_design
    write_checkpoint -force [file join $b optimized.dcp]
    puts "CHECKPOINT_PASS optimized"
}
if {$rank < 2} {
    place_design -directive AltSpreadLogic_high
    write_checkpoint -force [file join $b placed.dcp]
    puts "CHECKPOINT_PASS placed"
    report_timing_summary -file [file join $r placed_timing.rpt]
}
if {$rank < 3} {
    phys_opt_design -directive AggressiveExplore
    write_checkpoint -force [file join $b physopt.dcp]
    puts "CHECKPOINT_PASS physopt"
}
if {$rank < 4} {
    if {[catch {route_design -directive AlternateCLBRouting} reason]} {
        catch {report_route_status -file [file join $r route_failed.rpt]}
        catch {report_design_analysis -congestion -file [file join $r congestion_failed.rpt]}
        error $reason
    }
    write_checkpoint -force [file join $b routed.dcp]
    puts "CHECKPOINT_PASS routed"
}
identity
report_route_status -file [file join $r route.rpt]
report_utilization -file [file join $r utilization.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose -report_unconstrained -max_paths 10 -file [file join $r timing.rpt]
report_drc -file [file join $r drc.rpt]
check_timing -verbose -file [file join $r check_timing.rpt]
report_clocks -file [file join $r clocks.rpt]
set route [readfile [file join $r route.rpt]]
foreach {phrase name} {{nets with routing errors} errors {routable nets} total {fully routed nets} fully} {
    if {![regexp [format {# of %s\.+\s*:\s*([0-9]+)} $phrase] $route -> $name]} {error "missing route count: $phrase"}
}
if {$errors != 0 || $fully != $total || $total == 0} {error "route incomplete"}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == "Error" || SEVERITY == "Critical Warning"}]]} {error "blocking DRC"}
set check [readfile [file join $r check_timing.rpt]]
foreach test {no_clock unconstrained_internal_endpoints no_input_delay no_output_delay multiple_clock generated_clocks loops latch_loops} {
    if {![regexp [format {checking %s \(([0-9]+)\)} $test] $check -> n] || $n != 0} {error "timing coverage failed: $test"}
}
if {![string match {*All user specified timing constraints are met.*} [readfile [file join $r timing.rpt]]]} {error "timing violation"}
foreach delay {min max} {
    set paths [get_timing_paths -delay_type $delay -max_paths 1]
    if {![llength $paths] || [get_property SLACK $paths] < 0} {error "missing or negative $delay path"}
    puts "SIGNED_SLACK $delay [get_property SLACK $paths]"
}
set skew [report_bus_skew -return_string]
set f [open [file join $r bus_skew.rpt] w]; puts $f $skew; close $f
if {[regexp -nocase {set_bus_skew} [join [xdc_commands [file join $base build shell_timing.xdc]] \n]] || [regexp {Bus Skew Report Per Constraint} $skew]} {
    set checked 0
    foreach line [split $skew \n] {
        if {[regexp {^\s*(?:Slow|Fast)\s+[0-9.]+\s+[0-9.]+\s+(-?[0-9.]+)} $line -> slack]} {
            incr checked
            if {$slack < 0} {error "negative bus skew"}
        }
    }
    if {!$checked} {error "missing expected bus skew results"}
}
write_bitstream -force [file join $b candidate_A51A2493.bit]
puts "PHYSICAL_2493_PASS ROUTED=$fully USR_ACCESS=0xA51A2493 NO_BOARD"
