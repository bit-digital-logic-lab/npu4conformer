# xsdb.bat run_once.tcl --capture-live NEW_OUTPUT_DIR IDENTITY_TXT PYTHON_EXE release|already-released
if {$argc != 5 || [lindex $argv 0] ne "--capture-live" || [lindex $argv 4] ni {release already-released}} {
    error "usage: run_once.tcl --capture-live NEW_OUTPUT_DIR PROGRAM_IDENTITY_TXT PYTHON_EXE release|already-released"
}
lassign $argv opt out identity python mode
source [file join [file dirname [info script]] capture_ddr.tcl]
connect -url tcp:127.0.0.1:3121
try {
    resident_board::run $out $identity $python [expr {$mode eq "release"}]
} finally {
    disconnect
}
