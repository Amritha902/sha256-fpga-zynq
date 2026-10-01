#=============================================================================
#  run_on_board.tcl  —  program the ZedBoard over JTAG and run the program
#
#      xsct vitis/run_on_board.tcl cfgA      (or cfgB, cfgC, cfgD)
#
#  Prerequisites: board powered, PROG/JTAG micro-USB (J17) connected, boot
#  mode jumpers JP7-JP11 all to GND (JTAG boot), UART micro-USB (J14) open in
#  a terminal at 115200 8N1. The program prints its report on that UART.
#
#  Sequence: reset -> load bitstream -> ps7_init (DDR, clocks, MIO) ->
#            ps7_post_config (PS-PL level shifters) -> download ELF -> run.
#=============================================================================
set CFG "cfgA"
if {$argc > 0} { set CFG [lindex $argv 0] }

set ROOT [file normalize [file join [file dirname [info script]] ..]]
set WS   "$ROOT/vitis_ws_$CFG"
set BIT  "$ROOT/build_$CFG/sha256_system.bit"
set INIT [lindex [glob -nocomplain "$WS/sha256_plat/hw/ps7_init.tcl" \
                                   "$WS/sha256_plat/export/sha256_plat/hw/ps7_init.tcl"] 0]
set ELF  [lindex [glob -nocomplain "$WS/sha256_app/*/sha256_app.elf"] 0]

foreach {what f} [list bitstream $BIT ps7_init.tcl $INIT ELF $ELF] {
    if {$f eq "" || ![file exists $f]} { error "Missing $what - run build_system.tcl and build_app.tcl for $CFG first" }
}

connect
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 1000

targets -set -nocase -filter {name =~ "xc7z020*"}
fpga -file $BIT

targets -set -nocase -filter {name =~ "APU*"}
source $INIT
ps7_init
ps7_post_config

targets -set -nocase -filter {name =~ "*A9*#0"}
rst -processor
dow $ELF
con

puts ""
puts "============================================================"
puts " $CFG running on the ZedBoard. Watch the UART terminal."
puts " Expected: VERSION 0x53480001, NIST vectors PASS,"
puts "           ALL CONFORMANCE CHECKS PASSED"
puts "============================================================"
