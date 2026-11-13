# Caller verifies this image's implementation receipt before invoking Vivado.
if {$argc ni {2 3}} {error "expected bitstream, unique output directory, optional --cold-boot"}
set cold_boot [expr {$argc == 3 && [lindex $argv 2] eq "--cold-boot"}]
if {$argc == 3 && !$cold_boot} {error "unknown programming option"}
set bit [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
if {![file isfile $bit] || ![file isdirectory $out]} {error "missing verified image or output"}
open_hw_manager
connect_hw_server -url 127.0.0.1:3121 -cs_url 127.0.0.1:3042
try {
    set cables [get_hw_targets */Digilent/210512180081]
    if {[llength $cables] != 1} {error "designated cable absent or ambiguous"}
    current_hw_target [lindex $cables 0]
    set_property PARAM.FREQUENCY 6000000 [lindex $cables 0]
    open_hw_target
    set devices [get_hw_devices -filter {PART == xczu15}]
    if {[llength $devices] != 1} {error "expected exactly one xczu15"}
    set device [lindex $devices 0]
    current_hw_device $device
    refresh_hw_device $device
    set old [get_property REGISTER.USR_ACCESS $device]
    puts "PREVIOUS_USR_ACCESS=$old"
    if {$old != 0xA51A2492 && $old != 0xA51A2493 &&
        !($cold_boot && ($old == 0 || $old == 0xffffffff))} {error "unexpected existing image"}
    set_property PROBES.FILE {} $device
    set_property PROGRAM.FILE $bit $device
    program_hw_devices -mpsoc_reset no $device
    refresh_hw_device $device
    set actual [get_property REGISTER.USR_ACCESS $device]
    if {$actual != 0xA51A2493} {error "new image identity mismatch"}
    set f [open [file join $out identity.txt] {WRONLY CREAT EXCL}]
    puts $f "usr_access=[format 0x%08X $actual]\npart=[get_property PART $device]\nserial=210512180081"
    close $f
    puts "PROGRAM_2493_PASS ACTUAL_USR_ACCESS=[format 0x%08X $actual]"
} finally {
    catch {close_hw_target}
    disconnect_hw_server
    close_hw_manager
}
exit
