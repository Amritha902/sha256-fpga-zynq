# SHA-256 Hardware Accelerator on Zynq-7000

**Team handoff pack — Review 1**
Course: FPGA-Based System Design · Target: ZedBoard XC7Z020-1CLG484C · Vivado/Vitis 2022.2

---

## What this is

A hardware SHA-256 accelerator, built two ways from the **same compression round**:

| | Config A — iterative | Config B — 2× unrolled |
|---|---|---|
| Rounds per cycle | 1 | 2 |
| Cycles per 512-bit block | **66** (measured) | **34** (measured) |
| Round logic | 1× | 2× |
| Critical path | one 5-input 32-bit adder chain | **two in series** |
| Fmax | baseline | **expected to fall** |
| DSP48 | 0 | 0 |

**The project question is not "can we implement SHA-256."** It is:

> Does unrolling actually pay for a hash function, given that its rounds are strictly sequential?

Config B needs **1.94× fewer cycles**. If its Fmax comes out above **51.5%** of Config A's, unrolling is a net throughput win. Below that, it's a net loss — **and a well-measured loss is a valid finding, not a failure.** Say so in the report.

---

## Why this is a genuinely interesting question

Contrast with a block cipher in ECB mode:

- **AES-ECB blocks are independent.** Unrolled rounds can be separated by pipeline registers, so combinational depth per stage stays constant, Fmax is preserved, and throughput scales linearly with area.
- **SHA-256 rounds are dependent.** Round *t+1* consumes round *t*'s output. You cannot insert a register between two unrolled rounds without losing the cycle-count saving. The adder chains stack, and frequency *must* drop.

This is why hash functions parallelise badly within a single message, and it's the most defensible sentence in your report.

**One thing that does unroll for free:** the message schedule. `W[t+16]` and `W[t+17]` both depend only on the *current* 16-word window, so the two schedule adders run in parallel with no serial dependency. Compression is the bottleneck; the schedule isn't. Worth pointing out — it shows you understand *where* the dependency actually lives.

---

## Status: the RTL is written and verified

**This is not untested skeleton code.** It compiles and simulates, and passes 21 checks:

```
LEVEL 1 : logical functions        Sigma0/1, sigma0/1, Ch, Maj      9 PASS
LEVEL 2 : K constant ROM           K[0], K[15], K[32], K[63]        4 PASS
LEVEL 3 : Config A (iterative)     "abc", "", 56-byte 2-block       3 PASS
LEVEL 4 : Config B (2x unrolled)   same three vectors               3 PASS
LEVEL 5 : cross-validation         A and B produce identical digest 1 PASS
LEVEL 6 : cycle counts             66 vs 34 as designed             1 PASS

CHECKS RUN : 21      FAILURES : 0      RESULT : ALL CHECKS PASSED
```

Both cores produce the official NIST digests, including **multi-block chaining** (the 56-byte vector needs two blocks with the hash value carried forward).

The Python golden model separately passes all five FIPS 180-4 vectors, including the one-million-character test.

What remains is synthesis, AXI integration, the Vitis application, and measurement — not algorithm work.

---

## Files

```
sha_project/
├── model/
│   ├── sha256_golden.py        Python reference + vector generator
│   ├── k_const.mem             64 K constants for $readmemh (generated)
│   ├── blocks.txt              padded blocks + expected digests (generated)
│   ├── abc_round_trace.txt     a..h after every one of the 64 rounds
│   └── abc_schedule.txt        W[0..63] for the "abc" block
├── rtl/
│   ├── sha256_functions.v      Ch, Maj, Sigma0/1, sigma0/1, K ROM,
│   │                           and sha256_round_comb (one round)
│   ├── sha256_core_iter.v      CONFIG A — 1 round/cycle
│   └── sha256_core_unroll2.v   CONFIG B — 2 rounds/cycle
├── tb/
│   └── tb_sha256.v             self-checking testbench, 21 checks
├── Makefile
├── build_vivado.tcl            synthesis + implementation, both configs
└── README.md
```

---

## How to run it

**Simulation** (Linux/WSL):

```bash
sudo apt-get install iverilog gtkwave     # once
cd sha_project
make model     # regenerate golden vectors, confirm the model self-checks
make           # compile and run the full verification suite
make wave      # open sim/tb_sha256.vcd for the report waveforms
```

**Synthesis:**

```bash
vivado -mode batch -source build_vivado.tcl
# reports land in ./reports/
```

Then compare `reports/configA_iterative_summary.txt` against `reports/configB_unroll2_summary.txt`. **That comparison is the project's headline result.**

---

## Key design decisions (be ready to defend these)

**1. Rolling 16-word message schedule, not 64 stored words.**
`W[t]` depends only on `W[t-2]`, `W[t-7]`, `W[t-15]`, `W[t-16]`. A 16-deep shift register is sufficient; storing all 64 words would waste 1536 bits for zero benefit.

**2. ROTR and SHR are free.**
They're fixed bit reorderings — pure routing, zero LUTs, zero delay. Each Sigma function is just a two-level XOR of three re-wired copies of its input. All the cost is in the modulo-2³² *addition*.

**3. Zero DSP48 slices.**
SHA-256 has no multiplication anywhere. Only adds, XORs, ANDs and rewiring.

