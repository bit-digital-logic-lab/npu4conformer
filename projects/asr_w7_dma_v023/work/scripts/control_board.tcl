# Own V022 warm gateway only. START downloads A53 ELF; STOP restores prior cache.
set root [file normalize [file join [file dirname [info script]] ..]]
set action [lindex $argv 0];set tag [lindex $argv 1]
if {$action ni {start status stop}||![regexp {^run[0-9]{3,6}$} $tag]||[lindex $argv 2] ne "--board-released"} {error "start/status/stop runNNN --board-released required"}
set session [file join $root board $tag]
proc rd {a} {set t [string trim [mrd -force $a]];if {![regexp {:\s+([0-9a-fA-F]{8})$} $t -> v]} {error "Read failed $a"};scan $v %x v;expr {$v&0xffffffff}}
if {![file exists [file join $session programmed.txt]]} {error "Own programmed receipt required"}
puts [exec D:/app/ananconda/envs/asronnx312_int16/python.exe -I -B -X utf8 [file join $root scripts seal_runtime.py] full002 --verify]
connect -url tcp:127.0.0.1:3121
try {
 if {![string match *210512180081* [jtag targets]]} {error "Wrong cable"}
 targets -set -filter {name == "PSU"}
 if {[rd 0xA8000000]!=0xA51A21C1||[rd 0xA8000088]!=0x10102131||[rd 0xA9000000]!=0xA51A22D0||[rd 0xA900009C]!=0x10102201||[rd 0xA0000000]!=0xA51A1001||[rd 0xA4000000]!=0xA51A1310||[rd 0xFD070000]!=0x81040010||([rd 0xFD070004]&7)!=1||[rd 0xFF260020]!=33333000} {error "Known V022 warm identity/timer mismatch"}
 if {$action eq "start"} {
  if {[file exists [file join $session started.txt]]} {error "No START replay"}
  set state [targets];puts $state
  if {![regexp {Cortex-A53 #0 \((External Debug Request|Stopped|Halted)[^\r\n]*EL3} $state]||[regexp -all {Cortex-A53 #[123] \((Power On Reset|APU Reset)} $state]!=3||[regexp -all {RPU Reset} $state]!=2||[rd 0xFFFE0000]!=0xA51A1301||[rd 0xFFFE0004]!=2||[rd 0xFFFE0010]!=0||[rd 0xFFFE0078]!=[rd 0xFFFE0068]||[rd 0xFFFE007C]!=[rd 0xFFFE006C]||[rd 0xA4000004]!=0||([rd 0xA8000004]&5)!=0||([rd 0xA9000004]&5)!=0} {error "CPU/cache/DMA not clean, preserve state"}
  targets -set -filter {name == "Cortex-A53 #0"};dow [file join $root ps gateway_v022.elf];con;after 500
  targets -set -filter {name == "PSU"}
  if {[rd 0xFFFE0000]!=0xA51A1301||[rd 0xFFFE0004]!=1||[rd 0xFFFE0010]!=0} {error "Gateway boot not confirmed"}
  set hash [string trim [exec D:/app/ananconda/envs/asronnx312_int16/python.exe -I -B -c {import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())} [file join $root ps gateway_v022.elf]]]
  set f [open [file join $session started.txt] w]
  puts $f "V022_PHASE1_GATEWAY_STARTED\nUSR_ACCESS=A51A2201\nELF_SHA256=$hash\nCORE_HZ=125000000\nHumanreleasedboard; ownsignedoffbit; noPSreset/DDRinit/mediawrites.";close $f
  puts V022_PHASE1_GATEWAY_STARTED_PASS
 } elseif {$action eq "stop"} {
  if {![file exists [file join $session started.txt]]||[file exists [file join $session stopped.txt]]||[rd 0xFFFE0004]!=1||([rd 0xA9000004]&1)!=0||([rd 0xA8000004]&1)!=0} {error "Own drained running gateway required"}
  mwr -force 0xFFFE0008 1;set deadline [expr {[clock milliseconds]+10000}]
  while {[rd 0xFFFE0004]==1} {if {[clock milliseconds]>$deadline} {error "Stop timeout; preserve state"};after 10}
  if {[rd 0xFFFE0004]!=2||[rd 0xFFFE0010]!=0||[rd 0xFFFE0078]!=[rd 0xFFFE0068]||[rd 0xFFFE007C]!=[rd 0xFFFE006C]||[rd 0xA4000004]!=0||([rd 0xA8000004]&5)!=0||([rd 0xA9000004]&5)!=0} {error "Clean stop/cache/drain not confirmed"}
  targets -set -filter {name == "Cortex-A53 #0"};stop
  set f [open [file join $session stopped.txt] w];puts $f V022_PHASE1_GATEWAY_STOPPED_CACHE_RESTORED;close $f;puts V022_PHASE1_STOPPED_CACHE_RESTORED_PASS
 } else {puts [mrd -force 0xFFFE0000 64];puts [mrd -force 0xA9000000 44];puts [targets]}
} finally {disconnect}
exit
