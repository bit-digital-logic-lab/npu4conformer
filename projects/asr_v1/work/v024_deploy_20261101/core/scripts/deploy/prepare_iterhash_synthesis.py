from pathlib import Path
r=Path(__file__).resolve().parents[2]
s=(r/'scripts/deploy/synth_core128_ooc.tcl').read_text()
s=s.replace('project128','project128_iterhash').replace('v024_core128','v024_core128_iterhash').replace('reports core128_','reports core128_iterhash_')
s=s.replace('if {$source ne ""} {read_verilog -sv [file join $root $source]}','if {$source eq "rtl/graph/wc_graph_ctrl.sv"} {read_verilog -sv [file join $root analysis wc_graph_ctrl_iterhash.sv]} elseif {$source ne ""} {read_verilog -sv [file join $root $source]}')
s=s.replace('V024_CORE128_OOC_SYNTH_PASS','V024_CORE128_ITERHASH_OOC_SYNTH_PASS')
s=s.replace('puts $fh "MAX_NODES=128"','puts $fh "MAX_NODES=128"\nputs $fh "CONTROLLER_SOURCE=analysis/wc_graph_ctrl_iterhash.sv"')
(r/'scripts/deploy/synth_core128_iterhash_ooc.tcl').write_text(s,newline='\n')
print('Prepared separate candidate synthesis Tcl; NOT launched')
