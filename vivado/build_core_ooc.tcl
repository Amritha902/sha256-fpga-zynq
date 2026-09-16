#=============================================================================
#  build_core_ooc.tcl  —  out-of-context synthesis of ONE compression core
#
#  THE 2x2 DESIGN-SPACE EXPERIMENT.  This is the script that produces the
#  headline result.
#
#                  U = 1                        U = 2
#      C = 1   A : 66 cyc, depth 1      B : 34 cyc, depth 2
#      C = 2   C : 33 cyc, depth 1      D : 17 cyc, depth 2
#
#  Unroll depth U runs across; interleave depth C runs down.  Measuring both
#  axes independently, from one round module under one constraint set, is
#  what separates this from a benchmark table.
#
#  USAGE
#  -----
#      vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs 0    # Config A
#      vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs 1    # Config B
#      vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs 2    # Config C
#      vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs 3    # Config D
#
#  Then bring reports_ooc/results.csv back and run:
#      python3 scripts/compare_configs.py
#
#  WHY OUT-OF-CONTEXT, NOT THE SYSTEM BUILD
#  ----------------------------------------
#  build_system.tcl embeds the core in a block design with the Zynq PS, an
#  AXI DMA and an interconnect.  The worst path it reports may well sit in
#  the interconnect rather than in the core, in which case the number does
#  not measure what this experiment is about.
#
#  Out-of-context synthesis compiles the core ALONE against a virtual clock.
#  The reported Fmax is then the core's own Fmax, which is precisely the
#  quantity the hypothesis is about.  It is also far quicker, so all four
#  configurations can be rebuilt whenever a constraint changes.
#
#  Keep build_system.tcl for the on-board demo and for whole-system area.
#  Use THIS script for the comparison that goes in the results chapter.
#
#  WHY THE CLOCK TARGET IS DELIBERATELY UNREACHABLE
#  ------------------------------------------------
#  Vivado stops optimising once timing is met.  Constraining at 100 MHz
#  would let all four configurations meet timing with slack to spare, and
#  the reported slack would then reflect where the tool chose to stop, not
#  where each design actually runs out of road.
#
#  So the target below is set aggressively (250 MHz).  All four are
#  expected to MISS it.  That is intended: every configuration is pushed to
#  its own limit under identical pressure, and
#
#      Fmax = 1000 / (period - WNS)
#
#  is then a fair comparison.  A negative WNS here is not a failure -- it is
#  the measurement.  Do not "fix" it by relaxing the constraint, and do not
#  relax it for one configuration only.  That would void the experiment.
#=============================================================================

set CFG 0
if {$argc > 0} { set CFG [lindex $argv 0] }

set PART "xc7z020clg484-1"

# Aggressive target, identical for all four configurations.
set CLK_PERIOD 4.0

switch -- $CFG {
    0 {
        set TOP        "sha256_core_iter"
        set CORE_FILE  "sha256_core_iter.v"
        set CFG_NAME   "A"
        set CFG_DESC   "CONFIG A - U=1, C=1 : iterative baseline"
        set CYC_BLOCK  66.0
        set STREAMS    1
    }
    1 {
        set TOP        "sha256_core_unroll2"
        set CORE_FILE  "sha256_core_unroll2.v"
        set CFG_NAME   "B"
        set CFG_DESC   "CONFIG B - U=2, C=1 : 2x unrolled"
        set CYC_BLOCK  34.0
        set STREAMS    1
    }
    2 {
        set TOP        "sha256_core_cslow2"
        set CORE_FILE  "sha256_core_cslow2.v"
        set CFG_NAME   "C"
        set CFG_DESC   "CONFIG C - U=1, C=2 : 2-message C-slow interleaved"
        set CYC_BLOCK  33.0
        set STREAMS    2
    }
    3 {
        set TOP        "sha256_core_u2c2"
        set CORE_FILE  "sha256_core_u2c2.v"
        set CFG_NAME   "D"
        set CFG_DESC   "CONFIG D - U=2, C=2 : unrolled AND interleaved"
        set CYC_BLOCK  17.0
        set STREAMS    2
    }
    default { error "CFG must be 0 (A), 1 (B), 2 (C) or 3 (D)" }
}

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT       [file dirname $SCRIPT_DIR]
set RTL_DIR    "$ROOT/rtl"
set RPT_DIR    "$ROOT/reports_ooc"
file mkdir $RPT_DIR

puts ""
puts "============================================================"
puts " OUT-OF-CONTEXT CORE BUILD - $CFG_DESC"
puts " Part           : $PART"
puts " Target period  : $CLK_PERIOD ns ([format %.1f [expr {1000.0/$CLK_PERIOD}]] MHz, deliberately tight)"
puts " Expect to MISS it. Negative WNS is the measurement, not a failure."
puts "============================================================"
puts ""

#-----------------------------------------------------------------------------
# Read sources.  sha256_functions.v carries the primitives AND the shared
# sha256_round_comb that all four configurations instantiate.
#-----------------------------------------------------------------------------
read_verilog "$RTL_DIR/sha256_functions.v"
read_verilog "$RTL_DIR/$CORE_FILE"

