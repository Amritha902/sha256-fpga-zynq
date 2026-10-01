#!/usr/bin/env bash
#=============================================================================
#  build_open.sh  —  the 2x2 experiment with the open-source Xilinx flow
#
#      Yosys (synth_xilinx -arch xc7 -abc9)  ->  nextpnr-xilinx  ->  XC7Z020-1 CLG484
#
#  Stand-in for vivado/build_core_ooc.tcl when Vivado is not available. Same
#  part, same rules: one round module, one harness, one script, one
#  deliberately unreachable 250 MHz target, and every config placed and routed
#  with the same seeds. Writes reports_open/results.csv in the format
#  scripts/compare_configs.py reads.
#
#      openflow/build_open.sh [seed ...]          (default seeds: 1 2 3 4 5)
#
#  Environment (defaults match the cloud setup in openflow/README.md):
#      YOSYS           yosys >= 0.40 (0.33's abc9 aborts on these cores)
#      NEXTPNR_XILINX  nextpnr-xilinx binary
#      CHIPDB          xc7z020.bin built from prjxray-db
#      PINS            prjxray-db .../xc7z020clg484-1/package_pins.csv
#
#  Timing comes from the harness build (ports must sit on real pins); area
#  comes from synthesising the bare core, so the harness registers do not
#  count against any config. Fmax per config is the MEDIAN over seeds, so a
#  lucky placement cannot decide the comparison.
#=============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"                                   # yowasp-yosys only sees the cwd tree
YOSYS="${YOSYS:-yowasp-yosys}"
NPNR="${NEXTPNR_XILINX:-/opt/xc7/nextpnr-xilinx/build/nextpnr-xilinx}"
CHIPDB="${CHIPDB:-/opt/xc7/nextpnr-xilinx/xilinx/xc7z020.bin}"
PINS="${PINS:-/opt/xc7/nextpnr-xilinx/xilinx/external/prjxray-db/zynq7/xc7z020clg484-1/package_pins.csv}"
SEEDS=("$@"); [ ${#SEEDS[@]} -eq 0 ] && SEEDS=(1 2 3 4 5)
FREQ=250
OUT=reports_open
mkdir -p "$OUT"

RTL="rtl/sha256_functions.v rtl/sha256_core_iter.v rtl/sha256_core_unroll2.v \
     rtl/sha256_core_cslow2.v rtl/sha256_core_u2c2.v openflow/ooc_harness.v"
TOPS=(sha256_core_iter sha256_core_unroll2 sha256_core_cslow2 sha256_core_u2c2)
NAMES=(A B C D)

python3 openflow/make_xdc.py "$PINS" > "$OUT/pins.xdc"

for CFG in 0 1 2 3; do
    N=${NAMES[$CFG]}
    echo "=== Config $N: area synthesis of the bare core (${TOPS[$CFG]})"
    $YOSYS -q -l "$OUT/area_$N.log" -p "
        read_verilog -sv $RTL
        synth_xilinx -flatten -abc9 -arch xc7 -top ${TOPS[$CFG]}
        tee -q -o $OUT/area_$N.txt stat"

    echo "=== Config $N: timing synthesis inside the harness"
    $YOSYS -q -l "$OUT/synth_$N.log" -p "
        read_verilog -sv $RTL
        chparam -set CFG $CFG ooc_harness
        synth_xilinx -flatten -abc9 -arch xc7 -top ooc_harness
        write_json $OUT/cfg_$N.json"

    for S in "${SEEDS[@]}"; do
        "$NPNR" --chipdb "$CHIPDB" --xdc "$OUT/pins.xdc" --json "$OUT/cfg_$N.json" \
            --freq $FREQ --timing-allow-fail --seed "$S" \
            --report "$OUT/pnr_${N}_s$S.json" > "$OUT/pnr_${N}_s$S.log" 2>&1
        printf '    seed %-3s %s\n' "$S" "$(grep 'Max frequency' "$OUT/pnr_${N}_s$S.log" | tail -1 | sed 's/.*: //')"
    done
    rm -f "$OUT/cfg_$N.json"                 # large netlist; regenerable
done

python3 openflow/collect_results.py "$OUT" "${SEEDS[@]}"
python3 scripts/compare_configs.py "$OUT/results.csv"
