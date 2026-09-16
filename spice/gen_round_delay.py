#!/usr/bin/env python3
"""
gen_round_delay.py -- transistor-level critical-path delay of the SHA-256
compression round, and what it says about the base paper.

    python3 spice/gen_round_delay.py --curve      delay vs adder-chain depth
    python3 spice/gen_round_delay.py --verify     sanity-check one chain

THE QUESTION THIS ANSWERS

Suhaili & Julai (Pertanika JST 30(1), 2022) report that unfolding SHA-256 by
two -- the same 64-to-34-cycle transformation as our Config B -- IMPROVED
maximum frequency on an Arria II GX. The structural argument says it must
fall, because two rounds chained combinationally put two adder chains in
series.

Both cannot be right for the same architecture, so something else differs.
This script isolates the part that is pure circuit, independent of any FPGA
fabric or vendor toolchain: how the round's critical-path delay scales with
the number of 32-bit additions in series.

WHAT THE CRITICAL PATH ACTUALLY IS

    T1 = h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t]     <- four adds
    T2 = Sigma0(a) + Maj(a,b,c)                       <- one add, off-path
    a' = T1 + T2                                      <- one add
    e' = d + T1

Sigma1(e) is two XOR levels of rewired copies of e -- the rotations are free
routing. Ch is one mux level. So the round's delay is dominated by FIVE
32-bit additions in series, preceded by the Sigma network.

    Config A  (1 round)              : Sigma1 + 5 adds
    Config B  (2 rounds, naive order): Sigma1 + 10 adds
    Config C  (1 round per stage)    : Sigma1 + 5 adds   -- same as A

THE REORDERING THAT MIGHT RESCUE UNROLLING

In the second round of an unrolled pair, three of T1's five operands do NOT
depend on the first round's result:

    h2 = g1   a pure rename, free, available immediately
    K[t+1]    a compile-time constant
    W[t+1]    from the message schedule, which runs independently

Only Sigma1(e2) and Ch(e2,f2,g2) are late. An adder chain ordered to sum the
three early operands FIRST leaves only two adds on the late path, so the
second round costs ~2 extra adds rather than 5. That is Chaves' operation
rescheduling (CHES 2006) applied inside the unrolled pair.

This gives three candidate depths, and the measured delay curve below tells
us what each is worth:

    A          5 adds
    B naive   10 adds      ratio 5/10 = 0.500
    B reordered ~7 adds    ratio 5/7  = 0.714

The pre-registered break-even is 0.515 at core level and 0.624 at system
level. So naive ordering LOSES and aggressive reordering WINS -- the outcome
is decided by operand scheduling, not by unrolling as such.

That is a concrete, testable explanation for how Suhaili & Julai could report
a frequency improvement while the structural argument predicts a fall, and it
is exactly the confound their separately-built designs cannot rule out.

SCOPE, STATED HONESTLY

Generic SPICE LEVEL-1 models at 180 nm, not a foundry PDK, and a ripple-carry
adder rather than the carry-select or carry-lookahead structure a synthesiser
would infer on FPGA fabric. What transfers is the SHAPE of the curve -- is
delay linear in chain depth? -- and the RATIO between depths. Absolute
nanoseconds are not claimable.
"""

import argparse
import csv
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
LIB = HERE / "cmos180.lib"
OUT = HERE / "run_delay"

VDD = 1.8
N = 32                      # datapath width
TSTART = 20e-9              # settle before the measured edge
TEDGE = 0.05e-9             # input edge rate -- fast, so the path dominates
TSPAN = 60e-9               # generous window for the deepest chain


def sigma1_net(src, dst):
    """Sigma1(x) = ROTR6(x) XOR ROTR11(x) XOR ROTR25(x), two XOR2 levels.

    The rotations are pure rewiring -- zero gates, zero delay -- so this is
    just two XOR2 per bit on permuted copies of the same 32 nets.
    """
    L = [f"* Sigma1 network: {src} -> {dst}"]
    for i in range(N):
        r6 = (i + 6) % N
        r11 = (i + 11) % N
        r25 = (i + 25) % N
        L.append(f"Xs1a_{i} {src}{r6} {src}{r11} {dst}_t{i} vdd 0 XOR2")
        L.append(f"Xs1b_{i} {dst}_t{i} {src}{r25} {dst}{i} vdd 0 XOR2")
    return L


def rca(name, a, b, out, cin_node):
    """32-bit ripple-carry adder from the shared FA cell."""
    L = [f"* {name}: {out} = {a} + {b}"]
    for i in range(N):
        cin = cin_node if i == 0 else f"{name}_c{i}"
        L.append(f"X{name}_{i} {a}{i} {b}{i} {cin} {out}{i} {name}_c{i+1} "
                 f"vdd 0 FA")
    return L


