connect -url tcp:127.0.0.1:3121
if {[catch {
    source {C:/Academic_Work/CIM_learning/work/v024_ddr_resident/board_test/capture_ddr.tcl}
    resident_board::run {C:/Academic_Work/CIM_learning/work/v024_ddr_resident/board_test/runs/20261102_204850/functional} {C:/Academic_Work/CIM_learning/work/v024_ddr_resident/board_test/runs/20261102_204850/identity.txt} {C:/Users/liuka/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe} 1
} message options]} {
    puts stderr [dict get $options -errorinfo]
    catch {disconnect}
    exit 1
}
disconnect
exit
