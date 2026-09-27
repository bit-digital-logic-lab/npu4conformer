# Create a separate ASR project. The existing adder_16.xpr is not modified.
# vivado -mode batch -source scripts/create_project.tcl
# No board PACKAGE_PIN assignments are guessed; no bitstream is generated.
set root [file normalize [file join [file dirname [info script]] ..]]
set target [file join $root build vivado_project]
if {[file exists [file join $target asr_int16.xpr]]} {
    error "ASR project already exists; open it instead. No files overwritten."
}
create_project asr_int16 $target -part xc7a35tfgg484-2
set_property target_language Verilog [current_project]
add_files [glob [file join $root rtl *.sv]]
add_files -fileset constrs_1 [file join $root constraints clock_ooc.xdc]
set_property top asr_uart_top [current_fileset]
set_property generic {CLK_HZ=50000000 BAUD=115200} [current_fileset]
update_compile_order -fileset sources_1
puts "Project created. Add verified board pin constraints before implementation/bitstream."
