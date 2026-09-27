# Volatile JTAG configuration ONLY. Never program configuration memory/Flash.
set root [file normalize [file join [file dirname [info script]] ..]]
set bit [file join $root build board_build asr_v1_ax7035.bit]
if {![file isfile $bit]} {error "Missing accepted board bitstream: $bit"}
open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
set targets [get_hw_targets -quiet *210512180081]
if {[llength $targets] != 1} {error "Expected exactly the verified Digilent adapter 210512180081"}
set target [lindex $targets 0]
current_hw_target $target
open_hw_target $target
try {
    set devices [get_hw_devices]
    if {[llength $devices] != 1} {error "Expected one device in this JTAG chain"}
    set dev [lindex $devices 0]
    current_hw_device $dev
    refresh_hw_device -update_hw_probes false $dev
    if {[get_property PART $dev] ne "xc7a35t"} {error "Device part mismatch"}
    if {![string equal -nocase [get_property IDCODE_HEX $dev] "0362d093"]} {error "Device IDCODE mismatch"}
    set_property PROGRAM.FILE $bit $dev
    program_hw_devices $dev
    refresh_hw_device -update_hw_probes false $dev
    set done [get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev]
    set crc [get_property REGISTER.CONFIG_STATUS.BIT00_CRC_ERROR $dev]
    set marker [get_property REGISTER.USR_ACCESS $dev]
    puts "ASR_PROGRAM bit=$bit DONE=$done CRC_ERROR=$crc USR_ACCESS=$marker"
    if {$done != 1 || $crc != 0 || ![string equal -nocase $marker "a5160001"]} {
        error "Configuration verification failed"
    }
    puts "ASR_PROGRAM_PASS_VOLATILE_ONLY"
} finally {
    close_hw_target $target
    disconnect_hw_server
    close_hw_manager
}
