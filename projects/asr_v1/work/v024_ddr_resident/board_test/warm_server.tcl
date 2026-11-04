# A single live XSDB connection supports any number of sequential utterances.
# Each independently created directory uses fresh request numbers 1..61.
source [file join [file dirname [info script]] voice_server.tcl]
namespace eval warm {}
proc warm::alive {control} {
    set lease [file join $control lease]
    return [expr {![file exists [file join $control STOP]] && [file isfile $lease] &&
                  [clock seconds] - [file mtime $lease] < 45}]
}
proc warm::one {control run} {
    voice::check_idle
    set log [open [file join $run telemetry.tsv] {WRONLY CREAT EXCL}]
    try {
        puts $log "id\twords\tcycles\twitness_before\twitness_target\twitness_after"
        flush $log
        for {set i 1} {$i <= 61} {incr i} {
            set req [file join $run request_[format %04d $i].hex]
            set deadline [expr {[clock milliseconds]+120000}]
            while {![file exists $req]} {
                if {![alive $control]} {error "host lease ended during utterance"}
                if {[file exists [file join $run CANCEL]]} {error "utterance cancelled"}
                if {[clock milliseconds] >= $deadline} {error "no SQRT request within 120 seconds"}
                after 2
            }
            voice::request $run $i $log
        }
    } finally {close $log}
    voice::atomic [file join $run UTTERANCE_DONE] 61
}
proc warm::serve {control inputs} {
    resident_board::select_psu
    if {([resident_board::read32 0xfd070004] & 15) != 1 ||
        ([resident_board::read32 0xff5e00c0] & 0x013f3f07) != 0x01011602} {error "DDR/PL clock not initialized"}
    voice::check_plan $control $inputs
    voice::atomic [file join $control READY] [pid]
    for {set seq 1} {[alive $control]} {incr seq} {
        set job [file join $control [format job_%08d $seq]]
        while {![file isfile $job]} {
            if {![alive $control]} {return}
            after 10
        }
        set fh [open $job r]
        fconfigure $fh -encoding utf-8
        try {set run [string trimright [read $fh] "\r\n"]} finally {close $fh}
        if {![file isdirectory $run] || [file exists [file join $run telemetry.tsv]]} {error "reused/invalid utterance directory"}
        if {[catch {one $control $run} err opts]} {
            voice::atomic [file join $run FAILED] [dict get $opts -errorinfo]
            return -options $opts $err
        }
    }
}
if {$argc > 0 && [lindex $argv 0] eq "--warm-live"} {
    if {$argc != 3} {error "requires --warm-live CONTROL_DIR INPUTS_DIR"}
    lassign $argv opt control inputs
    set failed [catch {
        connect -url tcp:127.0.0.1:3121
        warm::serve $control $inputs
    } err opts]
    if {$failed} {voice::atomic [file join $control FAILED] [dict get $opts -errorinfo]; puts stderr $err}
    catch {disconnect}
    exit $failed
}
