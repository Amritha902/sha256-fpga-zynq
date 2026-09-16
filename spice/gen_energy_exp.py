#!/usr/bin/env python3
"""
gen_energy_exp.py -- transistor-level energy comparison of an N-bit adder
with and without operand-dependent bypass.

    python3 spice/gen_energy_exp.py --check          functional check, 8-bit
    python3 spice/gen_energy_exp.py --sweep          energy vs zero-fraction
    python3 spice/gen_energy_exp.py --sha            zero-operand statistics
    python3 spice/gen_energy_exp.py --sha-spice      REAL SHA-256 operands
                                                     driven through the netlist

WHAT IS BEING COMPARED
    baseline : N-bit ripple-carry adder, plain.
    bypass   : the SAME adder, wrapped in
                 - a zero-detect reduction tree on operand B
                 - AND-gate operand isolation on BOTH operands
                 - a 2:1 output mux that passes A through when B == 0
               This is the favourable, standard form of the technique --
               what a synthesis tool inserts for operand isolation. If it
               does not pay in this form, it does not pay.

WHAT COMES OUT
    Energy per addition for each design, as a function of the fraction of
    additions whose B operand is zero. The crossing point is the break-even
    zero-fraction: below it the bypass logic costs more than it saves.

Both designs instantiate the identical FA cell from cmos180.lib, so model
error is common-mode and the RATIO is the meaningful output. Absolute
joules are not claimable -- see the header of cmos180.lib.
"""

import argparse
import csv
import random
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
LIB = HERE / "cmos180.lib"
OUT = HERE / "run"

VDD = 1.8
TR = 0.1e-9          # input edge rate
TP = 8.0e-9          # vector period -- long enough for the RCA to settle
TSETTLE = 20e-9      # initial settling before energy accounting starts


# ---------------------------------------------------------------------------
# netlist construction
# ---------------------------------------------------------------------------
def zero_detect(prefix, bits, out_node):
    """Alternating NOR2/NAND2 reduction tree.

    NOR2 of two active-high 'all zero' flags is wrong, so the polarity
    alternates: NOR2 produces active-high 'all zero', NAND2 of two
    active-high flags produces active-low, NOR2 of two active-low produces
    active-high again, and so on. Requires a power-of-two width.
    """
    lines, level, idx = [], list(bits), 0
    active_high = False          # raw bits: a '1' means nonzero
    while len(level) > 1:
        nxt = []
        for i in range(0, len(level), 2):
            node = f"{prefix}_l{idx}_{i//2}"
            gate = "NOR2" if not active_high else "NAND2"
            lines.append(f"X{prefix}_{idx}_{i//2} {level[i]} {level[i+1]} {node} vdd 0 {gate}")
            nxt.append(node)
        active_high = not active_high
        level, idx = nxt, idx + 1
    # active_high now says whether level[0] is already an active-high
    # "operand is all zero" flag. If it is, buffer it; if not, invert it.
    if active_high:
        lines.append(f"X{prefix}_buf1 {level[0]} {prefix}_nb vdd 0 INV")
        lines.append(f"X{prefix}_buf2 {prefix}_nb {out_node} vdd 0 INV")
    else:
        lines.append(f"X{prefix}_final {level[0]} {out_node} vdd 0 INV")
    return lines


def build_adder(n, bypass):
    """Return netlist lines for the DUT. Ports: a<i>, b<i> in; y<i> out."""
    L = []
    if bypass:
        L += ["* ---- zero detect on operand B ----"]
        L += zero_detect("zd", [f"b{i}" for i in range(n)], "zflag")
        L += ["Xzb zflag zflagb vdd 0 INV",
              "* ---- operand isolation: hold both operands at 0 when B==0 ----"]
        for i in range(n):
            L.append(f"Xiso_a{i} a{i} zflagb ag{i} vdd 0 AND2")
            L.append(f"Xiso_b{i} b{i} zflagb bg{i} vdd 0 AND2")
        ain, bin_ = "ag", "bg"
    else:
        ain, bin_ = "a", "b"

    L.append("* ---- ripple-carry adder ----")
    L.append("Vcin cin0 0 DC 0")
    for i in range(n):
        cin = "cin0" if i == 0 else f"c{i}"
        sout = f"s{i}" if bypass else f"y{i}"
        L.append(f"Xfa{i} {ain}{i} {bin_}{i} {cin} {sout} c{i+1} vdd 0 FA")

    if bypass:
        L.append("* ---- output mux: pass A through when B==0 ----")
        for i in range(n):
            L.append(f"Xmux{i} s{i} a{i} zflag y{i} vdd 0 MUX2")
    return L


