# 中文说明：完整 head 的 HLS RTL + UART 数据桥，所有推理运算在 FPGA。
set project_root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $project_root build vivado]
set project_file [file join $project_dir modelA_conformer_head_full_fpga.xpr]
if {[file exists $project_file]} {
 open_project $project_file
} else {
 create_project modelA_conformer_head_full_fpga $project_dir -part xc7a35tfgg484-1
 set_property target_language Verilog [current_project]
}
# 重跑 HLS 后按清单更新工程，保留磁盘上的旧生成文件，避免误用已失效的 RTL。
set generated [file join $project_root rtl generated]
set manifest [file join $generated sources.txt]
set sources {}
if {[file exists $manifest]} {
 set fd [open $manifest r]
 foreach name [split [read $fd] "\n"] {
  set name [string trim $name]
  if {$name ne ""} {lappend sources [file normalize [file join $generated $name]]}
 }
 close $fd
} else {
 set sources [glob -nocomplain [file join $generated *.v] [file join $generated *.dat]]
}
if {[llength $sources] == 0} {error "Missing generated RTL: run HLS or restore rtl/generated"}
foreach old [get_files -quiet [file join $generated *]] {
 if {[lsearch -exact $sources [file normalize $old]] < 0} {remove_files $old}
}
foreach f [concat [glob [file join $project_root rtl *.sv]] $sources] {
 if {![file exists $f]} {error "Missing design file: $f"}
 if {[llength [get_files -quiet $f]] == 0} {add_files $f}
}
set xdc [file join $project_root constraints ax7035.xdc]
if {[llength [get_files -quiet $xdc]] == 0} {add_files -fileset constrs_1 $xdc}
set_property top ax7035_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "PROJECT_READY: $project_file"
