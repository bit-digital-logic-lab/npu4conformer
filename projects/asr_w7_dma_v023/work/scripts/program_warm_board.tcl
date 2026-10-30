# User explicitly released A51A2070. Volatile PL only; strict build/ownership gate.
set root [file normalize [file join [file dirname [info script]] ..]]
set tag [lindex $argv 0]
if {![regexp {^run[0-9]{3,6}$} $tag]||[lindex $argv 1] ne "--board-released"} {error "Fresh runNNN --board-released required after explicit human release"}
set session [file join $root board $tag]
if {[file exists $session]} {error "Fresh receipt required; no replay/reset"}
set seal [exec D:/app/ananconda/envs/asronnx312_int16/python.exe -I -B -X utf8 [file join $root scripts seal_runtime.py] full002 --verify]
puts $seal;if {![string match *V022_RUNTIME_SEAL_VERIFIED* $seal]} {error "Offline release not sealed"}
open_hw_manager;connect_hw_server -url localhost:3121
try {
 set ts [get_hw_targets -quiet *210512180081];if {[llength $ts]!=1} {error "Wrong cable"}
 current_hw_target [lindex $ts 0];open_hw_target
 try {
  set d [get_hw_devices -quiet xczu15_0]
  if {[llength $d]!=1||[llength [get_hw_devices]]!=2||![string equal -nocase [get_property IDCODE_HEX $d] 14750093]} {error "Wrong chip/chain"}
  current_hw_device $d;refresh_hw_device -update_hw_probes false $d
  set before [get_property REGISTER.USR_ACCESS $d]
  if {$before!=0xA51A2070||[get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $d]!=1||[get_property {REGISTER.CONFIG_STATUS.BIT[00]_CRC_ERROR} $d]!=0} {error "Only explicitly released2070 accepted; preserve changed board"}
  set check [exec D:/fpga/new2025/vitis/2025.2/Vitis/bin/xsdb.bat [file join $root scripts audit_warm_handoff.tcl] preprogram_$tag]
  puts $check;if {![string match *AUTONOMY_BOARD_READONLY_AUDIT_PASS* $check]} {error "Live CPU/cache/DDR/matrix/copy/job drain audit failed"}
  set_property PROGRAM.FILE [file join $root soc_full build full002 v022_full.bit] $d
  set begin [clock milliseconds];program_hw_devices $d;refresh_hw_device -update_hw_probes false $d
  set done [get_property {REGISTER.CONFIG_STATUS.BIT[14]_DONE_PIN} $d];set eos [get_property {REGISTER.CONFIG_STATUS.BIT[04]_END_OF_STARTUP_(EOS)_STATUS} $d];set crc [get_property {REGISTER.CONFIG_STATUS.BIT[00]_CRC_ERROR} $d];set marker [get_property REGISTER.USR_ACCESS $d]
  if {$done!=1||$eos!=1||$crc!=0||$marker!=0xA51A2201} {error "V022 programming not confirmed; preserve state"}
  file mkdir $session;set f [open [file join $session programmed.txt] w]
  puts $f "V022_PHASE1_VOLATILE_PL_PROGRAMMED\nUSR_ACCESS=A51A2201\nBUILD=full002\nBEFORE=$before DONE=$done EOS=$eos CRC=$crc\nPROGRAM_MS=[expr {[clock milliseconds]-$begin}]\nHumanreleased2070; live fullDMA/CPU/cache audit. NoPSreset/DDRinit/clock/MIO/mediawrites."
  close $f;puts V022_PHASE1_PROGRAMMED_PASS
 } finally {close_hw_target}
} finally {disconnect_hw_server;close_hw_manager}
exit
