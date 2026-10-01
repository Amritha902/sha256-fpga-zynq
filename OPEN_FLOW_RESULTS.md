# Open-Flow Results — the 2×2 placed and routed on XC7Z020

**SHA-256 accelerator on Zynq-7000 · Amritha S (23BEC1368)**
Run: 1 October 2026, in a cloud container, without Vivado. Flow and setup: `openflow/README.md`.

| | |
|---|---|
| Part | xc7z020clg484-1 (the ZedBoard's device) |
| Synthesis | Yosys 0.69, `synth_xilinx -flatten -abc9 -arch xc7` (LUT6, CARRY4, FDRE) |
| Place, route, timing | nextpnr-xilinx (openXC7) with the Project X-Ray database |
| Constraint | 250 MHz for every config, deliberately unreachable, as in the Vivado script |
| Statistic | **median Fmax over 5 placement seeds**; every seed is in `reports_open/seeds.csv` |
| Verification | 129 RTL + 21 software + 67 gate-level checks, 2 formal proofs, virtual board for A–D, all passing |

## The measurement

| | U | C | Fmax median (MHz) | seed range | Fmax / A | cyc/blk | LUT | FF | Mbit/s | Mbit/s/LUT |
|---|---|---|---:|---|---:|---:|---:|---:|---:|---:|
| **A** iterative | 1 | 1 | 68.24 | 64.5–70.5 | 1.000 | 66 | 1921 | 1035 | 529.4 | 0.276 |
| **B** 2× unrolled | 2 | 1 | 45.92 | 44.5–48.2 | **0.673** | 34 | 2298 | 1035 | 691.5 | **0.301** |
| **B′** B + operands scheduled | 2 | 1 | 44.41 | 41.5–45.7 | 0.651 | 34 | 2311 | 1035 | 668.7 | 0.289 |
| **C** 2-msg interleaved | 1 | 2 | 68.20 | 65.8–70.6 | **0.999** | 33 | 3611 | 2059 | 1058.1 | 0.293 |
| **D** unrolled + interleaved | 2 | 2 | 40.18 | 39.6–46.4 | 0.589 | 17 | 4486 | 2059 | **1210.1** | 0.270 |

No configuration uses DSP slices or block RAM.

**Use the ratios, not the MHz.** nextpnr-xilinx's routing model is conservative: about 75% of every
critical path is routing. Vivado will report higher absolute frequencies. The pre-registered
thresholds are stated as ratios, so they are what this run tests.

## Verdicts

### 1. The pre-registered prediction (Config B)

```
Fmax(B)/Fmax(A) = 0.673      core break-even 0.515      system break-even 0.624
```

**B clears both thresholds.** Unrolling is a net throughput win on this device and flow: 1.31× at core
level and 1.08× at system level with the measured AXI cycle counts. The thresholds stated in Review 1
were not moved. The prediction of a net loss is **falsified** by this flow, and that is reported as is.

### 2. The base paper (Suhaili & Julai 2022)

They report Fmax *rising* with unfolding ×2. On the XC7Z020 under a controlled build, it falls to
0.673 of A's. **Their frequency increase does not reproduce.** Their throughput claim, that unfolding ×2
is a net gain, **does** reproduce.

### 3. The structural "Fmax halves" argument

The naive structural model (two five-input adder chains in series) predicts 0.500. The measured value
is 0.673. **That model is also wrong**, for a reason visible in the critical-path reports:

| | carry-chain stages on critical path | LUT levels | logic ns | routing ns |
|---|---:|---:|---:|---:|
| A (seed 3) | 10 | 13 | 3.7 | 10.9 |
| B (seed 3) | 9 | 16 | 4.8 | 17.0 |

B's critical path is **not** twice A's. Synthesis rewrites each five-operand T1 sum into an adder tree
(`alumacc` → `$macc` → `maccmap`, then ABC9), so two rounds add about 30% more logic delay, not 100%.
What B pays for is mostly **routing**, because two rounds of logic spread over more of the die.

### 4. The operand-scheduling finding, tested on the FPGA

ngspice predicted 0.500 for naive operand order and 0.680 for scheduled order. B′ hoists
`g + K[t+1] + W[t+1]` out of the second round (`rtl/sha256_core_unroll2_sched.v`, marked keep so
synthesis cannot re-merge it).

| | measured | ngspice |
|---|---:|---:|
| B (RTL in naive order) | 0.673 | 0.500 |
| B′ (RTL hand-scheduled) | 0.651 | 0.680 |

**Hand-scheduling the RTL changes nothing.** The 3% difference is inside the seed spread, and both
designs clear both thresholds. The reason is the same as in §3: **the synthesiser already schedules the
adder tree**, so naive RTL lands at the scheduled bound (0.673 vs 0.680, within 1%).

So the finding is restated, more precisely and now with FPGA evidence:

> **The outcome of unrolling SHA-256 is decided by how synthesis structures the T1 adder, not by unroll
> depth and not by the operand order written in the RTL.** A tree-building synthesiser lands at the
> scheduled bound (ngspice 0.680, measured 0.673) and clears both thresholds. A flow that builds the
> literal serial chain would land near 0.500 and miss them. This is the measured mechanism behind the
> disagreement between Suhaili & Julai, the structural argument, and this project's own prediction.

What this run does *not* show: what Vivado's synthesiser does. That is the remaining open question, and
it is exactly what the four Vivado runs in `NEXT_STEPS.md` §1 answer.

### 5. Interleaving (the columns)

| | Fmax ratio | throughput gain |
|---|---:|---:|
| A → C | 0.999 | **2.00×** |
| B → D | 0.875 | 1.75× |

**A → C confirms the structural prediction exactly:** the same frequency and twice the throughput.
B → D loses 12.5% of frequency. D is the largest core (4486 LUT), and its critical path is again
routing-dominated, so the interaction is a placement effect. The two axes are **not** cleanly
orthogonal on this flow. That matches the decision to drop orthogonality as a claim.

### 6. Headline

- **Highest throughput:** D, 1210 Mbit/s, 2.29× A. Needs independent messages.
- **Best throughput per LUT:** B, 0.301 Mbit/s/LUT. Single-message unrolling is the most
  area-efficient option here.
- **System level** (measured AXI cycles): C is best at 1.67× A, because it amortises the streaming
  overhead over two blocks.

## Verification beyond RTL simulation

Everything below runs in the same container with free tools. Use `make formal`, `make gatesim`
and `make cosim`.

| Layer | Tool | Result |
|---|---|---|
| RTL simulation | Icarus Verilog | **129 / 129** checks: 103 for A–D plus 26 for B′. The race-free testbench still gives 66 and 34 cycles |
| Software reference | gcc | **21 / 21** |
| **Formal equivalence, round** | Yosys `sat -prove` | **PROVEN**: `round_comb(h,K,W) == round_comb_hkw(h+K+W)` for all 2³⁵² inputs |
| **Formal equivalence, whole core** | Yosys `equiv_make / equiv_simple / equiv_induct` | **PROVEN**: B′ ≡ B in every reachable state (4599 equivalence points). B′ is the same function with a different adder order |
| **Gate-level simulation** | Yosys netlist (LUT6/CARRY4/FDCE) under Icarus with the Xilinx cell models | **67 / 67**: A, B, B′, C and D netlists pass the RTL testbenches unchanged, so synthesis preserved function |
| **Virtual board** | Verilator model of `sha256_top`, driven by the **unmodified** `sw/main.c` and driver | **All four configs: ALL CONFORMANCE CHECKS PASSED**, including NIST vectors, the register self-test, dual-stream pairing, the benchmark, and `abc` typed at the emulated UART |

### What the new layers caught

1. **A driver bug, fixed.** On a Config C or D bitstream, `sha256_hw_hash()` hung: it streamed one
   message into a core that only accepts block *pairs*. No RTL testbench called the single-message
   API on a dual core; the virtual board does, because `main.c` does. The fix is in `sw/sha256_hw.c`:
   on a dual build, a lone message is hashed paired with itself, wasting one slot as documented.
   **This would have failed on the board.**
2. **A testbench race, fixed.** `tb_sha256.v` drove `block_valid` with a blocking write *at* the
   clock edge. RTL simulation happened to resolve the race in the favourable order; the gate-level
   netlist did not, and counted 67 and 35. The testbench now drives and samples 1 ns after each
   edge. The architecture is unchanged: 66 and 34 cycles per block, confirmed at RTL, at gate level
   and on the virtual board's CYCLE_CNT.
3. **A wrong label, fixed.** The 112-byte NIST vector pads to 2 blocks, not the 3 that `main.c`
   printed.

### System cycles read from the accelerator's own CYCLE_CNT (virtual board)

| | A | B | C (per message) | D (per message) |
|---|---:|---:|---:|---:|
| cycles per block over AXI | 84 | 52 | 50 | 34 |
| figure used in `compare_configs.py` | 85 | 53 | 51 | 35 |

The two counters differ by exactly one cycle, the same in every configuration, so no ratio or
threshold changes.

### What still needs the real hardware and Vivado

- Vivado's synthesiser (the open question in §4) and Vivado's Fmax: `vivado/build_core_ooc.tcl`.
- The Zynq block design (PS7 configuration and the AXI DMA IP). These are Xilinx IP with no
  open-source equivalent, so no board bitstream for the full system can be built here.
- Real PS7 bus latency, the A9's software speed (which sets the speedup figure), and on-board power.

## Reproduce

```bash
openflow/build_open.sh                         # all five configs, 5 seeds each
python3 scripts/compare_configs.py reports_open/results.csv
python3 openflow/compare_sched.py   reports_open/results.csv
```

Also reproduced in the same container: `spice/gen_round_delay.py --curve` gives the committed delays
to four decimal places (0.5506, 0.8460, 1.0890, 1.8387 ns at chain lengths 1, 2, 3 and 5).