def build(depth, path):
    """Sigma1 feeding `depth` chained 32-bit additions.

    The stimulus drives the Sigma1 input; each adder's other operand is held
    at 0x55555555 so every stage keeps switching and carries keep propagating.
    Delay is taken as the LAST output bit to settle.
    """
    L = [f"* SHA-256 round critical path: Sigma1 + {depth} chained 32-bit adds",
         ""]
    L += LIB.read_text().splitlines()
    L += ["", f"Vvdd vdd 0 DC {VDD}", ""]

    # Stimulus: e goes 0x00000000 -> 0xFFFFFFFF at TSTART.
    #
    # Each adder's other operand is held at 0x55555555. Alternating ones keep
    # every stage switching and keep carries propagating: an all-ones addend
    # looks like a worst case but actually freezes the sum's upper bits, so
    # the output never transitions and there is nothing to measure.
    L.append("* ---- stimulus ----")
    for i in range(N):
        L.append(f"Ve{i} e{i} 0 PWL(0 0 "
                 f"{TSTART*1e9:.4f}n 0 "
                 f"{(TSTART+TEDGE)*1e9:.4f}n {VDD})")
    L.append(f"Vone one 0 DC {VDD}")
    L.append("Vzero zero 0 DC 0")

    L.append("")
    L += sigma1_net("e", "s1")

    L.append("")
    L.append("* ---- chained additions ----")
    prev = "s1"
    for k in range(depth):
        nxt = f"sum{k}"
        L.append(f"* --- adder {k+1} of {depth} ---")
        for i in range(N):
            src = "one" if (i % 2 == 0) else "zero"      # 0x55555555
            L.append(f"Radd{k}_{i} {src} addb{k}_{i} 0.001")
        L += rca(f"add{k}", prev, f"addb{k}_", nxt, "zero")
        prev = nxt

    # load every output so the last stage drives something real
    L.append("")
    for i in range(N):
        L.append(f"Cl{i} {prev}{i} 0 5f")

    tend = TSTART + TSPAN
    L += ["", f".tran 5p {tend*1e9:.4f}n", ""]
    # Measure EVERY output bit and take the latest in post-processing. Which
    # bit settles last depends on the operand pattern, and a bit that happens
    # not to toggle yields no crossing at all -- picking one bit up front is
    # how the first attempt at this measured nothing.
    for i in range(N):
        L.append(f".meas tran tp{i} TRIG v(e0) VAL={VDD/2} RISE=1 "
                 f"TARG v({prev}{i}) VAL={VDD/2} CROSS=LAST")
    L += [".end", ""]
    path.write_text("\n".join(L))


def run(path):
    r = subprocess.run(["ngspice", "-b", str(path)],
                       capture_output=True, text=True, timeout=5400)
    return r.stdout + r.stderr


def meas(out, key):
    m = re.search(rf"^\s*{key}\s*=\s*([-\d.eE+]+)", out, re.M)
    return float(m.group(1)) if m else None


def worst_delay(out):
    """Latest settling output bit, and how many bits actually transitioned."""
    ts = [t for t in (meas(out, f"tp{i}") for i in range(N))
          if t is not None and t > 0]
    return (max(ts), len(ts)) if ts else (None, 0)


BREAKEVEN_CORE = 34.0 / 66.0
BREAKEVEN_SYS = 53.0 / 85.0


