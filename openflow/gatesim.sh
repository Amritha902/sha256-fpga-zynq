#!/usr/bin/env bash
#=============================================================================
#  gatesim.sh  —  post-synthesis (gate-level) simulation of every core
#
#  Synthesises each core to Xilinx 7-series primitives (LUT6, CARRY4,
#  FDRE/FDCE ...) with the same Yosys command the open flow uses, writes the
#  netlist back out as Verilog, and runs the existing RTL testbenches against
#  the NETLIST instead of the RTL, using Yosys's Xilinx cell models.
#
#  Passing proves synthesis preserved function: no simulation/synthesis
#  mismatch, no logic optimised away, no X-propagation surprise.
#
#      openflow/gatesim.sh            logs in reports_gatesim/
#=============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
YOSYS="${YOSYS:-yowasp-yosys}"
CELLS="${CELLS:-$(python3 -c 'import yowasp_yosys,os;print(os.path.join(os.path.dirname(yowasp_yosys.__file__),"share/xilinx/cells_sim.v"))')}"
OUT=reports_gatesim
mkdir -p "$OUT"
RTL="rtl/sha256_functions.v rtl/sha256_core_iter.v rtl/sha256_core_unroll2.v \
     rtl/sha256_core_cslow2.v rtl/sha256_core_u2c2.v rtl/sha256_core_unroll2_sched.v"

for TOP in sha256_core_iter sha256_core_unroll2 sha256_core_unroll2_sched \
           sha256_core_cslow2 sha256_core_u2c2; do
    echo "=== synthesise $TOP"
    $YOSYS -q -l "$OUT/synth_$TOP.log" -p "
        read_verilog -sv $RTL
        synth_xilinx -flatten -abc9 -noclkbuf -arch xc7 -top $TOP
        write_verilog -noattr $OUT/net_$TOP.v"
done

IV="iverilog -g2012 -DNO_ICE40_DEFAULT_ASSIGNMENTS"
# RTL primitives (sigma, K ROM) stay RTL: levels 1-2 of tb_sha256 test them
# directly. Every CORE comes from its gate-level netlist. (tb_sha256_soak.v is
# not run here: its trace check probes internal registers by name, which a
# flattened netlist does not keep.)
run() {   # name, testbench, netlists...
    local name=$1 tb=$2; shift 2
    $IV -o "$OUT/$name.vvp" "$CELLS" rtl/sha256_functions.v "$@" "$tb" 2> "$OUT/$name.iverilog.log"
    vvp -n "$OUT/$name.vvp" > "$OUT/$name.log" 2>&1 || true
    printf '%-34s %s\n' "$name" "$(grep -E 'CHECKS RUN' "$OUT/$name.log" | tail -1)"
    rm -f "$OUT/$name.vvp"
}

echo
echo "=== gate-level simulation (netlist under the RTL testbenches)"
run gl_A_B   tb/tb_sha256.v        $OUT/net_sha256_core_iter.v $OUT/net_sha256_core_unroll2.v
sed 's/sha256_core_unroll2 u_unroll/sha256_core_unroll2_sched u_unroll/' tb/tb_sha256.v > "$OUT/tb_sha256_sched.v"
run gl_A_Bs  "$OUT/tb_sha256_sched.v" $OUT/net_sha256_core_iter.v $OUT/net_sha256_core_unroll2_sched.v
run gl_C_D   tb/tb_sha256_cslow.v  $OUT/net_sha256_core_iter.v $OUT/net_sha256_core_unroll2.v \
                                   $OUT/net_sha256_core_cslow2.v $OUT/net_sha256_core_u2c2.v
rm -f "$OUT"/net_*.v "$OUT/tb_sha256_sched.v"            # large; regenerable
