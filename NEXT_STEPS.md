# Next Steps

**SHA-256 accelerator on Zynq-7000 · Amritha S (23BEC1368)**
Repo: https://github.com/Amritha902/sha256-fpga-zynq (private)
Last updated: 29 September 2026

---

## Where things stand

Everything in this repo is committed and pushed. Working tree clean, `master`
level with `origin/master`.

| | Status |
|---|---|
| Four cores A / B / C / D, one shared `sha256_round_comb` | done, verified |
| AXI4-Lite + AXI4-Stream integration, all four | done, verified |
| PS-side driver including the dual-stream pair API | done, verified natively |
| Verification | **103 RTL + 21 software checks, all passing** |
| Literature survey, re-framed around Suhaili & Julai (2022) | done |
| Base-paper comparison in ngspice | done |
| Adder-bypass study (rejected, with evidence) | done |
| Review slides for the 2×2 | done |
| **Synthesis, Fmax, area — open-source flow on XC7Z020** | **done, see `OPEN_FLOW_RESULTS.md`**: B/A = 0.673 (clears both thresholds), C/A = 0.999 |
| Synthesis, Fmax, area — Vivado | not started — see §1; still the reference result |
| Board bring-up | not started |

Reproduce the whole verification suite in one command:

```bash
cd ~/sha256-fpga && make all
```

> **The old working copy at `/Users/amritha/Downloads/files 2/sha_project` is now
> stale.** It lacks `BASE_PAPER_COMPARISON.md`, `spice/gen_round_delay.py` and
> `sw/sha256_pair.c`, and holds older versions of the Makefile, the driver, the
> slides and `build_system.tcl`. Work in `~/sha256-fpga` only. Delete the old
> copy once you are satisfied nothing is missing from it.

---

## 1. The four Vivado runs — blocks everything else

This is the only thing standing between the project and its headline result.
Nothing below can be finished without it. Needs a machine with **Vivado
2022.2**; there is none on this Mac.

```bash
cd ~/sha256-fpga
for i in 0 1 2 3; do vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs $i; done
python3 scripts/compare_configs.py
```

Each run appends a row to `reports_ooc/results.csv`. Bring that one file back
and `compare_configs.py` does the arithmetic and prints the verdict.

**Warn whoever runs it about two things, or they will "fix" them:**

1. **The timing constraint is deliberately unreachable (250 MHz) and all four
   are expected to MISS it.** Vivado stops optimising once timing is met, so at
   100 MHz all four would meet it with slack and the result would record where
   the tool chose to stop rather than where each design runs out of road.
   **Negative slack is the measurement.** Do not relax the constraint, and never
   relax it for one configuration only — that voids the comparison.
2. **Out-of-context is deliberate.** `build_system.tcl` wraps the core in a
   block design with the PS, a DMA and an interconnect, so its worst path may
   sit in the interconnect rather than the core. The OOC flow compiles each core
   alone against a virtual clock, which is what the hypothesis is actually about.

### How to read the result

Pre-registered before synthesis: **0.515** at core level, **0.624** at system
level. Both were committed in Review 1 and neither has been moved.

| Outcome | Meaning |
|---|---|
| Fmax(B)/Fmax(A) **> 0.624** | Unrolling pays outright. Report the gain. |
| **0.515 – 0.624** | Pays for the bare core, cancelled by the fixed AXI streaming overhead once integrated. Report both levels. |
| **< 0.515** | Net loss. This is the stated falsifiable outcome, **a valid finding, not a failure**. |

Separately, check the columns: **A→C and B→D should both be close to 2×**, and
Fmax(C) should be close to Fmax(A) because their combinational depth is
identical. If a column *loses*, that is a build problem — check the pipeline
register was not retimed away — not a refutation of the architecture.

### What the ngspice study predicts it will find

`BASE_PAPER_COMPARISON.md` measured the round's critical path at transistor
level: `delay(n) = 0.2110 ns + n × 0.3169 ns`, R² = 0.998, so delay is linear in
adder-chain depth.

| | Σ1 | adds | Path | Fmax vs A |
|---|---:|---:|---:|---:|
| A | 1 | 5 | 1.796 ns | 1.000 |
| B, naive operand order | 2 | 10 | 3.591 ns | **0.500** |
| B, reordered per Chaves | 2 | 7 | 2.641 ns | **0.680** |
| C | 1 | 5 | 1.796 ns | 1.000 |

So B's measured ratio should land **between 0.50 and 0.68**, and where it lands
tells you how well Vivado scheduled the adder chain. That is the finding —
unrolling's outcome is decided by operand scheduling, not unroll depth.

---

## 2. The four system builds — for the board and whole-system area

Only after §1, and only if you want the hardware demo and whole-system
utilisation figures.

```bash
cd ~/sha256-fpga
vivado -mode batch -source vivado/build_system.tcl -tclargs 0    # Config A
vivado -mode batch -source vivado/build_system.tcl -tclargs 1    # Config B
vivado -mode batch -source vivado/build_system.tcl -tclargs 2    # Config C
vivado -mode batch -source vivado/build_system.tcl -tclargs 3    # Config D
```

Produces `build_cfg?/sha256_system.xsa` for Vitis and `reports/summary.txt`.

If the DMA or block-design automation names things differently on your install,
expect to adjust one or two `apply_bd_automation` lines. A GUI fallback is in
`IMPLEMENTATION_GUIDE.md` §3.4.

---

