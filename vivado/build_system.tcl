#=============================================================================
#  build_system.tcl
#
#  FULLY AUTOMATED Vivado build for the SHA-256 accelerator system.
#
#  Packages the RTL as an IP, builds the complete block design (Zynq PS +
#  AXI DMA + accelerator + interconnect), runs synthesis and implementation,
#  generates the bitstream, and exports the hardware for Vitis.
#
#  This replaces roughly forty GUI clicks and, more importantly, makes the
#  build REPRODUCIBLE -- everyone on the team gets an identical design, and
#  the area/frequency numbers from Config A and Config B are comparable
#  because the surrounding system is bit-for-bit the same.
#
#  USAGE
#  -----
#      # Configuration A (iterative, default)
#      vivado -mode batch -source build_system.tcl
#
#      # Configuration B (2x unrolled)
#      vivado -mode batch -source build_system.tcl -tclargs 1
#
#  OUTPUTS  (in ./build_cfgA or ./build_cfgB)
#      sha256_system.xsa           hardware handoff for Vitis
#      sha256_system.bit           bitstream
#      reports/*.rpt               utilisation, timing, power
#      reports/summary.txt         the numbers you put in the report
#
#  RUNTIME: roughly 10-20 minutes per configuration on a typical laptop.
#=============================================================================

#-----------------------------------------------------------------------------
# Arguments and paths
#-----------------------------------------------------------------------------
set CORE_SELECT 0
if {$argc > 0} { set CORE_SELECT [lindex $argv 0] }

if {$CORE_SELECT == 0} {
    set CFG_NAME "cfgA"
    set CFG_DESC "Configuration A - iterative, 1 round/cycle, 66 cycles/block"
} else {
    set CFG_NAME "cfgB"
    set CFG_DESC "Configuration B - 2x unrolled, 2 rounds/cycle, 34 cycles/block"
}

set PART        xc7z020clg484-1
set BOARD_PART  em.avnet.com:zed:part0:1.4
set PROJ_DIR    [file normalize "./build_$CFG_NAME"]
set RTL_DIR     [file normalize "./rtl"]
set IP_REPO     [file normalize "$PROJ_DIR/ip_repo"]
set RPT_DIR     [file normalize "$PROJ_DIR/reports"]
set CLK_PERIOD  10.0

file mkdir $PROJ_DIR
file mkdir $RPT_DIR

puts ""
puts "============================================================"
puts " SHA-256 SYSTEM BUILD"
puts " $CFG_DESC"
puts " Part        : $PART"
puts " Output dir  : $PROJ_DIR"
puts "============================================================"
puts ""

set RTL_FILES [list \
    $RTL_DIR/sha256_functions.v      \
    $RTL_DIR/sha256_core_iter.v      \
    $RTL_DIR/sha256_core_unroll2.v   \
    $RTL_DIR/sha256_axi_lite_regs.v  \
    $RTL_DIR/sha256_axis_wrapper.v   \
    $RTL_DIR/sha256_top.v            \
]

#=============================================================================
# STEP 1 -- package sha256_top as a Vivado IP
#=============================================================================
puts "\[1/6\] Packaging sha256_top as an IP ..."

