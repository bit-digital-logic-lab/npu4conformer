foreach cmd {reset_timing read_checkpoint write_checkpoint} {
    puts [help $cmd]
}
puts "CLOCK_COMMANDS [info commands *clock*]"
exit
