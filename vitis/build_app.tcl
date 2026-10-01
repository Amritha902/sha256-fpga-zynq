#=============================================================================
#  build_app.tcl  —  Vitis 2022.2 (XSCT): platform + bare-metal application
#
#  Takes the hardware handoff from vivado/build_system.tcl and builds the
#  standalone ARM Cortex-A9 program in sw/ against it. No GUI.
#
#      xsct vitis/build_app.tcl cfgA        (or cfgB, cfgC, cfgD)
#
#  Input   build_<cfg>/sha256_system.xsa
#  Output  vitis_ws_<cfg>/sha256_app/Debug/sha256_app.elf
#          vitis_ws_<cfg>/sha256_plat/export/... (ps7_init.tcl, bitstream)
#
#  sw/test_sw.c is the host-side unit test and has its own main(); it is
#  deliberately NOT imported.
#=============================================================================
set CFG "cfgA"
if {$argc > 0} { set CFG [lindex $argv 0] }

set ROOT [file normalize [file join [file dirname [info script]] ..]]
set XSA  "$ROOT/build_$CFG/sha256_system.xsa"
set WS   "$ROOT/vitis_ws_$CFG"
if {![file exists $XSA]} {
    error "No hardware handoff at $XSA. Run: vivado -mode batch -source vivado/build_system.tcl -tclargs <0..3>"
}

file delete -force $WS
setws $WS

platform create -name sha256_plat -hw $XSA -proc ps7_cortexa9_0 -os standalone
platform generate

app create -name sha256_app -platform sha256_plat -domain standalone_domain \
    -template {Empty Application(C)}

foreach f {main.c sha256_hw.c sha256_hw.h sha256_pair.c sha256_sw.c sha256_sw.h} {
    importsources -name sha256_app -path "$ROOT/sw/$f"
}

app config -name sha256_app build-config release
app build  -name sha256_app

set ELF [glob -nocomplain "$WS/sha256_app/*/sha256_app.elf"]
if {$ELF eq ""} { error "Build produced no ELF - see the console above" }
puts ""
puts "============================================================"
puts " ELF : $ELF"
puts " Next: xsct vitis/run_on_board.tcl $CFG   (ZedBoard on JTAG)"
puts "============================================================"