file mkdir $IP_REPO
set ip_prj "$PROJ_DIR/ip_pkg_prj"
create_project -force sha256_ip_pkg $ip_prj -part $PART
add_files -norecurse $RTL_FILES
set_property top sha256_top [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $IP_REPO -vendor vit.ac.in -library user \
                     -taxonomy /UserIP -import_files -force

set core [ipx::current_core]
set_property name        sha256_top                       $core
set_property display_name "SHA-256 Accelerator"           $core
set_property description  "SHA-256 hash accelerator, AXI4-Lite control + AXI4-Stream data" $core
set_property version      1.0                             $core
set_property core_revision 1                              $core

# Make CORE_SELECT visible so the two builds differ by ONE parameter
ipx::add_user_parameter CORE_SELECT $core
set up [ipx::get_user_parameters CORE_SELECT -of_objects $core]
set_property value_format long   $up
set_property value        $CORE_SELECT $up
ipx::associate_bus_interfaces -busif s_axi -clock s_axi_aclk $core
ipx::associate_bus_interfaces -busif s_axis -clock s_axi_aclk $core

ipx::create_xgui_files  $core
ipx::update_checksums   $core
ipx::save_core          $core
close_project
puts "      IP repository: $IP_REPO"

#=============================================================================
# STEP 2 -- create the system project and block design
#=============================================================================
puts "\[2/6\] Creating the system project and block design ..."

create_project -force sha256_system $PROJ_DIR -part $PART
catch { set_property board_part $BOARD_PART [current_project] }
set_property ip_repo_paths $IP_REPO [current_project]
update_ip_catalog -rebuild

create_bd_design "sha256_bd"

# ---- Zynq Processing System -------------------------------------------------
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 zynq_ps]
catch { apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" apply_board_preset "1" \
                 Master "Disable" Slave "Disable"} $ps }

# 100 MHz PL clock, one AXI-HP port for the DMA, one AXI-GP for control
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_USE_S_AXI_HP0            {1}   \
    CONFIG.PCW_M_AXI_GP0_ENABLE_STATIC_REMAP {0} \
] $ps

# ---- AXI DMA : MM2S only, simple mode ---------------------------------------
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg           {0}  \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s          {1}  \
    CONFIG.c_include_s2mm          {0}  \
    CONFIG.c_mm2s_burst_size       {16} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_include_mm2s_dre      {0}  \
] $dma

# ---- the accelerator --------------------------------------------------------
set sha [create_bd_cell -type ip -vlnv vit.ac.in:user:sha256_top:1.0 sha256_0]
set_property CONFIG.CORE_SELECT $CORE_SELECT $sha

puts "\[3/6\] Connecting the block design ..."

# stream: DMA MM2S -> accelerator
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
                    [get_bd_intf_pins sha256_0/s_axis]

# control paths, memory map and clocking, done by automation
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config \
    [list Master {/zynq_ps/M_AXI_GP0} Clk {Auto}] \
    [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config \
    [list Master {/zynq_ps/M_AXI_GP0} Clk {Auto}] \
    [get_bd_intf_pins sha256_0/s_axi]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config \
    [list Master {/axi_dma_0/M_AXI_MM2S} Slave {/zynq_ps/S_AXI_HP0} \
     ddr_seg {Auto} intc_ip {New AXI SmartConnect} Clk {Auto}] \
    [get_bd_intf_pins zynq_ps/S_AXI_HP0]

regenerate_bd_layout
validate_bd_design
save_bd_design

# report the address map so the base address can be checked against the driver
assign_bd_address
set fh [open "$RPT_DIR/address_map.txt" w]
puts $fh [report_bd_address -force -return_string]
close $fh
puts "      address map written to $RPT_DIR/address_map.txt"

#=============================================================================
# STEP 3 -- HDL wrapper and constraints
#=============================================================================
puts "\[4/6\] Generating the wrapper and constraints ..."

make_wrapper -files [get_files "$PROJ_DIR/sha256_system.srcs/sources_1/bd/sha256_bd/sha256_bd.bd"] -top
add_files -norecurse "$PROJ_DIR/sha256_system.gen/sources_1/bd/sha256_bd/hdl/sha256_bd_wrapper.v"
set_property top sha256_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1

# The Zynq PS supplies the clock, so no board-level clock constraint is
# needed.  This file only tightens the PL clock for the timing experiment.
set xdc "$PROJ_DIR/timing.xdc"
set fh [open $xdc w]
puts $fh "# Tighten the PL clock so the tool reports real slack rather than"
puts $fh "# stopping as soon as it meets a loose target.  Both configurations"
puts $fh "# are built with the SAME constraint, which is what makes their"
puts $fh "# Fmax numbers comparable."
puts $fh "create_clock -period $CLK_PERIOD -name pl_clk \[get_pins zynq_ps_i/PS7_i/FCLKCLK\[0\]\]"
close $fh
catch { add_files -fileset constrs_1 -norecurse $xdc }

#=============================================================================
# STEP 4 -- synthesis and implementation
#=============================================================================
puts "\[5/6\] Running synthesis and implementation (this takes a while) ..."

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "SYNTHESIS FAILED - see $PROJ_DIR/sha256_system.runs/synth_1/runme.log"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "IMPLEMENTATION FAILED - see $PROJ_DIR/sha256_system.runs/impl_1/runme.log"
}

