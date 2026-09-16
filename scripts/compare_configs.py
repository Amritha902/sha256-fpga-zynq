#!/usr/bin/env python3
"""
compare_configs.py -- the 2x2 design-space result.

Reads reports_ooc/results.csv, written one row per configuration by
vivado/build_core_ooc.tcl.

                U = 1                      U = 2
    C = 1   A : 66 cyc, depth 1     B : 34 cyc, depth 2
    C = 2   C : 33 cyc, depth 1     D : 17 cyc, depth 2

WHAT IT TESTS

  Across a row (unroll depth):  halves the cycle count, DOUBLES the
  combinational depth.  Frequency must be paid.  Whether the trade is
  profitable is the pre-registered, falsifiable question -- Config B clears
  its threshold or it does not.

  Down a column (interleave depth):  halves the effective cycle count and
  leaves combinational depth UNTOUCHED.  Frequency should be preserved.

  The orthogonality claim is that these two axes are independent: the
  column ratio C/A should equal the column ratio D/B, and both should be
  close to 2.00 regardless of what the row does.  That is the finding.

    python3 scripts/compare_configs.py [path/to/results.csv]
"""

import csv
import sys
from pathlib import Path

CORE_BREAKEVEN = 34.0 / 66.0      # 0.5152 -- Config B at core level
SYS_BREAKEVEN = 53.0 / 85.0       # 0.6235 -- Config B with AXI streaming overhead

# Measured system-level cycles per block over the real AXI path. The dual
# configs retire two blocks per pass, so their streaming overhead amortises.
SYS_CYCLES = {"A": 85.0, "B": 53.0, "C": 51.0, "D": 35.0}

GRID = {"A": (1, 1), "B": (2, 1), "C": (1, 2), "D": (2, 2)}
DEPTH = {"A": 1, "B": 2, "C": 1, "D": 2}     # combinational depth, in rounds


def load(path):
    with open(path, newline="") as fh:
        rows = list(csv.DictReader(fh))
    latest = {}
    for r in rows:                 # a rebuild supersedes an earlier run
        latest[r["config"]] = r
    return latest


def f(row, key):
    return float(row[key])


