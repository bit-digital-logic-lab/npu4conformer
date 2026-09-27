# Read-only JTAG discovery. No program_hw_devices and no configuration-memory writes.
open_hw_manager
connect_hw_server -url localhost:3121 -allow_non_jtag
set targets [get_hw_targets]
puts "ASR_PROBE_TARGET_COUNT=[llength $targets]"
foreach target $targets {
    puts "ASR_PROBE_TARGET=$target"
    current_hw_target $target
    if {[catch {open_hw_target $target} detail]} {
        puts "ASR_PROBE_OPEN_FAILED=$detail"
        continue
    }
    foreach device [get_hw_devices] {
        puts "ASR_PROBE_DEVICE=$device"
        puts "ASR_PROBE_PART=[get_property PART $device]"
        if {[catch {refresh_hw_device -update_hw_probes false $device} detail]} {
            puts "ASR_PROBE_REFRESH_NOTE=$detail"
        }
        # Read only status needed for connection checks; do not dump eFUSE/key data.
        foreach property {
            IDCODE_HEX PROGRAM.IS_SUPPORTED
            REGISTER.CONFIG_STATUS.BIT00_CRC_ERROR
            REGISTER.CONFIG_STATUS.BIT13_DONE_INTERNAL_SIGNAL_STATUS
            REGISTER.CONFIG_STATUS.BIT14_DONE_PIN
            REGISTER.CONFIG_STATUS.BIT15_IDCODE_ERROR
            REGISTER.USR_ACCESS
        } {
            puts "ASR_PROBE_$property=[get_property $property $device]"
        }
    }
    close_hw_target $target
}
disconnect_hw_server
close_hw_manager
puts "ASR_PROBE_DONE_NO_PROGRAMMING"
