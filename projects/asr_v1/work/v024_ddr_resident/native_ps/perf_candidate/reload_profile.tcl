# Processor-only, reversible swap between precisely the two qualified ELF binaries.
# Caller owns the shared board lock and has closed all resident XSDB sessions.
if {$argc ni {2 3}} {error "usage: reload_profile.tcl profile|baseline NEW_DIRECTORY ?prior_cleaned_log?"}
lassign $argv mode out prior
if {$mode ni {profile baseline} || [file exists $out]} {error "refusing invalid mode or prior directory"}
set out [file normalize $out]; file mkdir $out
set here [file normalize [file dirname [info script]]]
source [file join $here .. .. board_test capture_ddr.tcl]
set baseelf [file join $here .. build encoder.elf]
set perfelf [file join $here encoder_profile.elf]
set log [open [file join $out reload.log] {WRONLY CREAT EXCL}]
proc note {s} {puts $::log $s;flush $::log;puts $s;flush stdout}
proc pin {file expected} {
    set s [exec C:/Windows/System32/certutil.exe -hashfile [file nativename $file] SHA256]
    if {[string first $expected [string tolower $s]]<0} {error "ELF hash mismatch: $file"}
    note "PIN $expected $file"
}
proc core {} {targets -set -filter {name == "Cortex-A53 #0" && jtag_cable_serial == "210512180081"}}
proc regnum {name} {
    set raw [rrd -no-bits $name];note "REG $raw"
    if {![regexp -nocase {:\s*(?:0x)?([a-f0-9]+)\s*$} [string trim $raw] -> digits]} {
        error "cannot parse XSDB register $name"
    }
    return [expr 0x$digits]
}
proc confirm_region {file section start addr nbytes} {
    set path [file join $::out old_${section}.bin]
    resident_board::dump $addr [expr {$nbytes/4}] $path
    set f [open $file rb];seek $f $start
    try {set expected [read $f $nbytes]} finally {close $f}
    if {[resident_board::contents $path] ne $expected} {error "live immutable $section differs from source ELF"}
    note "MATCH $section [format 0x%x $addr] $nbytes"
}
proc idle {} {
    foreach {addr val mask} {0x08000000 0x50533234 0xffffffff 0x08000004 1 0xffffffff
        0x0800000c 7 7 0xfd070004 1 15 0xff5e00c0 0x01011602 0x013f3f07
        0xa0000004 0 5 0xa00000b0 0 0xffffffff 0xa00000b4 0 0xffffffff
        0xa00000b8 0 0xffffffff 0xa00000bc 0 0xffffffff} {
        set current [resident_board::read32 $addr]
        if {($current & $mask)!=$val} {error "firmware/PL idle gate failed at $addr: $current"}
    }
    if {[resident_board::read32 0x08000008] ni {1 3} ||
        [resident_board::read32 0x08000010] != [resident_board::read32 0x08000014]} {error "in-flight firmware request"}
}
set phase untouched
set code [catch {
    pin $baseelf 682dfd8096d4e62e325b107857461fbfd85f53fe722e494025cfd7d4082d1068
    pin $perfelf 5603019fcb94cd1f7d0889246ede0b2f2adb063f9373bbae37e7f7798b7dae7e
    if {$mode eq "profile"} {
        set old $baseelf;set next $perfelf;set bytes 0xfac0
        set idlepcs {0x0f000090 0x0f000094 0x0f000098 0x0f00009c 0x0f000118 0x0f00011c}
    } else {
        set old $perfelf;set next $baseelf;set bytes 0xfe80
        set idlepcs {0x0f0000a8 0x0f0000ac 0x0f0000b0 0x0f0000b4 0x0f0000b8 0x0f000144 0x0f000148}
    }
    connect -url tcp:127.0.0.1:3121
    resident_board::select_psu
    set cores [targets -target-properties -filter {name =~ "Cortex-A53 #*" && jtag_cable_serial == "210512180081"}]
    if {[llength $cores]!=4} {error "expected four target cores"}
    foreach c $cores {
        note "TARGET [dict get $c name] [dict get $c state_reason]"
        if {[dict get $c name] ne "Cortex-A53 #0" && [dict get $c state_reason] ni {{APU Reset} {Power On Reset}}} {
            error "another A53 is active"
        }
    }
    idle
    confirm_region $old boot 0x20000 0xfffc0000 0x10f0
    confirm_region $old tables 0x22000 0xfffc2000 0x6000
    confirm_region $old text 0x10000 0x0f000000 $bytes
    resident_board::dump 0x08000000 50 [file join $out mailbox_before.bin]
    core;catch {stop};set phase stopped_original
    set pc [regnum pc];set ok 0
    foreach known $idlepcs {if {$pc==$known} {set ok 1}}
    set resumed 0
    if {$prior ne ""} {
        set evidence [resident_board::contents $prior]
        if {![string match "*REG pc: 00000000fffc0108*REG pc: 00000000fffc00e4*RELOAD_FAILED phase=executing_cache_cleanup no register match: x0*" $evidence] ||
            ($pc!=0xfffc00e4 && $pc!=0xfffc0108)} {error "no matching previously cleaned stop"}
        set resumed 1;set phase executing_cache_cleanup
    }
    if {!$ok && !$resumed} {error "CPU was outside the verified idle loop at [format 0x%x $pc]"}
    foreach reg {cpsr sp x0 x30} {if {![catch {rrd -no-bits $reg} val]} {note "BEFORE $val"}}
    resident_board::select_psu;idle;core
    set phase executing_cache_cleanup
    if {!$resumed} {
        rwr pc 0xfffc00d8
        if {[regnum pc]!=0xfffc00d8} {error "cache cleanup entry not selected"}
        set done 0
        for {set i 0} {$i<8} {incr i} {
            con;after 250;stop
            if {[regnum pc]==0xfffc0108} {set done 1;break}
        }
        if {!$done} {error "cache-clean epilogue did not reach benchmark_done; firmware not overwritten"}
    } else {
        note "CONTINUE previous_proven_clean_epilogue=$prior"
    }
    # Single-step the previously verified 0xd53e1000. This is a direct hardware
    # read of SCTLR_EL3 even on XSDB versions without the SysReg register group.
    rwr pc 0xfffc00e0;stpi
    if {[regnum pc]!=0xfffc00e4} {error "unexpected PC after MRS SCTLR_EL3"}
    if {[catch {regnum r0} sctlr] && [catch {regnum x0} sctlr]} {
        note "REGS [rrd -no-bits]"
        error "could not read MRS destination R0/X0"
    }
    note "SCTLR_EL3_AFTER [format 0x%llx $sctlr]"
    rwr pc 0xfffc0108
    if {($sctlr&0x1005)!=0 || [regnum pc]!=0xfffc0108} {error "MMU or cache still enabled; firmware not overwritten"}
    set phase proven_clean
    resident_board::select_psu
    resident_board::dump 0xfffc0000 16384 [file join $out ocm_after_clean.bin]
    resident_board::dump 0x0f000000 32768 [file join $out private_after_clean.bin]
    resident_board::dump 0x08000000 50 [file join $out mailbox_after_clean.bin]
    # A zero mailbox magic ensures the next READY cannot be inherited.
    mwr -force -size w 0x08000000 0
    set phase loading_new
    core;rst -processor -clear-registers
    dow $next;verify $next;con
    resident_board::select_psu
    set deadline [expr {[clock milliseconds]+15000}]
    while {[resident_board::read32 0x08000000]!=0x50533234 && [clock milliseconds]<$deadline} {after 20}
    idle
    if {[resident_board::read32 0x08000008]!=1 || [resident_board::read32 0x08000014]!=0} {error "fresh READY absent"}
    resident_board::dump 0x08000000 16 [file join $out mailbox.bin]
    note "RELOAD_PASS target=$mode fresh_seq=0"
    set phase ready
} msg opts]
if {$code} {
    note "RELOAD_FAILED phase=$phase $msg"
    if {$phase eq "stopped_original"} {catch {core;con}}
    if {$phase in {executing_cache_cleanup proven_clean loading_new}} {catch {core;stop}}
}
catch {disconnect};close $log
if {$code} {puts stderr [dict get $opts -errorinfo];exit 1}
exit
