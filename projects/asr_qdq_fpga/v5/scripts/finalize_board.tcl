# Finalize an already routed, source-hash-verified checkpoint. No hardware access.
# board_003 first build met timing, then its Python hash check failed because
# Vivado injects PYTHONHOME. Isolated Python below ignores that environment.
set root [file normalize [file join [file dirname [info script]] ..]]
set run_name [lindex $argv 0]
if {![regexp {^[A-Za-z0-9_]+$} $run_name]} {error "Unsafe run name"}
set out [file join $root build $run_name]
set bit [file join $out asr_v4_ax7035.bit]
if {[file exists $bit]} {error "Existing bitstream is protected"}
set python [expr {[info exists ::env(ASR_PYTHON)] ? $::env(ASR_PYTHON) : "python"}]
puts [exec $python -I [file join $root scripts capture_build_inputs.py] --run $run_name --verify]
open_checkpoint [file join $out asr_v4_route.dcp]
set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
if {$setup eq "" || $hold eq "" || $setup < 0 || $hold < 0} {error "Timing gate failed"}
report_drc -file [file join $out drc_finalize.rpt]
set errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $errors]} {error "DRC errors: $errors"}
set_property BITSTREAM.CONFIG.USR_ACCESS 0xA5160005 [current_design]
write_bitstream $bit
puts "ASR_V5_FINALIZE_PASS setup=$setup hold=$hold NO_HARDWARE_ACCESSED"
