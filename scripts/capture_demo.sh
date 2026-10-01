#!/usr/bin/env bash
# capture_demo.sh -- re-run every verification step and capture its output for
# scripts/make_demo_video.py.   scripts/capture_demo.sh [out_dir]
cd "$(dirname "$0")/.."; OUT=${1:-/tmp/demo/cap}; mkdir -p "$OUT"
cap() { local f=$1; shift; { echo "\$ $*"; eval "$@" 2>&1; } > $OUT/$f.txt; }
cap 01_rtl        "make clean >/dev/null; make all sched 2>&1 | grep -E 'VERIFICATION|CHECKS RUN|RESULT|PASS\]  SHA|Config A :|Config B :|cross-validation|ALL VERIFICATION'"
cap 02_formal     "make formal 2>&1 | grep -v 'Replacing memory'"
cap 03_gatesim    "openflow/gatesim.sh 2>&1 | grep -v 'Replacing memory'"
mkdir -p demo_tmp
cap 04_pnr        "yowasp-yosys -q -p 'read_verilog -sv rtl/sha256_functions.v rtl/sha256_core_iter.v rtl/sha256_core_unroll2.v rtl/sha256_core_cslow2.v rtl/sha256_core_u2c2.v rtl/sha256_core_unroll2_sched.v openflow/ooc_harness.v; chparam -set CFG 1 ooc_harness; synth_xilinx -flatten -abc9 -arch xc7 -top ooc_harness; write_json demo_tmp/b.json' 2>&1 | grep -v 'Replacing memory'; /opt/xc7/nextpnr-xilinx/build/nextpnr-xilinx --chipdb /opt/xc7/nextpnr-xilinx/xilinx/xc7z020.bin --xdc reports_open/pins.xdc --json demo_tmp/b.json --freq 250 --timing-allow-fail --seed 1 2>&1 | grep -E 'Logic utilisation|SLICE_LUTX|CARRY4|Placed|Routing complete|Max frequency' | tail -8"
rm -rf demo_tmp
cap 05_compare    "python3 scripts/compare_configs.py reports_open/results.csv 2>&1 | sed -n '1,40p'; python3 openflow/compare_sched.py reports_open/results.csv"
cap 06_spice      "python3 spice/gen_round_delay.py --verify 2>&1 | tail -12; echo; echo '\$ cat reports_ooc/round_path_delay.csv'; cat reports_ooc/round_path_delay.csv"
cap 07_cosim      "cosim/run_cosim.sh 2>&1"
cap 07b_uart      "cat reports_cosim/board_C.log"
cap 08_arm        "for f in main sha256_hw sha256_pair sha256_sw; do arm-none-eabi-gcc -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -O2 -Wall -Wextra -Werror -Icosim/bsp -Isw -c sw/\$f.c -o /tmp/\$f.o && echo \"  sw/\$f.c  OK\"; done; arm-none-eabi-size /tmp/main.o /tmp/sha256_hw.o /tmp/sha256_pair.o /tmp/sha256_sw.o"
echo CAPTURE_DONE