def pwl(node, seq, name):
    """Piecewise-linear source stepping through one bit's vector sequence."""
    pts, t = [], TSETTLE
    v = (seq[0] >> 0) & 1
    pts.append(f"0 {v*VDD}")
    for k, bit in enumerate(seq):
        if k == 0:
            continue
        t = TSETTLE + k * TP
        pts.append(f"{(t-TR)*1e9:.4f}n {v*VDD}")
        v = bit
        pts.append(f"{t*1e9:.4f}n {v*VDD}")
    return f"V{name} {node} 0 PWL({' '.join(pts)})"


def make_netlist(n, vectors, bypass, path, meas_points=None):
    """vectors: list of (a, b) integer pairs."""
    m = len(vectors)
    tend = TSETTLE + m * TP
    L = [f"* adder energy experiment  n={n}  bypass={bypass}  vectors={m}", ""]
    # The library is INLINED rather than .include'd: this project's path
    # contains a space, which ngspice's .include cannot handle.
    L += LIB.read_text().splitlines()
    L += ["", f"Vvdd vdd 0 DC {VDD}", ""]

    for i in range(n):
        L.append(pwl(f"a{i}", [(a >> i) & 1 for a, _ in vectors], f"a{i}"))
        L.append(pwl(f"b{i}", [(b >> i) & 1 for _, b in vectors], f"b{i}"))
    L.append("")
    L += build_adder(n, bypass)
    L.append("")

    # a light capacitive load on every output, so both designs drive something
    for i in range(n):
        L.append(f"Cl{i} y{i} 0 5f")

    L += ["", f".tran 20p {tend*1e9:.4f}n",
          f".meas tran qtot INTEG i(Vvdd) FROM={TSETTLE*1e9:.4f}n TO={tend*1e9:.4f}n"]

    if meas_points:
        for k in range(m):
            t = TSETTLE + (k + 1) * TP - TP * 0.05
            for i in range(n):
                L.append(f".meas tran y{k}_{i} FIND v(y{i}) AT={t*1e9:.4f}n")

    L += [".end", ""]
    path.write_text("\n".join(L))
    return tend


# ---------------------------------------------------------------------------
# run + parse
# ---------------------------------------------------------------------------
def run_ngspice(path):
    r = subprocess.run(["ngspice", "-b", str(path)],
                       capture_output=True, text=True, timeout=1800)
    return r.stdout + r.stderr


def get_energy(out, m):
    mt = re.search(r"^\s*qtot\s*=\s*([-\d.eE+]+)", out, re.M)
    if not mt:
        return None
    return abs(float(mt.group(1))) * VDD / m      # joules per addition


def get_bits(out, k, n):
    v = 0
    for i in range(n):
        mt = re.search(rf"^\s*y{k}_{i}\s*=\s*([-\d.eE+]+)", out, re.M)
        if not mt:
            return None
        if float(mt.group(1)) > VDD / 2:
            v |= 1 << i
    return v


def gen_vectors(m, n, zero_frac, rng):
    """Place an EXACT count of zero-operand vectors, then shuffle.

    Drawing each vector independently against a probability gives a ragged
    curve at small m -- different target fractions can land on the identical
    vector set. An exact count makes the sweep monotone and reproducible.
    """
    nzero = round(zero_frac * m)
    flags = [True] * nzero + [False] * (m - nzero)
    rng.shuffle(flags)
    return [(rng.getrandbits(n), 0 if z else rng.getrandbits(n)) for z in flags]


