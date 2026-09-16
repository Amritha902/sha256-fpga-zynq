# RESULTS TEMPLATE & PROJECT GAP ANALYSIS

**SHA-256 Accelerator on ZedBoard** · Amritha S · 23BEC1368

---

## PART 1 — Is the project done?

**No. The design is done. The project is not.**

Here is the honest split.

### 1.1 Complete and verified (nothing left to do here)

| Component | Evidence |
|---|---|
| Python golden model | 5 NIST vectors incl. one million chars; cross-checked against Python `hashlib` |
| Compression core, Config A | 66 cycles/block, correct digests |
| Compression core, Config B | 34 cycles/block, correct digests |
| Compression core, Config C | U=1 C=2, 33 effective cycles/block, two independent streams |
| Compression core, Config D | U=2 C=2, 17 effective cycles/block, four round instances |
| AXI4-Lite register file | Register map verified by BFM read/write |
| AXI4-Stream wrapper | Back-pressure, multi-block chaining, re-arm, soft reset |
| Top-level IP | 9/9 system checks, both configurations |
| Per-round trace verification | a..h and W[t] match at **all 64 rounds** |
| Soak test | 12 messages incl. 55/56/63/64/65-byte padding boundaries |
| Software SHA-256, padding, byte-swap | Compiled and verified natively against NIST |
| Vitis driver and application | Written, complete |
| Build automation | Written |

**Total: 69 RTL checks + 10 software checks, all passing.**

### 1.2 Written but never executed

| Item | Risk | What to do |
|---|---|---|
| `vivado/build_system.tcl` | **Medium** — I have no Vivado to test against | Run Config A first. Expect to adjust one or two `apply_bd_automation` lines if your install names things differently. GUI fallback is in the guide, §3.4. |
| `sw/main.c`, `sw/sha256_hw.c` | **Low** — logic verified, Xilinx API calls are standard | Compile against your BSP. Fix the base-address macro if `xparameters.h` names it differently. |

### 1.3 Genuinely not started

- Synthesis, area and Fmax for **any** of the four configurations — the headline result
- Board bring-up and any hardware measurement
- The final project report, Review 3 slides, demo video

**Config C and D AXI integration is now DONE** — `sha256_axis_wrapper_dual.v`,
an extended register map with a second digest at 0x38 and a CAPS discovery bit
at 0x58, and `sha256_top` selecting wrapper and core together on CORE_SELECT
0/1/2/3. 17 dual-stream system checks pass for each of C and D.
- Board bring-up
- Any hardware measurement
- **The final project report** (separate from the synopsis)
- Review 3 / final presentation
- Demo video, if required

---

## PART 2 — Extra files you still need

Ranked by how much they matter.

### Must have

| File | Why | Who |
|---|---|---|
| **Final project report** (.docx or .pdf) | The main graded artifact. The synopsis is a proposal, not a report. Needs: abstract, introduction, literature survey, methodology, implementation, results, discussion, conclusion, references. | Shared |
| **Review 3 / final presentation** | Same structure as Review 2 but with the results filled in | Shared |
| **Measurement data** — the two `reports/summary.txt` files and the UART log | Without these there are no results | P2, P3 |
| **Waveform screenshots** (5, per deliverable ③) | Explicitly required by the brief | P1 |

### Should have

| File | Why |
|---|---|
| **Block diagram figures** for the report | Redraw the ASCII diagrams from the synopsis in draw.io or Visio as PNG/SVG |
| **Individual contribution statement** | Most team projects require a per-member breakdown |
| **Demo script** | A written run sheet so the live demo does not depend on remembering the sequence |
| **`.gtkw` GTKWave save file** | So waveform captures are reproducible rather than hand-arranged each time |

### Nice to have

| File | Why |
|---|---|
| Photo of the board running | Good for the report and slides |
| Short demo video | Insurance if the hardware misbehaves on review day |
| BRAM-vs-LUT K-ROM comparison | A second data point, ten minutes of work |

---

## PART 3 — Results recording sheet

Fill this in as you go. Once complete, the results chapter is arithmetic.

### 3.1 Simulation results — ALREADY MEASURED, do not change

| Metric | Config A | Config B | Config C | Note |
|---|---|---|---|---|
| Structure | `reg→round→reg` | `reg→round→round→reg` | `reg→round→reg→round→reg` | one shared round module |
| Round instances | 1 | 2 combinational | 2 register-separated | |
| Messages in flight | 1 | 1 | **2** | C needs independent messages |
| Cycles per block pair | — | — | **66 for TWO blocks** | |
| Cycles per 512-bit block, compression only | **66** | **34** | **33 effective** | |
| Cycles per block, full system over AXI | **85** | **53** | **51** (102/2) | measured |
| Streaming overhead per block | **19** | **19** | **18** | 16 beats + handshake |
| Combinational depth | one round | **two rounds** | one round | why C keeps its Fmax |
| Core-level break-even vs A | — | 34/66 = **0.515** | 33/66 = **0.500** | |
| **System-level break-even vs A** | — | 53/85 = **0.624** | 51/85 = **0.600** | |