def rule(ch="-", n=78):
    print(ch * n)


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("reports_ooc/results.csv")
    if not path.exists():
        sys.exit(
            f"No results at {path}\n\nRun the four OOC builds first:\n"
            + "\n".join(
                f"  vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs {i}"
                for i in range(4)
            )
        )

    cfg = load(path)
    missing = [c for c in "ABCD" if c not in cfg]

    print()
    rule("=")
    print(" SHA-256 2x2 DESIGN SPACE -- post-route, out of context")
    rule("=")
    if missing:
        print(f" WARNING: missing configuration(s): {', '.join(missing)}. Partial results.")
        rule()

    # ---- measurement table ------------------------------------------------
    print()
    print(f" {'':<3} {'U':>2} {'C':>2} {'depth':>6} {'Fmax':>9} {'cyc/blk':>8} "
          f"{'LUT':>7} {'FF':>7} {'DSP':>4} {'Mbit/s':>10} {'Mb/s/LUT':>9}")
    rule()
    for c in "ABCD":
        if c not in cfg:
            continue
        r, (u, i) = cfg[c], GRID[c]
        print(f" {c:<3} {u:>2} {i:>2} {DEPTH[c]:>6} {f(r,'fmax_mhz'):>9.2f} "
              f"{f(r,'cycles_per_block'):>8.0f} {int(r['lut']):>7} {int(r['ff']):>7} "
              f"{int(r['dsp']):>4} {f(r,'throughput_mbps'):>10.1f} "
              f"{f(r,'throughput_per_lut'):>9.4f}")
    rule()

    for c in "ABCD":
        if c in cfg and int(cfg[c]["dsp"]) != 0:
            print(f" ** Config {c} reports {cfg[c]['dsp']} DSP. Expected 0 -- SHA-256 has")
            print("    no multiplication. Investigate before reporting.")

    if "A" not in cfg:
        print("\n Config A is the baseline; nothing can be evaluated without it.")
        return

    fa, ta = f(cfg["A"], "fmax_mhz"), f(cfg["A"], "throughput_mbps")

    # ---- ROW: unrolling, the falsifiable prediction -----------------------
    if "B" in cfg:
        fb, tb = f(cfg["B"], "fmax_mhz"), f(cfg["B"], "throughput_mbps")
        ratio = fb / fa
        print()
        rule("=")
        print(" ACROSS THE ROW -- unrolling (the pre-registered prediction)")
        rule("=")
        print(f"   Fmax(B)/Fmax(A) = {fb:.2f}/{fa:.2f} = {ratio:.4f}")
        print(f"   Core break-even (34/66)   = {CORE_BREAKEVEN:.4f}")
        print(f"   System break-even (53/85) = {SYS_BREAKEVEN:.4f}")
        print()
        if ratio > SYS_BREAKEVEN:
            print(f"   VERDICT: clears BOTH thresholds. Unrolling is a net win.")
            print(f"            {tb/ta:.2f}x throughput over baseline.")
        elif ratio > CORE_BREAKEVEN:
            print(f"   VERDICT: clears the core threshold but NOT the system one.")
            print(f"            Unrolling pays for the bare core and is cancelled by")
            print(f"            the fixed 19-cycle AXI overhead once integrated.")
        else:
            print(f"   VERDICT: BELOW threshold. Unrolling is a NET LOSS here.")
            print(f"            The stated falsifiable outcome. Valid finding, not failure.")
        print()
        print(f"   Suhaili & Julai (2022) report unfolding-2 IMPROVING Fmax on")
        print(f"   Arria II GX. That result does "
              f"{'REPRODUCE' if ratio >= 1.0 else 'NOT reproduce'} on Zynq-7020 "
              f"(ratio {ratio:.3f}).")

    # ---- COLUMNS: interleaving, the structural prediction ------------------
    cols = []
    if "C" in cfg:
        cols.append(("A", "C"))
    if "B" in cfg and "D" in cfg:
        cols.append(("B", "D"))

    if cols:
        print()
        rule("=")
        print(" DOWN THE COLUMNS -- interleaving (the structural prediction)")
        rule("=")
        print("   Combinational depth is unchanged down a column, so Fmax should")
        print("   hold and throughput should roughly double.")
        print()
        for base, inter in cols:
            fr = f(cfg[inter], "fmax_mhz") / f(cfg[base], "fmax_mhz")
            tr = f(cfg[inter], "throughput_mbps") / f(cfg[base], "throughput_mbps")
            flag = "" if tr > 1.0 else "   <-- UNEXPECTED"
            print(f"   {base} -> {inter}   Fmax ratio {fr:5.3f}   "
                  f"throughput {tr:5.2f}x{flag}")
        print()
        bad = [f"{b}->{i}" for b, i in cols
               if f(cfg[i], "throughput_mbps") <= f(cfg[b], "throughput_mbps")]
        if bad:
            print(f"   {', '.join(bad)} lost throughput. This should not happen --")
            print("   same depth, half the effective cycles. Check the pipeline")
            print("   register was not retimed away and both builds used the same")
            print("   directive. A loss here is a BUILD problem, not a refutation.")
        else:
            print("   Both columns gained, as predicted.")

    # ---- ORTHOGONALITY : the actual claim ---------------------------------
    if all(c in cfg for c in "ABCD"):
        ca = f(cfg["C"], "throughput_mbps") / f(cfg["A"], "throughput_mbps")
        db = f(cfg["D"], "throughput_mbps") / f(cfg["B"], "throughput_mbps")
        ba = f(cfg["B"], "throughput_mbps") / f(cfg["A"], "throughput_mbps")
        dc = f(cfg["D"], "throughput_mbps") / f(cfg["C"], "throughput_mbps")

        print()
        rule("=")
        print(" ORTHOGONALITY -- the claim")
        rule("=")
        print(f"   Interleave gain at U=1 (A->C) : {ca:.3f}x")
        print(f"   Interleave gain at U=2 (B->D) : {db:.3f}x")
        spread_i = abs(ca - db) / max(ca, db) * 100
        print(f"   Spread                        : {spread_i:.1f}%")
        print()
        print(f"   Unroll gain at C=1 (A->B)     : {ba:.3f}x")
        print(f"   Unroll gain at C=2 (C->D)     : {dc:.3f}x")
        spread_u = abs(ba - dc) / max(ba, dc) * 100
        print(f"   Spread                        : {spread_u:.1f}%")
        print()
        if spread_i < 10 and spread_u < 10:
            print("   CONFIRMED: the two axes are independent. The interleave gain")
            print("   does not depend on unroll depth, and vice versa. Unrolling is")
            print("   a gamble on the device; interleaving is a guaranteed linear")
            print("   area-for-throughput trade that holds at any unroll depth.")
        else:
            print("   NOT CLEAN: the axes interact. Most likely cause is routing")
            print("   congestion in Config D, which is the largest core. Check its")
            print("   utilisation and congestion report before interpreting -- an")
            print("   interaction that only appears in the biggest design is a")
            print("   placement effect, not an architectural one.")

        # ---- headline ------------------------------------------------------
        print()
        rule("=")
        print(" HEADLINE")
        rule("=")
        best = max("ABCD", key=lambda c: f(cfg[c], "throughput_mbps"))
        best_pl = max("ABCD", key=lambda c: f(cfg[c], "throughput_per_lut"))
        print(f"   Highest throughput     : Config {best} "
              f"({f(cfg[best],'throughput_mbps'):.1f} Mbit/s)")
        print(f"   Best throughput/LUT    : Config {best_pl} "
              f"({f(cfg[best_pl],'throughput_per_lut'):.4f} Mbit/s/LUT)")
        print()
        print(f"   Area ladder : " + "  ".join(
            f"{c} {int(cfg[c]['lut'])}" for c in "ABCD") + "  LUT")
        print()
        print("   State the caveat: C and D need INDEPENDENT messages. Single-")
        print("   message latency is 66 cycles for C and 34 for D -- no better")
        print("   than A and B respectively.")

    # ---- system-level projection ------------------------------------------
    if "A" in cfg:
        print()
        rule("=")
        print(" SYSTEM LEVEL -- using measured AXI cycle counts")
        rule("=")
        print("   Core Fmax applied to the measured system cycles per block.")
        print()
        print(f"   {'':<4} {'sys cyc':>8} {'Mbit/s':>10} {'vs A':>7} {'break-even vs A':>17}")
        rule()
        for c in "ABCD":
            if c not in cfg:
                continue
            thr = 512.0 * f(cfg[c], "fmax_mhz") / SYS_CYCLES[c]
            base = 512.0 * fa / SYS_CYCLES["A"]
            be = SYS_CYCLES[c] / SYS_CYCLES["A"]
            print(f"   {c:<4} {SYS_CYCLES[c]:>8.0f} {thr:>10.1f} {thr/base:>6.2f}x "
                  f"{('baseline' if c == 'A' else f'{be:.3f}'):>17}")
        rule()
        print("   C needs 51 system cycles per block against B's 53, so C beats B")
        print("   on cycle count as well as on combinational depth.")

    print()
    rule("=")
    print()


if __name__ == "__main__":
    main()
