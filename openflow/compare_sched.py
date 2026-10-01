#!/usr/bin/env python3
"""The operand-scheduling finding, measured on the FPGA flow.

Reads a results.csv holding rows A, B and Bs (= B', sha256_core_unroll2_sched)
and puts the two unrolled ratios against the pre-registered thresholds and the
ngspice prediction.

    python3 openflow/compare_sched.py reports_open/results.csv
"""
import csv
import sys

CORE, SYSTEM = 34 / 66, 53 / 85
SPICE = {"B": 0.500, "Bs": 0.680}


def verdict(r):
    if r > SYSTEM:
        return "clears BOTH thresholds"
    if r > CORE:
        return "clears core, misses system"
    return "misses BOTH thresholds"


def main():
    rows = {r["config"]: r for r in csv.DictReader(open(sys.argv[1]))}
    fa = float(rows["A"]["fmax_mhz"])
    print()
    print("=" * 78)
    print(" OPERAND SCHEDULING INSIDE THE UNROLLED PAIR -- B (naive) vs B' (scheduled)")
    print("=" * 78)
    print(f" {'':<4} {'Fmax MHz':>9} {'ratio vs A':>11} {'ngspice':>8} {'LUT':>6}   verdict "
          f"(core {CORE:.3f} / system {SYSTEM:.3f})")
    print("-" * 78)
    for c, label in (("B", "B"), ("Bs", "B'")):
        if c not in rows:
            continue
        f = float(rows[c]["fmax_mhz"])
        print(f" {label:<4} {f:>9.2f} {f / fa:>11.3f} {SPICE[c]:>8.3f} {int(rows[c]['lut']):>6}   "
              f"{verdict(f / fa)}")
    if "B" in rows and "Bs" in rows:
        fb, fs = float(rows["B"]["fmax_mhz"]), float(rows["Bs"]["fmax_mhz"])
        print("-" * 78)
        print(f" Scheduling alone moves Fmax by {100 * (fs / fb - 1):+.1f}% "
              f"({fb:.2f} -> {fs:.2f} MHz), same device, flow and constraint.")
        if verdict(fb / fa) != verdict(fs / fa):
            print(" The verdict CHANGES with operand order: unrolling's outcome is decided by")
            print(" operand scheduling, not by unroll depth.")
        else:
            print(" The verdict does NOT change with operand order on this flow.")


if __name__ == "__main__":
    main()