#=============================================================================
# STEP 5 -- reports and export
#=============================================================================
puts "\[6/6\] Collecting reports and exporting hardware ..."

open_run impl_1

report_utilization -hierarchical -file "$RPT_DIR/utilization.rpt"
report_timing_summary            -file "$RPT_DIR/timing.rpt"
report_power                     -file "$RPT_DIR/power.rpt"

set wns  [get_property SLACK [get_timing_paths -delay_type max]]
set fmax [expr {1000.0 / ($CLK_PERIOD - $wns)}]

# count primitives inside the accelerator only, so the DMA and interconnect
# do not pollute the comparison
set sha_cells [get_cells -hier -filter {NAME =~ "*sha256_0*"}]
set n_lut  [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT        && NAME =~ "*sha256_0*"}]]
set n_ff   [llength [get_cells -hier -filter {PRIMITIVE_GROUP == FLOP_LATCH && NAME =~ "*sha256_0*"}]]
set n_bram [llength [get_cells -hier -filter {PRIMITIVE_GROUP == BLOCKRAM   && NAME =~ "*sha256_0*"}]]
set n_dsp  [llength [get_cells -hier -filter {PRIMITIVE_GROUP == DSP        && NAME =~ "*sha256_0*"}]]

set tot_lut [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT}]]
set tot_ff  [llength [get_cells -hier -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]

set sfh [open "$RPT_DIR/summary.txt" w]
puts $sfh "============================================================"
puts $sfh " $CFG_DESC"
puts $sfh "============================================================"
puts $sfh "Part                  : $PART"
puts $sfh "Target clock period   : $CLK_PERIOD ns  ([format %.1f [expr {1000.0/$CLK_PERIOD}]] MHz)"
puts $sfh "Worst negative slack  : $wns ns"
puts $sfh "Fmax estimate         : [format %.2f $fmax] MHz"
puts $sfh ""
puts $sfh "ACCELERATOR ONLY (sha256_0):"
puts $sfh "  LUT   : $n_lut"
puts $sfh "  FF    : $n_ff"
puts $sfh "  BRAM  : $n_bram"
puts $sfh "  DSP   : $n_dsp        <-- MUST BE 0"
puts $sfh ""
puts $sfh "WHOLE SYSTEM (incl. DMA and interconnect):"
puts $sfh "  LUT   : $tot_lut / 53200"
puts $sfh "  FF    : $tot_ff / 106400"
puts $sfh ""
if {$CORE_SELECT == 0} {
    puts $sfh "Cycles per 512-bit block : 66"
    puts $sfh "Throughput at Fmax       : [format %.1f [expr {512.0 * $fmax / 66.0}]] Mbit/s"
} else {
    puts $sfh "Cycles per 512-bit block : 34"
    puts $sfh "Throughput at Fmax       : [format %.1f [expr {512.0 * $fmax / 34.0}]] Mbit/s"
}
puts $sfh ""
puts $sfh "BREAK-EVEN REMINDER"
puts $sfh "  Config B is a net throughput win only if"
puts $sfh "      Fmax(B) / Fmax(A)  >  34/66  =  0.515"
puts $sfh "  Record both numbers and compute the ratio."
close $sfh

puts ""
puts [exec cat "$RPT_DIR/summary.txt"]

# export for Vitis
file copy -force "$PROJ_DIR/sha256_system.runs/impl_1/sha256_bd_wrapper.bit" \
                 "$PROJ_DIR/sha256_system.bit"
write_hw_platform -fixed -include_bit -force -file "$PROJ_DIR/sha256_system.xsa"

puts ""
puts "============================================================"
puts " BUILD COMPLETE - $CFG_DESC"
puts ""
puts " Bitstream : $PROJ_DIR/sha256_system.bit"
puts " XSA       : $PROJ_DIR/sha256_system.xsa   <-- import into Vitis"
puts " Summary   : $RPT_DIR/summary.txt"
puts " Addresses : $RPT_DIR/address_map.txt      <-- check against sha256_hw.c"
puts "============================================================"