**4. Padding is done in software, not hardware.**
The PS pads the message and streams 512-bit blocks; the PL does compression. This is a deliberate scope decision — padding is trivial bookkeeping, compression is the expensive part. Say it's deliberate, don't let it look like an omission. A hardware padder is listed as future work.

**5. The K constants are "nothing up my sleeve" numbers** — the first 32 bits of the fractional parts of the cube roots of the first 64 primes, chosen so nobody can claim a hidden trapdoor. One sentence in the report; examiners like it.

---

## Work split (3 people)

### Person 1 — Datapath & model (owns `sha256_functions.v`, `model/`)
- Own the Python golden model and the generated vectors
- **Experiment:** move the K ROM from LUT-based (current) to a `$readmemh` BRAM version using `model/k_const.mem`; measure the LUT/BRAM trade. Real data for the report.
- Extract waveforms for deliverable ③: one compression round showing T1/T2 formation, a Sigma function showing pure-rewiring, the message-schedule window advancing
- Build the truth-table figures: Ch, Maj, and the ROTR/SHR bit-mapping tables

### Person 2 — Cores & verification (owns both cores, `tb/`)
- Round-by-round comparison against `model/abc_round_trace.txt` is **done** — `tb/tb_sha256_soak.v` Level A checks `a..h` and `W[t]` at all 64 rounds. Run `make soak`.
- Add a random-message soak test driven from `model/blocks.txt`
- Run `build_vivado.tcl`; record Fmax and area for **both** configs
- **This person owns the headline result.** The Fmax ratio is the answer to the project question.

### Person 3 — AXI, software & system (owns wrappers, Vitis)
- Write `axi_lite_regs.v` (control/status, digest readback) and `axis_wrapper.v` (AXI4-Stream slave for 512-bit blocks, TLAST framing)
- Package as IP; Vivado block design with ZYNQ7 PS + AXI DMA
- Vitis bare-metal app: message padding, block streaming, digest readback, verification against NIST vectors, ARM global timer measurement
- Software SHA-256 baseline for the speedup comparison
- Build the demo: type a message over UART → board returns the hash

### Shared
Report, slides, demo rehearsal. **Everyone** should be able to explain why unrolling a hash costs frequency but unrolling AES-ECB doesn't. It's the most likely question.

---

## Honest expectation on speedup

Projected: Config A ≈ **776 Mbps** at 100 MHz. An ARM Cortex-A9 software SHA-256 runs around 20–25 cycles/byte, giving roughly **250 Mbps** — so expect only about **3×**, not the 100× an AES accelerator would show.

**Don't hide this. Explain it:** SHA-256 is built from 32-bit addition, XOR and rotation — precisely the operations a general-purpose ALU executes in one cycle each. There's no arithmetic the CPU has to emulate. The value of a SHA-256 accelerator is *offload and deterministic latency*, not raw speedup.

Saying that clearly is worth more marks than quoting an inflated number.

---

## Scope — frozen

**In:** SHA-256, 512-bit block compression in hardware, multi-block chaining, two configurations, PS–PL integration, FIPS 180-4 conformance.

**Out, with reasons:**

| Excluded | Why |
|---|---|
| Hardware padding | Trivial bookkeeping; the PS does it. Listed as future work. |
| SHA-224 / 384 / 512 | SHA-224 is a trivial IV change; 384/512 need a 64-bit datapath — a different design |
| HMAC | Two nested hashes plus key handling; a wrapper project, not a core one |
| 4-way multi-stream interleaving | The *right* way to get real throughput from a hash (independent messages pipeline fine). Genuinely interesting, but a third configuration — documented as the natural next step. |
| Side-channel resistance | Separate research field |

---

## Verification levels

| Level | Checked against | Status |
|---|---|---|
| Sigma / sigma / Ch / Maj | Python golden model | ✅ passing |
| K ROM entries | FIPS 180-4 §4.2.2 | ✅ passing (4 spot checks) |
| Message schedule W[0..63] | `abc_schedule.txt` | ✅ verified at all 64 rounds (`make soak`, Level A) |
| Per-round a..h | `abc_round_trace.txt` | ✅ verified at all 64 rounds (`make soak`, Level A) |
| Single-block digest | NIST "abc", "" | ✅ passing |
| Multi-block chaining | NIST 56-byte vector | ✅ passing |
| Config A vs Config B | Each other | ✅ passing |
| Cycle counts | 66 / 34 by design | ✅ passing |

Both trace checks are now wired into `tb/tb_sha256_soak.v` and passing. Every row in this table is verified.

---

## Reference

- **NIST FIPS PUB 180-4**, *Secure Hash Standard* — the specification. Free and authoritative.
- **NIST**, *Cryptographic Algorithm Validation Program* — additional test vectors.
- Chaves, Kuzmanov, Sousa, Vassiliadis, *Improving SHA-2 Hardware Implementations*, CHES 2006 — operation rescheduling and the unrolling trade-off.
- Ting, Yuen, Lee, Leong, *An FPGA Based SHA-256 Processor*, FPL 2002.
- McEvoy, Crowe, Murphy, Marnane, *Optimisation of the SHA-2 Family of Hash Functions on FPGAs*, ISVLSI 2006.
- Xilinx PG021 (AXI DMA), UG585 (Zynq TRM), UG901 (synthesis / ROM inference).

**Verify all citations before submission.** FIPS 180-4 is certain; the conference papers need year and venue confirmed on IEEE Xplore.