> **Note the refinement.** Review 1 derived 0.515 from the core cycle counts. Measuring the integrated system exposed a fixed 19-cycle streaming overhead — sixteen AXI beats plus handshake — which is identical in both configurations. A fixed overhead dilutes a proportional saving, so the real threshold is **0.624**, not 0.515. Unrolling has a harder bar to clear than Review 1 assumed. Present this as a finding.

### 3.1b System-level cycles — ALREADY MEASURED

Measured over the real AXI path, not estimated. Interleaving amortises the
streaming overhead over two blocks, so the dual configs gain at system level as
well as in the core.

| | Core cyc/block | System cyc/block | System break-even vs A |
|---|---:|---:|---|
| **A** | 66 | **85** | baseline |
| **B** | 34 | **53** | Fmax(B)/Fmax(A) > 53/85 = **0.624** |
| **C** | 33 | **51** (102 per pair) | Fmax(C)/Fmax(A) > 51/85 = **0.600** |
| **D** | 17 | **35** (70 per pair) | Fmax(D)/Fmax(A) > 35/85 = **0.412** |

**Note what this does to the argument.** At system level C needs only 51 cycles
per block against B's 53 — so C beats B on cycle count *as well as* on
combinational depth. B has to win a frequency argument it is structurally
positioned to lose. D needs 35, and only has to retain 41% of A's frequency to
break even.

### 3.2 Synthesis results — the 2×2 design space

| | **U = 1** | **U = 2** |
|---|---|---|
| **C = 1** | A — 66 cyc, depth 1 | B — 34 cyc, depth 2 |
| **C = 2** | C — 33 eff, depth 1 | D — 17 eff, depth 2 |

**Run these three, in any order, on the Vivado machine:**

```
vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs 0    # Config A
vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs 1    # Config B
vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs 2    # Config C
vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs 3    # Config D
python3 scripts/compare_configs.py
```

Each run appends a row to `reports_ooc/results.csv`; the compare script does
the arithmetic and prints the verdict. Bring that one CSV back and the results
chapter is transcription.

> **Why out-of-context and not `build_system.tcl`.** The system build wraps the
> core in a block design with the PS, a DMA and an interconnect, so the worst
> path it reports may sit in the interconnect rather than in the core — which is
> not what the hypothesis is about. The OOC flow compiles each core alone against
> a virtual clock, so the number is the core's own Fmax. Keep `build_system.tcl`
> for the board demo and whole-system area.

> **Why the constraint is set at 250 MHz and all three are expected to miss it.**
> Vivado stops optimising once timing is met. At 100 MHz all three would meet it
> with slack and the numbers would reflect where the tool chose to stop, not where
> each design runs out of road. A tight target pushes all three to their own limit
> under identical pressure. **A negative WNS here is the measurement, not a
> failure.** Do not relax the constraint, and never relax it for one config only.

| Metric | A (1,1) | B (2,1) | C (1,2) | D (2,2) | Notes |
|---|---|---|---|---|---|
| Worst negative slack (ns) | ____ | ____ | ____ | ____ | expected negative for all four |
| **Fmax (MHz)** | ____ | ____ | ____ | ____ | the headline numbers |
| Core LUT | ____ | ____ | ____ | ____ | |
| Core FF | ____ | ____ | ____ | ____ | interleaving roughly doubles FF |
| CARRY cells | ____ | ____ | ____ | ____ | where the adder chains live |
| BRAM | ____ | ____ | ____ | ____ | expect 0 |
| **DSP48** | ____ | ____ | ____ | ____ | **must be 0** |
| Throughput (Mbit/s) | ____ | ____ | ____ | ____ | 512 × Fmax ÷ cycles |
| **Throughput per LUT** | ____ | ____ | ____ | ____ | **the fair metric across the grid** |

**Expected pattern.** Fmax(A) ≈ Fmax(C) and Fmax(B) ≈ Fmax(D) — depth is constant down a column. Fmax drops moving across a row. If a column shows a large Fmax drop, suspect routing congestion in the bigger core, not architecture.

Whole-system LUT/FF, for A and B only, still come from `build_system.tcl`:

| Metric | Config A | Config B |
|---|---|---|
| Whole-system LUT | ________ | ________ |
| Whole-system FF | ________ | ________ |

### 3.3 The result

**Config B — the pre-registered prediction, genuinely open:**

```
    Fmax(B)          ________
    --------   =    ---------   =   ________
    Fmax(A)          ________

    Core threshold   = 0.515        System threshold = 0.624

    Verdict:   [ ] ratio > 0.624  ->  net WIN at core and system level
               [ ] 0.515 < r < 0.624 -> wins bare, cancelled by AXI overhead
               [ ] ratio < 0.515  ->  net LOSS — a valid reportable finding
```

**The columns — interleaving, structural, expected to win:**

```
    A -> C   Fmax ratio ________   throughput gain ________   (expect ~2x)
    B -> D   Fmax ratio ________   throughput gain ________   (expect ~2x)

    A loss in either column is a BUILD problem, not a refutation.
    Check the pipeline register was not retimed away.
```

