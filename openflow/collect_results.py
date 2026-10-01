#!/usr/bin/env python3
"""Turn the open-flow reports into reports_open/results.csv.

Same columns as vivado/build_core_ooc.tcl, so scripts/compare_configs.py
reads either. Fmax is the median over seeds; every seed is also kept in
seeds.csv so the spread can be reported.

    python3 openflow/collect_results.py reports_open 1 2 3 4 5
"""
import csv
import json
import re
import statistics
import sys
from pathlib import Path

CFG = {  # name: (description, cycles per block, streams)
    "A": ("CONFIG A - U=1, C=1 : iterative baseline", 66.0, 1),
    "B": ("CONFIG B - U=2, C=1 : 2x unrolled", 34.0, 1),
    "C": ("CONFIG C - U=1, C=2 : 2-message C-slow interleaved", 33.0, 2),
    "D": ("CONFIG D - U=2, C=2 : unrolled AND interleaved", 17.0, 2),
    "Bs": ("CONFIG B' - U=2, C=1 : 2x unrolled, operands scheduled", 34.0, 1),
}
PERIOD = 4.0


def area(path):
    cells = {}
    for line in Path(path).read_text().splitlines():
        m = re.match(r"\s+(\d+)\s+(\S+)$", line)
        if m:
            cells[m.group(2)] = cells.get(m.group(2), 0) + int(m.group(1))
    lut = sum(v for k, v in cells.items() if re.fullmatch(r"LUT[1-6]", k))
    ff = sum(v for k, v in cells.items() if re.fullmatch(r"FD[CPRS]E", k))
    carry = cells.get("CARRY4", 0)
    bram = sum(v for k, v in cells.items() if k.startswith("RAMB"))
    dsp = sum(v for k, v in cells.items() if k.startswith("DSP"))
    return lut, ff, carry, bram, dsp


def main():
    out = Path(sys.argv[1])
    seeds = sys.argv[2:]
    rows, seed_rows = [], []
    for name, (desc, cyc, streams) in CFG.items():
        if not (out / f"pnr_{name}_s{seeds[0]}.json").exists():
            continue
        fmaxes = []
        for s in seeds:
            rep = json.loads((out / f"pnr_{name}_s{s}.json").read_text())
            f = list(rep["fmax"].values())[0]["achieved"]
            fmaxes.append(f)
            seed_rows.append([name, s, f"{f:.2f}"])
        fmax = statistics.median(fmaxes)
        lut, ff, carry, bram, dsp = area(out / f"area_{name}.txt")
        thr = 512.0 * fmax / cyc
        rows.append([name, desc, "xc7z020clg484-1 (open flow)", PERIOD,
                     f"{PERIOD - 1000.0 / fmax:.3f}", f"{fmax:.2f}", cyc, streams,
                     lut, ff, carry, bram, dsp, f"{thr:.1f}", f"{thr / lut:.4f}"])
        print(f"{name}: median Fmax {fmax:.2f} MHz over {len(fmaxes)} seeds "
              f"(min {min(fmaxes):.2f}, max {max(fmaxes):.2f}); {lut} LUT, {ff} FF")

    # merge with configs built by an earlier run (CONFIGS="Bs" rebuilds one)
    built = {r[0] for r in rows}
    for old_csv, keep in (("results.csv", rows), ("seeds.csv", seed_rows)):
        if (out / old_csv).exists():
            old = [r for r in csv.reader(open(out / old_csv))][1:]
            keep[:0] = [r for r in old if r[0] not in built]
    order = list(CFG)
    rows.sort(key=lambda r: order.index(r[0]))
    seed_rows.sort(key=lambda r: (order.index(r[0]), int(r[1])))

    with open(out / "results.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["config", "description", "part", "period_ns", "wns_ns", "fmax_mhz",
                    "cycles_per_block", "streams", "lut", "ff", "carry", "bram", "dsp",
                    "throughput_mbps", "throughput_per_lut"])
        w.writerows(rows)
    with open(out / "seeds.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["config", "seed", "fmax_mhz"])
        w.writerows(seed_rows)


if __name__ == "__main__":
    main()