#-----------------------------------------------------------------------------
# Synthesis.  Identical directive for all four -- this is the whole point.
#-----------------------------------------------------------------------------
puts "\[1/4\] Synthesising $TOP out of context ..."
synth_design -top $TOP -part $PART -mode out_of_context -directive Default

create_clock -name clk -period $CLK_PERIOD [get_ports clk]

# Do not let I/O delays contaminate a core-internal timing question.
set_false_path -from [get_ports rst_n]
set_input_delay  -clock clk 0.0 [all_inputs]  -quiet
set_output_delay -clock clk 0.0 [all_outputs] -quiet
set_false_path -from [all_inputs]  -quiet
set_false_path -to   [all_outputs] -quiet

puts "\[2/4\] Optimising and placing ..."
opt_design
place_design
phys_opt_design

puts "\[3/4\] Routing ..."
route_design

#-----------------------------------------------------------------------------
# Reports
#-----------------------------------------------------------------------------
puts "\[4/4\] Collecting results ..."

report_utilization       -file "$RPT_DIR/util_$CFG_NAME.rpt"
report_timing_summary    -file "$RPT_DIR/timing_$CFG_NAME.rpt"
report_timing -max_paths 10 -nworst 10 -path_type full \
                         -file "$RPT_DIR/paths_$CFG_NAME.rpt"

# Worst register-to-register slack, which for an OOC core with false-pathed
# I/O is the internal critical path -- exactly what we want.
set wns  [get_property SLACK [get_timing_paths -delay_type max]]
set fmax [expr {1000.0 / ($CLK_PERIOD - $wns)}]

set n_lut  [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT}]]
set n_ff   [llength [get_cells -hier -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]
set n_bram [llength [get_cells -hier -filter {PRIMITIVE_GROUP == BLOCKRAM}]]
set n_dsp  [llength [get_cells -hier -filter {PRIMITIVE_GROUP == DSP}]]
set n_carry [llength [get_cells -hier -filter {REF_NAME =~ CARRY*}]]

# Throughput in Mbit/s.  For the interleaved configs, CYC_BLOCK is already
# the EFFECTIVE per-block cost (66/2 for C, 34/2 for D), so one formula
# serves all four.
set thr     [expr {512.0 * $fmax / $CYC_BLOCK}]
set thr_lut [expr {$thr / $n_lut}]

set sfh [open "$RPT_DIR/summary_$CFG_NAME.txt" w]
puts $sfh "============================================================"
puts $sfh " $CFG_DESC   (out-of-context)"
puts $sfh "============================================================"
puts $sfh "Part                      : $PART"
puts $sfh "Constraint period         : $CLK_PERIOD ns (identical for A, B, C and D)"
puts $sfh "Worst negative slack      : [format %.3f $wns] ns"
puts $sfh "Fmax                      : [format %.2f $fmax] MHz"
puts $sfh ""
puts $sfh "Cycles per 512-bit block  : $CYC_BLOCK"
puts $sfh "Message streams in flight : $STREAMS"
puts $sfh "Throughput at Fmax        : [format %.1f $thr] Mbit/s"
puts $sfh ""
puts $sfh "CORE RESOURCES:"
puts $sfh "  LUT                     : $n_lut"
puts $sfh "  FF                      : $n_ff"
puts $sfh "  CARRY                   : $n_carry"
puts $sfh "  BRAM                    : $n_bram"
puts $sfh "  DSP                     : $n_dsp        <-- MUST BE 0"
puts $sfh ""
puts $sfh "Throughput per LUT        : [format %.4f $thr_lut] Mbit/s/LUT"
puts $sfh "    The only fair metric across the grid -- the configs differ in area."
close $sfh

#-----------------------------------------------------------------------------
# Append one row to the shared CSV that compare_configs.py reads.
#-----------------------------------------------------------------------------
set csv "$RPT_DIR/results.csv"
if {![file exists $csv]} {
    set cfh [open $csv w]
    puts $cfh "config,description,part,period_ns,wns_ns,fmax_mhz,cycles_per_block,streams,lut,ff,carry,bram,dsp,throughput_mbps,throughput_per_lut"
    close $cfh
}
set cfh [open $csv a]
puts $cfh "$CFG_NAME,\"$CFG_DESC\",$PART,$CLK_PERIOD,[format %.3f $wns],[format %.2f $fmax],$CYC_BLOCK,$STREAMS,$n_lut,$n_ff,$n_carry,$n_bram,$n_dsp,[format %.1f $thr],[format %.4f $thr_lut]"
close $cfh

puts ""
puts [exec cat "$RPT_DIR/summary_$CFG_NAME.txt"]
puts ""
puts "============================================================"
puts " Row appended to $csv"
puts " When all four configs are built, run:"
puts "     python3 scripts/compare_configs.py"
puts "============================================================"
