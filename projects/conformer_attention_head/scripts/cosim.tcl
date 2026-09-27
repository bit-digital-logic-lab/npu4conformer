set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
open_project [file join $root core_hls]
open_solution solution
cosim_design -rtl verilog -trace_level none
file copy -force [file join $root core_hls solution sim report conformer_head_cosim.rpt] [file join $root artifacts cosim.rpt]
exit