**ORTHOGONALITY — the actual claim:**

```
    Interleave gain at U=1  (A->C) = ________
    Interleave gain at U=2  (B->D) = ________     spread ____ %

    Unroll gain at C=1      (A->B) = ________
    Unroll gain at C=2      (C->D) = ________     spread ____ %

    Both spreads under ~10%  ->  axes are INDEPENDENT. Claim confirmed.
    Large spread             ->  check Config D congestion first; an
                                 interaction appearing only in the largest
                                 core is a placement effect, not architecture.
```

**Against the literature:** Suhaili & Julai (2022) report unfolding-×2
*improving* Fmax on Arria II GX. Record explicitly whether that reproduces here:

```
    Does Fmax(B) > Fmax(A)?     [ ] yes — their result reproduces
                                [ ] no  — it does not transfer to Zynq-7020
```

**Headline sentence to fill in:**

> Unroll depth and interleave depth are ____________ in SHA-256.
> Unrolling delivered ______× and cost ______% of baseline frequency.
> Interleaving delivered ______× at ______% of baseline frequency,
> and the gain was the same at both unroll depths (spread ______%).

### 3.4 Board measurements — from the UART log, TEST 3

| Metric | Config A | Config B |
|---|---|---|
| Hardware throughput (Mbit/s) | ________ | ________ |
| Software throughput (Mbit/s) | ________ | ________ |
| Speedup | ________ | ________ |
| Cycle count reported by the accelerator | ________ | ________ |

> Expect roughly **3×**, not 100×. SHA-256 is 32-bit add, XOR and rotate — exactly what an ALU does in one cycle each. Explain this rather than apologising for it. The value of the accelerator is offload and deterministic latency.

### 3.5 Conformance — from the UART log, TEST 2

| Vector | Config A | Config B |
|---|---|---|
| empty message | [ ] PASS | [ ] PASS |
| `"abc"` | [ ] PASS | [ ] PASS |
| 56-byte, two blocks | [ ] PASS | [ ] PASS |
| 112-byte, three blocks | [ ] PASS | [ ] PASS |

---

## PART 4 — Report skeleton

Suggested structure and rough page budget for a 12-week project report.

| Section | Pages | Source material |
|---|---|---|
| 1. Abstract | 0.5 | Synopsis §1 |
| 2. Introduction and motivation | 2 | Synopsis §2 |
| 3. Literature survey | 4 | `FPGA_SHA256_Literature_Survey.md` |
| 4. Algorithm background | 3 | Synopsis §4, including the Ch/Maj/ROTR tables |
| 5. Architecture and design | 5 | Synopsis §5, plus the AXI register map |
| 6. Implementation | 4 | RTL module list, build flow, Vitis application |
| 7. Verification methodology | 4 | The eight-level hierarchy; the per-round trace method |
| 8. Results | 5 | Part 3 of this document |
| 9. Discussion | 3 | The 0.515 → 0.624 refinement; why the speedup is modest |
| 10. Conclusion and future work | 2 | Multi-stream interleaving; operation rescheduling |
| References | 1 | Literature survey |
| Appendix: key RTL listings | — | `sha256_functions.v`, `sha256_core_iter.v` |

**Two things to make sure appear in the discussion**, because they are what distinguish this from a plain implementation report:

1. **The threshold moved from 0.515 to 0.624** because integration exposed a fixed overhead the original analysis missed. That is real engineering — a prediction refined by measurement rather than abandoned.

2. **A modest software speedup is the correct outcome**, and the structural reason is that SHA-256's operations are exactly what a general-purpose ALU is built for. Contrast with a block cipher, whose finite-field arithmetic must be emulated.

---

## PART 5 — Pre-submission checklist

**Verification**
- [ ] `make all` passes on a clean checkout
- [ ] Both Vivado builds complete without errors
- [ ] `DSP : 0` confirmed in both summary files
- [ ] Hardware digests match NIST for all four vectors

**Documents**
- [ ] Final report complete, all placeholders filled
- [ ] Every citation verified on IEEE Xplore or IACR ePrint
- [ ] Cover page: correct title, names, IDs, team declaration
- [ ] Five waveforms captured and captioned

**Rubric coverage**
- [ ] ① Program — RTL + Vitis C + Python model
- [ ] ② Output verification — conformance tables
- [ ] ③ Waveforms — five, captioned
- [ ] ④ Truth tables — Ch, Maj, ROTR/SHR mapping, FSM state table
- [ ] ⑤ Circuit / block diagrams — redrawn as figures
- [ ] ⑥ End-to-end product — live demo works

**Demo**
- [ ] Board boots reliably from a cold start
- [ ] Serial terminal settings written down (115200 8N1, correct COM port)
- [ ] Backup: screen recording of a successful run
- [ ] Everyone can explain why unrolling costs frequency here but not in AES-ECB

---

*Last updated at Review 2. Update the measured columns as data arrives — do not wait until Week 11.*
