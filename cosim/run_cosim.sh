#!/usr/bin/env bash
#=============================================================================
#  run_cosim.sh  —  virtual board bring-up for all four configurations
#
#  Builds sha256_top with CORE_SELECT = 0..3 under Verilator, links the
#  unmodified bare-metal program from sw/ against the stub BSP in
#  cosim/bsp/, and runs it. The interactive test is fed "abc" then a blank
#  line, as a user at the UART would type.
#
#      cosim/run_cosim.sh            all four configs, logs in reports_cosim/
#=============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/reports_cosim"
mkdir -p "$OUT"
NAMES=(A B C D)
SYS_RTL="rtl/sha256_functions.v rtl/sha256_core_iter.v rtl/sha256_core_unroll2.v \
         rtl/sha256_core_cslow2.v rtl/sha256_core_u2c2.v rtl/sha256_axi_lite_regs.v \
         rtl/sha256_axis_wrapper.v rtl/sha256_axis_wrapper_dual.v rtl/sha256_top.v"
CFLAGS="-O2 -I$ROOT/cosim/bsp -I$ROOT/sw"

status=0
for SEL in 0 1 2 3; do
    N=${NAMES[$SEL]}
    B="$OUT/obj_$N"
    rm -rf "$B"; mkdir -p "$B"
    # the board program, compiled as C exactly as the Vitis BSP would
    gcc $CFLAGS -Dmain=board_main -c "$ROOT/sw/main.c"       -o "$B/main.o"
    gcc $CFLAGS                   -c "$ROOT/sw/sha256_hw.c"  -o "$B/sha256_hw.o"
    gcc $CFLAGS                   -c "$ROOT/sw/sha256_pair.c" -o "$B/sha256_pair.o"
    gcc $CFLAGS                   -c "$ROOT/sw/sha256_sw.c"  -o "$B/sha256_sw.o"
    (cd "$ROOT" && verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-lint -Wno-style \
        --top-module sha256_top -GCORE_SELECT=$SEL --Mdir "$B/v" \
        -CFLAGS "-I$ROOT/cosim/bsp" \
        $SYS_RTL "$ROOT/cosim/sim_main.cpp" \
        "$B/main.o" "$B/sha256_hw.o" "$B/sha256_pair.o" "$B/sha256_sw.o" > "$B/verilator.log" 2>&1)
    echo "=== Config $N (CORE_SELECT=$SEL)"
    if printf 'abc\n\n' | "$B/v/Vsha256_top" > "$OUT/board_$N.log" 2>&1; then
        grep -E "ALL CONFORMANCE|FAILURE|cycles = |PASS|FAIL|accelerator cycles|board_main returned" "$OUT/board_$N.log" | sed 's/^/    /'
    else
        echo "    RUN FAILED (see $OUT/board_$N.log)"; status=1
    fi
    rm -rf "$B"
done
exit $status