# ---------------------------------------------------------------------------
def cmd_check(args):
    """Functional check: both designs must compute a+b at the reported width.

    Run this at the SAME width the energy sweep uses. Checking 8-bit and then
    reporting 32-bit energy would be reporting numbers from a circuit whose
    correctness was never established.
    """
    n, m = args.bits, args.vectors
    rng = random.Random(7)
    vecs = [(rng.getrandbits(n), 0 if k % 2 else rng.getrandbits(n))
            for k in range(m)]
    OUT.mkdir(exist_ok=True)
    ok = True
    for bypass in (False, True):
        name = "bypass" if bypass else "baseline"
        p = OUT / f"check_{name}.sp"
        make_netlist(n, vecs, bypass, p, meas_points=True)
        out = run_ngspice(p)
        print(f"\n--- functional check: {name}, {n}-bit ---")
        for k, (a, b) in enumerate(vecs):
            exp = (a + b) & ((1 << n) - 1)
            got = get_bits(out, k, n)
            good = got == exp
            ok &= good
            tag = "PASS" if good else "FAIL"
            print(f"  [{tag}]  {a:#0{n//4+2}x} + {b:#0{n//4+2}x} = {exp:#0{n//4+2}x}"
                  + ("" if good else f"   got {got:#x}"))
    print("\nFUNCTIONAL CHECK:", "PASSED" if ok else "FAILED")
    return 0 if ok else 1


