# Read only. Refresh and persist the identity of the currently attached image.
if {$argc != 1} {error "expected output file for current hardware identity"}
open_hw_manager
connect_hw_server -url 127.0.0.1:3121 -cs_url 127.0.0.1:3042
try {
    set cable [get_hw_targets */Digilent/210512180081]
    if {[llength $cable] != 1} {error "designated cable unavailable"}
    current_hw_target [lindex $cable 0]
    open_hw_target
    set dev [get_hw_devices -filter {PART == xczu15}]
    if {[llength $dev] != 1} {error "expected a single xczu15"}
    set dev [lindex $dev 0]
    refresh_hw_device $dev
    set usr [get_property REGISTER.USR_ACCESS $dev]
    if {$usr != 0xa51a2493} {error "the currently programmed board has USR_ACCESS=$usr"}
    set f [open [lindex $argv 0] {WRONLY CREAT EXCL}]
    try {
        puts $f "usr_access=[format 0x%08X $usr]\npart=[get_property PART $dev]\nserial=[lindex [split [lindex $cable 0] /] end]"
    } finally {close $f}
    puts "VOICE_CURRENT_IMAGE_2493"
} finally {
    catch {close_hw_target}
    disconnect_hw_server
    close_hw_manager
}