## 3. Board bring-up

1. Import the `.xsa` into Vitis, create a platform and a bare-metal application.
2. Build `sw/` — `main.c`, `sha256_hw.c`, `sha256_pair.c`, `sha256_sw.c`.
3. Check the base-address macro against `xparameters.h`; fix `SHA256_BASEADDR`
   in `sha256_hw.c` if Vivado assigned something else.
4. Program the bitstream, open a terminal at **115200 8N1**, run.

`main.c` runs four tests and a benchmark:

| | What |
|---|---|
| TEST 1 | Register map, VERSION = `0x53480001` |
| TEST 2 | NIST FIPS 180-4 conformance |
| TEST 3 | Hardware vs software throughput |
| TEST 4 | **Dual-stream pair API** — skips itself automatically on a Config A or B bitstream, because it reads CAPS at 0x58 rather than assuming |

**If the hardware digest disagrees with the software reference, check the cache
flush first.** The Cortex-A9 has a write-back data cache; without
`Xil_DCacheFlushRange()` the DMA reads stale DDR and the digest is silently
wrong. It is the single most common cause of this failure.

---

## 4. Measurements to record

Fill in `RESULTS_AND_GAPS.md` §3 as data arrives — do not wait until the end.
Already measured and **not** to be re-derived:

| | Core cyc/block | System cyc/block |
|---|---:|---:|
| A | 66 | 85 |
| B | 34 | 53 |
| C | 33 | 51 (102 per pair) |
| D | 17 | 35 (70 per pair) |

Still needed: WNS, Fmax, LUT, FF, BRAM, **DSP (must be 0)**, throughput, and
**throughput-per-LUT** — the last is the only fair metric across the grid, since
the four configurations differ in area.

Also capture five waveform screenshots (deliverable ③) and a UART log.

---

## 5. Report and Review 3

Skeleton and page budget are in `RESULTS_AND_GAPS.md` §4. Source material:

| Chapter | From |
|---|---|
| Literature survey | `FPGA_SHA256_Literature_Survey.md` |
| Architecture | `FPGA_SHA256_Synopsis.md` §5 + the AXI register map |
| Verification | the eight-level hierarchy; the per-round trace method |
| Results | `RESULTS_AND_GAPS.md` §3 once filled |
| Discussion | `BASE_PAPER_COMPARISON.md` — the operand-scheduling finding |
| Future work | `ADDER_BYPASS_FINDING.md` — evaluated and rejected, with evidence |

Slides: `Review_SHA256_2x2.pptx`, six slides numbered 04–09 to slot into the
Review 1 deck. Rebuild after edits with
`python3 scripts/build_review_slides.py`. Add a results slide once §1 lands.

---

## 6. Loose ends

- [ ] **Four citations still marked ⚠️** in the survey §10 — [9] Kumar et al.
  (author list), [17] Padhi & Chaudhari (authors, volume, pages), [22] Wang et
  al. and [23] Stevens et al. (not independently re-verified). Resolve before
  submission; do not let a viva find them first.
- [x] **Survey reframed around the operand-scheduling finding.** §3.2 (fourth
  explanation), §5.4, §6 claim 4, §7, §8 and §11 now match
  `BASE_PAPER_COMPARISON.md`; orthogonality is dropped as a claim.
- [ ] **Ask the professor: a filed application, or a granted patent?** They are
  very different asks and change what to optimise for. VIT's IPR policy §9 says
  the Institute bears the full cost and takes assignment, with a 60:40 revenue
  split to the inventor — so money is not the constraint.
- [ ] Delete the stale `Downloads/files 2/sha_project` copy.
- [ ] Optional, cheap, decent report value: the K-ROM in LUT vs BRAM comparison.

---

## 7. Closed — do not reopen

Recorded so nobody spends a week re-deciding these.

**Operand-dependent adder bypass — rejected on measured evidence.** Occupied
prior art on both readings (carry-skip is textbook; operand isolation is covered
by US8578196, US5023826, US6366943 among others), *and* it does not work here:
driven with real SHA-256 operand streams in ngspice it costs **1.68×–2.00×** the
plain adder's energy, including on padded short messages, which are its best
possible case in this algorithm. SHA-256's operands are uniformly distributed by
construction — that is the security property — so value-dependent optimisation
has nothing to bite on. Full write-up in `ADDER_BYPASS_FINDING.md`.

**A patent on the architecture — all six candidate claims killed on prior art.**
Full adversarial assessment in `PATENT_GRILLING.md`. The decisive documents: a
**Helion Technology commercial FPGA IP datasheet from 2010** that switches
message context "on a block by block basis ... for multiple interleaved message
streams", and **IBM US20250070957A1** (filed 2023) which describes "lockstep of
two messages, to fully exploit a two-cycle pipeline" as *known background* it is
claiming around. Unroll-plus-pipeline is McEvoy 2006 and Gamgam 2023; operand
rescheduling is Chaves 2006; axis independence follows from Leiserson–Saxe
(1991); the methodology is excluded under §3(k). The one route that stays open
is a Vivado result that contradicts Suhaili & Julai — teaching away is a genuine
inventive-step argument — but the odds are low, because our own ngspice study
already supplies the explanation. Needs §1 done first.

**What the project actually claims** is a controlled re-test of a specific
recent contradictory result, plus the measured finding that unrolling's payoff
is decided by operand scheduling rather than unroll depth. That is defensible
and it survives the measurement going either way.