def cmd_sweep(args):
    n, m = args.bits, args.vectors
    fracs = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 1.0]
    if args.fine:
        # the break-even sits between 0.75 and 1.0; interpolating across a gap
        # that wide is not a measurement, so sample inside it
        fracs = [0.0, 0.25, 0.5, 0.75, 0.8125, 0.875, 0.9375, 1.0]
    OUT.mkdir(exist_ok=True)
    rows = []
    print(f"\n{n}-bit adder, {m} additions per point, generic 180nm models")
    print(f"{'zero frac':>10} {'baseline pJ':>13} {'bypass pJ':>12} "
          f"{'ratio':>8} {'verdict':>10}")
    print("-" * 60)
    for zf in fracs:
        rng = random.Random(1234)
        vecs = gen_vectors(m, n, zf, rng)
        e = {}
        for bypass in (False, True):
            p = OUT / f"sweep_{int(zf*1000)}_{'byp' if bypass else 'base'}.sp"
            make_netlist(n, vecs, bypass, p)
            e[bypass] = get_energy(run_ngspice(p), m)
            if e[bypass] is None:
                print(f"  ngspice gave no result for zf={zf} bypass={bypass}")
                return 1
        ratio = e[True] / e[False]
        rows.append(dict(zero_fraction=zf, baseline_pj=e[False] * 1e12,
                         bypass_pj=e[True] * 1e12, ratio=ratio))
        print(f"{zf:>10.3f} {e[False]*1e12:>13.4f} {e[True]*1e12:>12.4f} "
              f"{ratio:>8.3f} {'bypass wins' if ratio < 1 else 'bypass LOSES':>10}")

    csvp = ROOT / "reports_ooc" / "adder_bypass_energy.csv"
    csvp.parent.mkdir(exist_ok=True)
    with open(csvp, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    print("-" * 60)
    be = None
    for i in range(len(rows) - 1):
        if (rows[i]["ratio"] - 1) * (rows[i + 1]["ratio"] - 1) < 0:
            r0, r1 = rows[i], rows[i + 1]
            t = (1 - r0["ratio"]) / (r1["ratio"] - r0["ratio"])
            be = r0["zero_fraction"] + t * (r1["zero_fraction"] - r0["zero_fraction"])
    if be is None:
        best = min(rows, key=lambda r: r["ratio"])
        if best["ratio"] >= 1:
            print("BREAK-EVEN: never. The bypass loses at every zero-fraction,")
            print("            including 100%. The overhead exceeds the saving.")
        else:
            print("BREAK-EVEN: below the smallest sweep point.")
    else:
        print(f"BREAK-EVEN ZERO-FRACTION: {be:.3f}")
        print(f"  The bypass pays only when more than {be*100:.1f}% of additions")
        print(f"  have a zero operand.")
    print(f"\nWritten to {csvp}")
    print("\nFor SHA-256: the T1 operands are hash state, which is uniformly")
    print("random by design. P(32-bit operand == 0) = 2^-32. Run --sha to")
    print("measure the actual zero-fraction on real round traces.")
    return 0


K_CONST = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
        0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
        0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
H_INIT = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
          0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
M32 = 0xffffffff


def rotr(x, k):
    return ((x >> k) | (x << (32 - k))) & M32


def sha_rounds(block):
    """Run one 512-bit block, yielding (partial_sum, W[t]) per round.

    The T1 chain is  h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t].  The pair below
    is its LAST two-input stage: the accumulated partial as operand A, and
    W[t] as operand B.  W[t] is the right operand to zero-detect, because it
    is the only one that is ever actually zero -- the padding region of a
    short message leaves W[1..14] at zero.
    """
    w = list(block)
    for t in range(16, 64):
        s0 = rotr(w[t-15], 7) ^ rotr(w[t-15], 18) ^ (w[t-15] >> 3)
        s1 = rotr(w[t-2], 17) ^ rotr(w[t-2], 19) ^ (w[t-2] >> 10)
        w.append((s1 + w[t-7] + s0 + w[t-16]) & M32)
    a, b, c, d, e, f, g, h = H_INIT
    out = []
    for t in range(64):
        S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
        ch = (e & f) ^ (~e & M32 & g)
        S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
        mj = (a & b) ^ (a & c) ^ (b & c)
        partial = (h + S1 + ch + K_CONST[t]) & M32
        out.append((partial, w[t]))
        t1 = (partial + w[t]) & M32
        t2 = (S0 + mj) & M32
        h, g, f, e = g, f, e, (d + t1) & M32
        d, c, b, a = c, b, a, (t1 + t2) & M32
    return out


def padded_block(msg: bytes):
    """FIPS 180-4 padding, single block only."""
    pad = msg + b"\x80" + b"\x00" * ((56 - len(msg) - 1) % 64)
    pad += (len(msg) * 8).to_bytes(8, "big")
    assert len(pad) == 64, "single-block messages only"
    return [int.from_bytes(pad[i*4:(i+1)*4], "big") for i in range(16)]


def cmd_sha_spice(args):
    """Drive the SPICE netlists with REAL SHA-256 T1 operands.

    No interpolation and no inference: the actual operand stream, through the
    actual transistor-level circuits, measured.
    """
    cases = [("abc", padded_block(b"abc")),
             ("empty message", padded_block(b"")),
             ("55-byte message", padded_block(b"a" * 55))]
    OUT.mkdir(exist_ok=True)
    print("\nREAL SHA-256 OPERANDS THROUGH THE NETLIST")
    print("  operand A = h + Sigma1(e) + Ch(e,f,g) + K[t]   (accumulated partial)")
    print("  operand B = W[t]                               (zero-detected)")
    print("\n  A padded short message is the bypass's BEST case in SHA-256:")
    print("  W[1..14] of the padding region really are zero.\n")
    print(f"  {'message':>18} {'zero W[t]':>10} {'frac':>7} "
          f"{'baseline pJ':>12} {'bypass pJ':>11} {'ratio':>7}")
    print("  " + "-" * 72)
    rows = []
    for name, blk in cases:
        vecs = sha_rounds(blk)
        nz = sum(1 for _, b in vecs if b == 0)
        e = {}
        for bypass in (False, True):
            path = OUT / f"sha_{name.split()[0]}_{'byp' if bypass else 'base'}.sp"
            make_netlist(32, vecs, bypass, path)
            e[bypass] = get_energy(run_ngspice(path), len(vecs))
            if e[bypass] is None:
                print(f"  ngspice gave no result for {name}")
                return 1
        ratio = e[True] / e[False]
        rows.append(dict(message=name, rounds=len(vecs), zero_w=nz,
                         zero_fraction=nz / len(vecs),
                         baseline_pj=e[False] * 1e12,
                         bypass_pj=e[True] * 1e12, ratio=ratio))
        print(f"  {name:>18} {nz:>10} {nz/len(vecs):>7.3f} "
              f"{e[False]*1e12:>12.4f} {e[True]*1e12:>11.4f} {ratio:>7.3f}")

    csvp = ROOT / "reports_ooc" / "adder_bypass_sha_operands.csv"
    csvp.parent.mkdir(exist_ok=True)
    with open(csvp, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    print("  " + "-" * 72)
    worst = min(rows, key=lambda r: r["ratio"])
    print(f"\n  Best case for the bypass across these messages: "
          f"{worst['ratio']:.3f}x at a {worst['zero_fraction']:.1%} zero-fraction.")
    if worst["ratio"] > 1.0:
        print(f"  The bypass LOSES on every real SHA-256 operand stream tested,")
        print(f"  including the padded short messages that maximise its chances.")
    else:
        print(f"  The bypass wins on {worst['message']} -- investigate.")
    print(f"\n  A multi-block message is worse still: only the FINAL block")
    print(f"  carries padding, so the zero-fraction tends to 0 as length grows.")
    print(f"\n  Written to {csvp}")
    return 0


def cmd_sha(args):
    """Measure the real zero-operand fraction in SHA-256's T1 addition."""
    K = K_CONST
    H = H_INIT
    rng = random.Random(99)
    counts = {"h": 0, "S1": 0, "Ch": 0, "W": 0, "any": 0}
    total = 0
    nblocks = args.blocks
    for _ in range(nblocks):
        blk = [rng.getrandbits(32) for _ in range(16)]
        w = list(blk)
        for t in range(16, 64):
            s0 = rotr(w[t-15], 7) ^ rotr(w[t-15], 18) ^ (w[t-15] >> 3)
            s1 = rotr(w[t-2], 17) ^ rotr(w[t-2], 19) ^ (w[t-2] >> 10)
            w.append((s1 + w[t-7] + s0 + w[t-16]) & M32)
        a, b, c, d, e, f, g, h = H
        for t in range(64):
            S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
            ch = (e & f) ^ (~e & M32 & g)
            S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
            mj = (a & b) ^ (a & c) ^ (b & c)
            ops = {"h": h, "S1": S1, "Ch": ch, "W": w[t]}
            for k_, v in ops.items():
                if v == 0:
                    counts[k_] += 1
            if any(v == 0 for v in ops.values()):
                counts["any"] += 1
            total += 1
            t1 = (h + S1 + ch + K[t] + w[t]) & M32
            t2 = (S0 + mj) & M32
            h, g, f, e = g, f, e, (d + t1) & M32
            d, c, b, a = c, b, a, (t1 + t2) & M32

    print(f"\nSHA-256 T1 operand statistics over {nblocks} random blocks "
          f"({total} rounds)")
    print("  T1 = h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t]")
    print(f"\n  {'operand':>10} {'zero count':>11} {'fraction':>12}")
    print("  " + "-" * 36)
    for k_ in ("h", "S1", "Ch", "W"):
        print(f"  {k_:>10} {counts[k_]:>11} {counts[k_]/total:>12.3e}")
    print(f"  {'ANY zero':>10} {counts['any']:>11} {counts['any']/total:>12.3e}")
    print(f"\n  Expected for uniform random 32-bit values: 2^-32 = "
          f"{2**-32:.3e} per operand.")
    print("\n  This is the zero-fraction the bypass would actually see.")
    print("  Compare it against the break-even fraction from --sweep.")
    return 0


def main():
    if not shutil.which("ngspice"):
        sys.exit("ngspice not found on PATH")
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--sweep", action="store_true")
    ap.add_argument("--sha", action="store_true")
    ap.add_argument("--sha-spice", action="store_true")
    ap.add_argument("--bits", type=int, default=32)
    ap.add_argument("--vectors", type=int, default=16)
    ap.add_argument("--fine", action="store_true",
                    help="denser sweep points near the break-even region")
    ap.add_argument("--blocks", type=int, default=200)
    a = ap.parse_args()
    if a.check:
        return cmd_check(a)
    if a.sweep:
        return cmd_sweep(a)
    if a.sha:
        return cmd_sha(a)
    if a.sha_spice:
        return cmd_sha_spice(a)
    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
