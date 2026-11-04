# Resident, serial JTAG bridge for the already programmed 2492 image.
# All accelerator transactions use the original calibrated host library.
set out [file normalize [lindex $argv 0]]
source [lindex $argv 1]
set probes [file normalize [lindex $argv 2]]
set strict [expr {$argc < 4 || [lindex $argv 3] eq "0"}]
proc atomic_text {name value} {
    set tmp "${name}.tmp"
    set ch [open $tmp {WRONLY CREAT EXCL}]
    puts $ch $value
    close $ch
    file rename $tmp $name
}
proc read_block {base count} {
    set result {}
    for {set i 0} {$i < $count} {incr i $n} {
        set addr [expr {$base+4*$i}]
        set n [v024host::chunk_size $addr [expr {$count-$i}] 127]
        lappend result {*}[v024host::read_words $addr $n]
    }
    return $result
}
proc drained {} {
    foreach addr {0xa1000028 0xa100002c 0xa1000030} {
        v024host::ensure {[v024host::read32 $addr] == 0} "DMA pending before buffer reuse"
    }
}
proc matrix_tile {folder k} {
    global strict
    set key [format %04d $k]
    set start [clock milliseconds]
    v024host::ensure {[v024host::read32 0xa0000004] == 2} "core not idle for matrix"
    drained
    if {$k == 1} {
        # Column affine multipliers 2^-8, zero biases, checked through the live port.
        for {set j 0} {$j < 64} {incr j} {
            set val [expr {$j < 32 ? 0x3b800000 : 0}]
            set addr [expr {0xa1000100+4*$j}]
            v024host::write32 $addr $val
            v024host::ensure {[v024host::read32 $addr] == $val} "matrix scale or bias mismatch"
        }
    }
    set f [open [file join $folder tile_$key.req] r]
    lassign [string trim [read $f]] row inner col
    close $f
    foreach dim [list $row $inner $col] {
        v024host::ensure {[string is integer -strict $dim] && $dim >= 0 && $dim < 32} "invalid tile position"
    }
    set aname [format a_%02d_%02d.hex $row $inner]
    if {![info exists ::loaded_a] || $::loaded_a ne $aname} {
        set a [v024host::load_hex [file join $folder $aname] 512]
        v024host::upload_memory 0x10001000 $a
        if {$strict} {v024host::ensure {[read_block 0x10001000 512] eq $a} "A16 input did not read back"}
        set ::loaded_a $aname
    }
    set w [v024host::load_hex [file join $folder [format w_%02d_%02d.hex $inner $col]] 256]
    v024host::upload_memory 0x10002000 $w
    if {$strict} {v024host::ensure {[read_block 0x10002000 256] eq $w} "W7p8 weights did not read back"}
    # 0x8000 cannot be attained given the chosen input magnitudes and 1/256 scale.
    if {$strict} {
        set poison [lrepeat 512 80008000]
        v024host::upload_memory 0x04004000 $poison
        v024host::ensure {[read_block 0x04004000 512] eq $poison} "matrix output poison did not read back"
    }
    v024host::write32 0xa0000010 1
    while {1} {
        set status [v024host::read32 0xa0000004]
        if {$status & 6} break
        if {[clock milliseconds] > $start + 60000} {error "matrix tile timed out"}
        after 5
    }
    set completed [v024host::read32 0xa0000014]
    set err [v024host::read32 0xa000001c]
    v024host::ensure {$status == 2 && $completed == 7 && $err == 0} "matrix graph failed"
    drained
    set cycles [expr {[v024host::read32 0xa0000020] + ([v024host::read32 0xa0000024] << 32)}]
    set y [read_block 0x04004000 512]
    v024host::ensure {$cycles > 0 && [lsearch -exact $y 80008000] < 0} "matrix output stale"
    set tele [open [file join $folder telemetry.tsv] a]
    puts $tele "$k\t$row\t$inner\t$col\t$cycles\t$status\t$completed\t$err\t[expr {[clock milliseconds]-$start}]"
    close $tele
    atomic_text [file join $folder out_$key.hex] [join $y \n]
}
proc run_trial {} {
    global out probes strict
    open_hw_manager
    connect_hw_server -url 127.0.0.1:3121 -cs_url 127.0.0.1:3042
    set targets [get_hw_targets */Digilent/210512180081]
    v024host::ensure {[llength $targets] == 1} "assigned cable missing or ambiguous"
    set target [lindex $targets 0]
    current_hw_target $target
    set_property PARAM.FREQUENCY 6000000 $target
    open_hw_target
    set devs [get_hw_devices -filter {PART == xczu15}]
    v024host::ensure {[llength $devs] == 1} "expected xczu15 on assigned cable"
    set dev [lindex $devs 0]
    current_hw_device $dev
    set_property PROBES.FILE $probes $dev
    refresh_hw_device $dev
    set usr [get_property REGISTER.USR_ACCESS $dev]
    v024host::ensure {$usr == 0xA51A2492} "live image is $usr"
    set axes [get_hw_axis -of_objects $dev]
    v024host::ensure {[llength $axes] == 1} "expected one JTAG AXI master"
    atomic_text [file join $out identity.txt] "target=$target\npart=[get_property PART $dev]\nusr_access=$usr\njtag_hz=[get_property PARAM.FREQUENCY $target]"
    v024_board_verify [lindex $axes 0] [file join $out bootstrap] 60000
    set ::v024host::log [open [file join $out stream_axi.tsv] {WRONLY CREAT EXCL}]
    set tele [open [file join $out telemetry.tsv] {WRONLY CREAT EXCL}]
    puts $tele "id\twords\tcycles\tstatus\tcompleted\terror\tservice_ms"
    atomic_text [file join $out READY] 1
    set mat_id 1
    set mat_folder [file join $out matrix]
    for {set i 1} {1} {incr i} {
        set key [format %04d $i]
        set req [file join $out request_$key.hex]
        set deadline [expr {[clock milliseconds]+240000}]
        while {![file isfile $req]} {
            if {[file isfile [file join $out STOP]]} {close $tele; close $::v024host::log; return}
            if {[file isfile [file join $mat_folder [format tile_%04d.req $mat_id]]]} {
                matrix_tile $mat_folder $mat_id
                incr mat_id
                set deadline [expr {[clock milliseconds]+240000}]
                continue
            }
            if {[clock milliseconds] > $deadline} {error "no request within 240 s"}
            after 10
        }
        set started [clock milliseconds]
        set ch [open $req r]; set n [llength [split [string trim [read $ch]] \n]]; close $ch
        v024host::ensure {$n > 0 && $n <= 1024} "invalid SQRT vector length"
        set inputs [v024host::load_hex $req $n]
        v024host::ensure {[v024host::read32 0xa0000004] == 2} "core busy or faulted"
        drained
        v024host::upload_memory 0x04002000 $inputs
        if {$strict} {
            v024host::ensure {[read_block 0x04002000 $n] eq $inputs} "input readback mismatch"
            set poison [lrepeat $n 7fc01234]
            v024host::upload_memory 0x04006800 $poison
            v024host::ensure {[read_block 0x04006800 $n] eq $poison} "output poison readback mismatch"
        }
        v024host::write32 0xa0000010 1
        set deadline [expr {[clock milliseconds]+60000}]
        while {1} {
            set status [v024host::read32 0xa0000004]
            if {$status & 6} break
            if {[clock milliseconds] > $deadline} {error "graph did not finish"}
            after 5
        }
        set completed [v024host::read32 0xa0000014]
        set err [v024host::read32 0xa000001c]
        v024host::ensure {$status == 2 && $completed == 7 && $err == 0} "graph status=$status completed=$completed error=$err"
        drained
        set cycles [expr {[v024host::read32 0xa0000020] + ([v024host::read32 0xa0000024] << 32)}]
        set outputs [read_block 0x04006800 $n]
        v024host::ensure {$cycles > 0 && [lsearch -exact $outputs 7fc01234] < 0} "output not overwritten"
        puts $tele "$i\t$n\t$cycles\t$status\t$completed\t$err\t[expr {[clock milliseconds]-$started}]"
        flush $tele
        atomic_text [file join $out response_$key.hex] [join $outputs \n]
    }
}
set failed [catch {run_trial} msg opts]
if {$failed} {atomic_text [file join $out FAILED] [dict get $opts -errorinfo]; puts stderr "$msg"}
catch {close_hw_target}
catch {disconnect_hw_server}
catch {close_hw_manager}
exit $failed