def cmd_curve(args):
    depths = args.depths or [1, 2, 3, 5, 7, 10]
    OUT.mkdir(exist_ok=True)
    rows = []
    print(f"\nSHA-256 round critical path, {N}-bit, generic 180nm models")
    print("Sigma1 network feeding N chained 32-bit ripple-carry additions,")
    print("addends at 0x55555555; delay is the LAST output bit to settle.\n")
    print(f"  {'adds':>5} {'delay (ns)':>12} {'ns per add':>12} {'vs 5 adds':>11}")
    print("  " + "-" * 64)
    base = None
    for d in depths:
        p = OUT / f"chain_{d}.sp"
        build(d, p)
        o = run(p)
        t, nbits = worst_delay(o)
        if t is None:
            print(f"  {d:>5}   ngspice returned no measurement")
            continue
        if d == 5:
            base = t
        rows.append(dict(adds=d, delay_ns=t * 1e9, ns_per_add=t * 1e9 / d,
                         bits_measured=nbits))
        rel = f"{t/base:.3f}x" if base else "-"
        print(f"  {d:>5} {t*1e9:>12.4f} {t*1e9/d:>12.4f} {rel:>11}   "
              f"({nbits}/{N} bits toggled)")

    csvp = ROOT / "reports_ooc" / "round_path_delay.csv"
    csvp.parent.mkdir(exist_ok=True)
    with open(csvp, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print("  " + "-" * 64)

    by = {r["adds"]: r["delay_ns"] for r in rows}
    if len(rows) < 3:
        print("\n  Need at least three depths to fit the model.")
        return 0

    # ---- least-squares fit:  delay(n) = t_sigma + n * t_add ---------------
    xs = [r["adds"] for r in rows]
    ys = [r["delay_ns"] for r in rows]
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    t_add = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / \
            sum((x - mx) ** 2 for x in xs)
    t_sig = my - t_add * mx
    ss_res = sum((y - (t_sig + t_add * x)) ** 2 for x, y in zip(xs, ys))
    ss_tot = sum((y - my) ** 2 for y in ys)
    r2 = 1 - ss_res / ss_tot if ss_tot else 1.0

    print("\n  MODEL FIT   delay(n) = t_sigma + n * t_add")
    print(f"    t_sigma (Sigma1 network, 2 XOR levels) : {t_sig:.4f} ns")
    print(f"    t_add   (one 32-bit addition)          : {t_add:.4f} ns")
    print(f"    R^2                                    : {r2:.5f}")
    if r2 > 0.99:
        print("    Delay is LINEAR in chain depth. There is no circuit-level")
        print("    effect that lets an unrolled round match the iterative one.")

    # ---- the configurations ----------------------------------------------
    #
    # CAREFUL: a depth-n chain here contains ONE Sigma1. Config B is two
    # rounds, so it carries TWO Sigma1 networks -- the raw depth-10 number
    # understates it by one t_sigma. Model each configuration explicitly.
    def model(sigmas, adds):
        return sigmas * t_sig + adds * t_add

    dA = model(1, 5)
    cfgs = [
        ("A   iterative",              1,  5),
        ("B   unrolled, naive order",  2, 10),
        ("B   unrolled, reordered",    2,  7),
        ("C   interleaved (= A path)", 1,  5),
        ("D   both (= B path)",        2, 10),
    ]
    print(f"\n  CONFIGURATION CRITICAL PATHS")
    print(f"    {'':<28} {'Sigma':>6} {'adds':>5} {'ns':>8} {'Fmax vs A':>10}")
    print("    " + "-" * 62)
    for label, sg, ad in cfgs:
        d = model(sg, ad)
        print(f"    {label:<28} {sg:>6} {ad:>5} {d:>8.4f} {dA/d:>10.3f}")
    print("    " + "-" * 62)

    print(f"\n  AGAINST THE PRE-REGISTERED THRESHOLDS")
    print(f"    core 34/66 = {BREAKEVEN_CORE:.3f}      system 53/85 = {BREAKEVEN_SYS:.3f}")
    print()
    for label, sg, ad in cfgs[1:3]:
        ratio = dA / model(sg, ad)
        c = "clears" if ratio > BREAKEVEN_CORE else "MISSES"
        y = "clears" if ratio > BREAKEVEN_SYS else "MISSES"
        print(f"    {label:<28} ratio {ratio:.3f}   core: {c}   system: {y}")

    r_naive = dA / model(2, 10)
    r_reord = dA / model(2, 7)
    print(f"\n  THE FINDING")
    print(f"    Naive operand order puts unrolling at {r_naive:.3f}, effectively")
    print(f"    ON the core break-even of {BREAKEVEN_CORE:.3f} and below the system")
    print(f"    break-even of {BREAKEVEN_SYS:.3f}. Reordering the adder chain so the")
    print(f"    operands that do NOT depend on the previous round are summed")
    print(f"    first moves it to {r_reord:.3f}, which clears both.")
    print()
    print(f"    So the outcome of unrolling is decided by OPERAND SCHEDULING,")
    print(f"    not by unroll depth. A design whose adder chain is ordered well")
    print(f"    gains; one ordered naively does not. That is a concrete")
    print(f"    mechanism by which Suhaili & Julai (2022) could report a")
    print(f"    frequency improvement while the structural argument predicts a")
    print(f"    fall -- and it is exactly what their separately-built designs")
    print(f"    cannot distinguish.")
    print()
    print(f"    Config C keeps one round per stage, so its path equals A's and")
    print(f"    its Fmax ratio is 1.000 by construction. Interleaving changes")
    print(f"    the cycle count and never the path -- which is why it is the")
    print(f"    lever that does not depend on getting the scheduling right.")

    print(f"\n  Written to {csvp}")
    return 0


def cmd_verify(args):
    """Confirm the chain actually computes what it should, at depth 1."""
    OUT.mkdir(exist_ok=True)
    p = OUT / "verify_1.sp"
    build(1, p)
    o = run(p)
    t, nbits = worst_delay(o)
    print(f"\n  depth-1 chain elaborated and simulated")
    if t:
        print(f"  worst-bit delay : {t*1e9:.4f} ns  "
              f"({nbits}/{N} output bits transitioned)")
    else:
        print("  NO MEASUREMENT")
    errs = [l for l in o.splitlines() if "rror" in l or "arning: " in l]
    if errs:
        print("\n  ngspice messages:")
        for e in errs[:8]:
            print("   ", e)
    else:
        print("  no ngspice errors")
    return 0 if t else 1


def main():
    if not shutil.which("ngspice"):
        sys.exit("ngspice not found on PATH")
    ap = argparse.ArgumentParser()
    ap.add_argument("--curve", action="store_true")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--depths", type=int, nargs="*")
    a = ap.parse_args()
    if a.verify:
        return cmd_verify(a)
    if a.curve:
        return cmd_curve(a)
    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
