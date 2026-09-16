# Project Synopsis

## Unrolling Analysis of a SHA-256 Hardware Accelerator on Zynq-7000

**Author:** Amritha S · 23BEC1368
**Course:** FPGA-Based System Design
**Platform:** ZedBoard (XC7Z020-1CLG484C) · Vivado 2022.2 · Vitis 2022.2
**Duration:** 12 weeks

---

## 1. Abstract

This project implements a SHA-256 hash accelerator on the Zynq-7000 programmable logic and answers a specific architectural question: **does loop unrolling improve throughput for a hash function whose rounds are strictly sequential?**

The SHA-256 compression round is decomposed into its constituent operations. The four logical functions — Ch, Maj, Σ₀ and Σ₁ — reduce to two-level XOR and AND networks, because the ROTR and SHR operations they are built from are fixed bit reorderings realised in hardware as pure routing with zero logic cost. The message schedule uses a rolling sixteen-word window rather than storing all sixty-four expanded words, exploiting the fact that W[t] depends only on W[t−2], W[t−7], W[t−15] and W[t−16]. There is no multiplication anywhere in SHA-256, so the design occupies **zero DSP48 slices**; the entire critical path is modulo-2³² addition.

Two configurations are built from the identical round module. **Configuration A** executes one round per clock cycle, requiring 66 cycles per 512-bit block. **Configuration B** chains two rounds combinationally, requiring 34 cycles — a 1.94× reduction. Because round *t+1* consumes the output of round *t*, the two unrolled rounds cannot be separated by a pipeline register without forfeiting the cycle saving, so Configuration B's critical path contains two five-input adder chains in series and its maximum frequency must fall. Whether the cycle-count saving outweighs the frequency loss is measured rather than assumed.

Correctness is established against the published test vectors of NIST FIPS 180-4, including multi-block chaining. The accelerator is deployed as a complete PS–PL co-design in which a Vitis bare-metal application on the ARM Cortex-A9 pads the message, streams 512-bit blocks through AXI DMA, retrieves the digest, verifies it against the reference vectors, and reports measured throughput against a software implementation on the same processor.

---

## 2. Motivation and Problem Statement

SHA-256 underpins TLS certificates, digital signatures, password storage, software integrity verification and blockchain proof-of-work. It is also structurally interesting for hardware implementation in a way that distinguishes it sharply from block ciphers.

**The central observation:** a block cipher in ECB mode processes independent blocks, so an unrolled implementation can be pipelined — registers between stages hold the combinational depth per stage constant, frequency is preserved, and throughput scales linearly with area. A hash function cannot do this within a single message. Round *t+1* consumes round *t*'s working variables, and blocks chain through the hash value. Unrolling therefore stacks combinational adder chains and **must** cost frequency.

This yields a genuine engineering question with a non-obvious answer:

> Configuration B needs 1.94× fewer cycles per block. Its maximum frequency will be lower. Is the product a net gain, a net loss, or approximately a wash — and what does the answer say about parallelising sequential cryptographic primitives on FPGA fabric?

Three supporting observations shape the implementation:

1. **The rotations are free.** ROTR^n and SHR^n are fixed bit reorderings. In fabric they are routing: zero LUTs, zero flip-flops, zero delay. Each Σ function is a three-input XOR of rewired copies of one operand.

2. **The message schedule needs sixteen words, not sixty-four.** A naive implementation stores the full expanded schedule — 2048 bits. The recurrence only reaches back sixteen words, so a sixteen-deep shift register suffices, saving 1536 bits of storage for no functional cost.

3. **All the cost is addition.** With rotations free and the logical functions shallow, the critical path of a round is the five-input modulo-2³² addition forming T1. This is precisely why unrolling is expensive.

**Problem statement:** design a SHA-256 compression core for XC7Z020, implement it in an iterative and a two-way unrolled configuration built from identical submodules, verify both exactly against NIST FIPS 180-4 vectors including multi-block chaining, and determine by measurement whether unrolling yields a net throughput benefit on this device.

---

## 3. Objectives

| # | Objective | Measurable success criterion |
|---|---|---|
| O1 | Implement the six logical functions and the K constant ROM | Each matches the Python golden model; K ROM matches FIPS 180-4 §4.2.2 |
| O2 | Implement the rolling sixteen-word message schedule | W[0..63] matches the golden schedule for a known block |
| O3 | Build Configuration A (iterative, 1 round/cycle) | Correct digest for all NIST vectors; 66 cycles per block |
| O4 | Build Configuration B (2× unrolled, 2 rounds/cycle) | Bit-identical digest to Config A; 34 cycles per block |
| O5 | Integrate as a PS–PL system over AXI4-Lite and AXI4-Stream/DMA | Arbitrary-length message hashed correctly on hardware |
| O6 | Determine whether unrolling pays | Post-route Fmax and area for both; net throughput compared |

---

## 4. Algorithm Background

SHA-256 (FIPS 180-4) produces a 256-bit digest from a message of arbitrary length. The message is padded to a multiple of 512 bits and processed one block at a time, each block updating a 256-bit chaining value.

### 4.1 Structure

```
  H := H(0)                                    eight 32-bit initial values
  for each 512-bit block M:
      W[0..15]  := M                           message words
      W[t]      := σ₁(W[t-2]) + W[t-7] + σ₀(W[t-15]) + W[t-16]     16 ≤ t ≤ 63
      a..h      := H
      for t = 0 to 63:
          T1 := h + Σ₁(e) + Ch(e,f,g) + K[t] + W[t]
          T2 := Σ₀(a) + Maj(a,b,c)
          h:=g  g:=f  f:=e  e:=d+T1  d:=c  c:=b  b:=a  a:=T1+T2
      H := H + (a..h)                          element-wise, mod 2³²
```

Note that six of the eight working-variable updates are a pure rename — free in hardware. Only *a* and *e* require arithmetic.

### 4.2 The logical functions

```
  Ch(x,y,z)  = (x AND y) XOR (NOT x AND z)          bitwise "choose"
  Maj(x,y,z) = (x AND y) XOR (x AND z) XOR (y AND z)  bitwise majority

  Σ₀(x) = ROTR²(x)  XOR ROTR¹³(x) XOR ROTR²²(x)
  Σ₁(x) = ROTR⁶(x)  XOR ROTR¹¹(x) XOR ROTR²⁵(x)
  σ₀(x) = ROTR⁷(x)  XOR ROTR¹⁸(x) XOR SHR³(x)
  σ₁(x) = ROTR¹⁷(x) XOR ROTR¹⁹(x) XOR SHR¹⁰(x)
```

Every rotation is a compile-time constant, so each Σ costs one three-input XOR per bit and nothing else.

### 4.3 The constants

The eight initial hash values are the first 32 bits of the fractional parts of the square roots of the first eight primes. The sixty-four round constants K[t] are the first 32 bits of the fractional parts of the cube roots of the first sixty-four primes.

These are **"nothing up my sleeve" numbers**: derived from a publicly verifiable mathematical procedure so that no party can be accused of embedding a hidden trapdoor in them. It is worth one sentence in the report — it demonstrates understanding of cryptographic design intent rather than just the arithmetic.

### 4.4 The rolling message schedule

The recurrence reaches back at most sixteen words. Maintaining a sixteen-deep window `w[0..15]` holding W[t..t+15]:

```
  round t consumes  w[0]
  w_new = σ₁(w[14]) + w[9] + σ₀(w[1]) + w[0]        ( = W[t+16] )
  shift down by one; load w_new into w[15]
```

This is a standard optimisation and reduces schedule storage from 2048 bits to 512.

---

## 5. Architecture

### 5.1 Top level

```
┌──────────────────────── ZedBoard XC7Z020 ────────────────────────┐
│  PROCESSING SYSTEM (PS)          │   PROGRAMMABLE LOGIC (PL)      │
│                                  │                                │
│  ARM Cortex-A9 @ 667 MHz         │   ┌──────────────────────┐     │
│    • Vitis bare-metal app        │   │ AXI4-Lite Registers  │     │
│    • Message padding (FIPS 5.1.1)│◄──┤  init / start        │     │
│    • Block streaming             │   │  status / done       │     │
│    • Digest readback + verify    │   │  digest[255:0]       │     │
│    • Software SHA-256 baseline   │   └──────────┬───────────┘     │
│    • UART report                 │              │                 │
│                                  │   ┌──────────▼───────────┐     │
│  DDR3 (512 MB)                   │   │ AXI4-Stream Slave    │     │
│    • Message buffer              │   │ 512-bit block in     │     │
│    • Padded block buffer         │   └──────────┬───────────┘     │
│         │  AXI-HP                │              │                 │
│         └────► AXI DMA ──────────┼──►┌──────────▼───────────┐     │
│                                  │   │ MESSAGE SCHEDULE     │     │
│                                  │   │ rolling 16-word window│     │
│                                  │   │ σ₀, σ₁, 4-input add  │     │
│                                  │   └──────────┬───────────┘     │
│                                  │              │ W[t]            │
│                                  │   ┌──────────▼───────────┐     │
│                                  │   │ COMPRESSION ROUND    │     │
│                                  │   │ Ch · Maj · Σ₀ · Σ₁   │     │
│                                  │   │ T1 5-input add       │     │
│                                  │   │                      │     │
│                                  │   │ CONFIG A : ×1        │     │
│                                  │   │ CONFIG B : ×2 chained│     │
│                                  │   └──────────┬───────────┘     │
│                                  │   ┌──────────▼───────────┐     │
│                                  │   │ CHAINING VALUE H0-H7 │     │
│                                  │   │ 8 × 32-bit accumulate│     │
│                                  │   └──────────────────────┘     │
└───────────────────────────────────────────────────────────────────┘
```

### 5.2 Configuration A — iterative

One `sha256_round_comb` instance. The eight working variables feed back through it, one round per cycle.

| | |
|---|---|
| Cycles per block | 1 load + 64 rounds + 1 hash update = **66** |
| Throughput @ 100 MHz | 512 bits ÷ 66 cycles ≈ **776 Mbps** |
| Critical path | one five-input 32-bit adder chain |

### 5.3 Configuration B — two-way unrolled

Two `sha256_round_comb` instances chained combinationally. The message-schedule window advances by two words per cycle.

| | |
|---|---|
| Cycles per block | 1 load + 32 double-rounds + 1 hash update = **34** |
| Throughput @ 100 MHz **if Fmax held** | ≈ **1.51 Gbps** |
| Critical path | **two** five-input adder chains in series |
| Expected Fmax | substantially lower — the point of the experiment |

**The break-even condition.** Configuration B is a net throughput win if and only if

```
  Fmax(B) / Fmax(A)  >  34 / 66  =  0.515
```

That single inequality is the project's result. It is stated in advance, in the report, before the measurement is taken — which is the honest way to run an experiment.

**Why the message schedule is not the problem.** W[t+16] and W[t+17] both depend only on the current window contents:

```
  w_new1 = σ₁(w[14]) + w[9]  + σ₀(w[1]) + w[0]
  w_new2 = σ₁(w[15]) + w[10] + σ₀(w[2]) + w[1]
```

There is no serial dependency between them, so the schedule unrolls for free. Only the compression rounds stack. Identifying precisely *where* the dependency lives is a substantive part of the analysis.

### 5.4 Resource projection

| Block | Config A | Config B |
|---|---|---|
| Working + chaining registers | ~512 FF | ~512 FF |
| Message schedule window | ~512 FF | ~512 FF |
| Round logic (Ch, Maj, Σ, adders) | ~450 LUT | ~900 LUT |
| Message schedule arithmetic | ~160 LUT | ~320 LUT |
| K ROM (LUT-based) | ~200 LUT | ~400 LUT |
| Hash update adders | ~256 LUT | ~256 LUT |
| Control FSM and counters | ~60 LUT | ~60 LUT |
| **Core subtotal** | **~1,150 LUT** | **~1,950 LUT** |
| AXI4-Lite + AXI4-Stream + DMA | ~2,500 LUT | ~2,500 LUT |
| **Total** | **~3,700 / 53,200 (7%)** | **~4,500 / 53,200 (8%)** |
| **BRAM** | 0 (LUT ROM) | 0 |
| **DSP48E1** | **0 / 220** | **0 / 220** |

Both configurations are small. Area is not the constraint here — **frequency is**, which is what makes this a frequency study rather than an area study.

### 5.5 Performance projection

| | Config A | Config B | ARM software |
|---|---|---|---|
| Cycles per 512-bit block | 66 | 34 | ~1,400 |
| Throughput @ 100 MHz | ~776 Mbps | ~1.51 Gbps *if Fmax held* | ~250 Mbps |
| Realistic speedup over software | ~3× | measured | — |

**An honest note on the modest speedup.** SHA-256 is built from 32-bit addition, XOR and rotation — precisely the operations a general-purpose ALU executes in a single cycle. Unlike AES, whose GF(2⁸) arithmetic a processor must emulate, SHA-256 has nothing the CPU is bad at. A hardware speedup of roughly 3× is therefore expected and correct.

The value of a SHA-256 accelerator is **offload and deterministic latency**, not raw throughput multiplication. Stating this plainly is better engineering than quoting an inflated figure.

---

## 6. Reference Tables

### 6.1 Ch — bitwise choose

| x | y | z | Ch | Behaviour |
|---|---|---|---|---|
| 0 | 0 | 0 | 0 | x=0 → select z |
| 0 | 0 | 1 | 1 | x=0 → select z |
| 0 | 1 | 0 | 0 | x=0 → select z |
| 0 | 1 | 1 | 1 | x=0 → select z |
| 1 | 0 | 0 | 0 | x=1 → select y |
| 1 | 0 | 1 | 0 | x=1 → select y |
| 1 | 1 | 0 | 1 | x=1 → select y |
| 1 | 1 | 1 | 1 | x=1 → select y |

Ch is a bitwise 2:1 multiplexer with x as the select line.

### 6.2 Maj — bitwise majority

| x | y | z | Maj | Ones |
|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 0 |
| 0 | 0 | 1 | 0 | 1 |
| 0 | 1 | 0 | 0 | 1 |
| 0 | 1 | 1 | 1 | 2 |
| 1 | 0 | 0 | 0 | 1 |
| 1 | 0 | 1 | 1 | 2 |
| 1 | 1 | 0 | 1 | 2 |
| 1 | 1 | 1 | 1 | 3 |

Maj is 1 exactly when two or more inputs are 1 — a 3-input majority gate, one LUT per bit.

### 6.3 ROTR / SHR bit mapping — why rotation is free

For Σ₀(x) = ROTR²(x) ⊕ ROTR¹³(x) ⊕ ROTR²²(x), output bit *i* is:

| Output bit | from ROTR² | from ROTR¹³ | from ROTR²² |
|---|---|---|---|
| out[0] | x[2] | x[13] | x[22] |
| out[1] | x[3] | x[14] | x[23] |
| out[9] | x[11] | x[22] | x[31] |
| out[31] | x[1] | x[12] | x[21] |

General form: `out[i] = x[(i+2) mod 32] ⊕ x[(i+13) mod 32] ⊕ x[(i+22) mod 32]`

Every index is a compile-time constant. The mapping is **wires**, and the only logic is one 3-input XOR per bit — 32 LUTs for the whole function.

SHR differs only in that shifted-in bits are hard zeros rather than wrapped: `SHR³(x)[i] = x[i+3]` for i ≤ 28, and 0 for i > 28.

### 6.4 Control FSM state table

| Present state | Condition | Next state | Action |
|---|---|---|---|
| IDLE | `block_valid` | ROUND | load W[0..15]; load a..h from H (or H(0) if `init`) |
| ROUND | `t < 63` (A) / `t < 62` (B) | ROUND | execute round(s); advance schedule window |
| ROUND | `t = 63` (A) / `t = 62` (B) | FINAL | last round complete |
| FINAL | — | IDLE | H += a..h; assert `digest_valid` |

---

## 7. Verification Strategy

FIPS 180-4 and the NIST Cryptographic Algorithm Validation Program publish reference digests, and the golden model emits the per-round working-variable trace, so verification is hierarchical rather than end-to-end only.

| Level | What is checked | Against |
|---|---|---|
| Σ₀, Σ₁, σ₀, σ₁ | Known values | Python golden model |
| Ch, Maj | Selector and majority behaviour | Truth tables §6.1–6.2 |
| K ROM | Boundary entries K[0], K[15], K[32], K[63] | FIPS 180-4 §4.2.2 |
| Message schedule | W[0..63] for a known block | Golden schedule file |
| Per-round a..h | All 64 rounds | Golden trace file |
| Single-block digest | `"abc"`, empty message | NIST vectors |
| Multi-block chaining | 56-byte message → 2 blocks | NIST vector |
| Config A vs Config B | Bit-identical digest | Each other |
| Cycle counts | 66 and 34 | Design intent |

The cross-validation row is a strong self-check requiring no external reference: the two configurations share submodules but differ in control and unroll depth, so a control-path error in either breaks the match immediately.

---

## 8. Design Flow

```
① MODEL        Python SHA-256 reference; emit K constants, padded blocks,
               per-round trace, message schedule
                       ↓
② PRIMITIVES   Ch, Maj, Σ₀, Σ₁, σ₀, σ₁, K ROM — each verified alone
                       ↓
③ ROUND        sha256_round_comb; verify T1/T2 against the golden trace
                       ↓
④ CONFIG A     Iterative core + FSM; verify NIST vectors, single and multi-block
                       ↓
⑤ CONFIG B     Two rounds chained; verify identical digest to Config A
                       ↓
⑥ INTEGRATE    AXI4-Lite + AXI4-Stream wrappers; IP packaging; block design
                       ↓
⑦ IMPLEMENT    Synthesis → place → route for BOTH configs under identical
               constraints; record area and Fmax
                       ↓
⑧ SOFTWARE     Vitis: padding, block streaming, digest readback, verification,
               timing; software SHA-256 baseline
                       ↓
⑨ ANALYSE      Evaluate Fmax(B)/Fmax(A) against the 0.515 break-even threshold
                       ↓
⑩ DELIVER      Report, waveforms, demo, LMS submission
```

---

## 9. Twelve-Week Plan

| Week | Activity | Exit criterion |
|---|---|---|
| 1 | Python reference; generate K constants, vectors, per-round trace | Model passes all five FIPS 180-4 vectors |
| 2 | Logical functions and K ROM in Verilog | Each verified against the model |
| 3 | Rolling message schedule | W[0..63] matches the golden schedule |
| 4 | `sha256_round_comb` + Config A FSM | Round matches the golden trace |
| 5 | Config A full cipher | Correct digest, single and multi-block |
| 6 | **Buffer week** | — |
| 7 | AXI4-Lite + AXI4-Stream wrappers, IP packaging | AXI protocol checks clean |
| 8 | Vivado block design, DMA, Config A implementation | Timing closed; area and Fmax recorded |
| 9 | Vitis application; on-board bring-up and verification | Hardware digest matches NIST |
| 10 | Config B; implementation; **the Fmax comparison** | Both characterised; break-even evaluated |
| 11 | Software baseline; throughput measurement; report drafting | All data collected |
| 12 | Waveforms, demo, final submission | Deliverables complete |

Week 6 is genuine buffer. **Configuration B is scheduled at Week 10**, after Configuration A works on hardware, so a schedule slip degrades the project to a complete verified single-configuration deliverable rather than a failure.

---

## 10. Evaluation Metrics

| Metric | Method | Baseline | Target |
|---|---|---|---|
| Functional correctness | NIST vectors, hierarchical | FIPS 180-4 | Exact match |
| Cross-validation | Bit-identical digest | Config A vs B | Exact match |
| Cycles per block | Simulation counter | Design intent | 66 and 34 |
| Maximum frequency | Post-route timing, identical constraints | Config A vs B | Measured |
| **Fmax ratio vs 0.515** | Derived | Break-even threshold | **The headline result** |
| Net throughput | Cycles × Fmax | Each other | Measured |
| LUT / FF / BRAM | Post-implementation report | Each configuration | A ≈ 7%, B ≈ 8% |
| DSP48E1 usage | Utilisation report | — | Exactly 0 |
| Speedup over software | ARM global timer | Cortex-A9 software SHA-256 | ~3× (honest) |

---

## 11. Deliverables and Rubric Mapping

| Requirement | Deliverable |
|---|---|
| ① Program | Verilog RTL (both configs) + Vitis C application + Python reference |
| ② Output verification | NIST conformance at eight levels; cross-check between configurations |
| ③ Waveform (3–5) | (a) compression round showing T1/T2 formation (b) message-schedule window advancing (c) Σ function as pure rewiring (d) AXI4-Lite digest readback (e) AXI4-Stream block transfer with TLAST |
| ④ Truth table | Ch; Maj; ROTR/SHR bit mapping; control FSM state table |
| ⑤ Circuit / block diagram | Round datapath → iterative vs unrolled topology → full Zynq block design |
| ⑥ End-to-end product | Message in over UART, verified digest out, with measured throughput |
| Tools mandated | Vivado 2022.2 (RTL, both implementations, timing) + Vitis 2022.2 (PS application) |

---

## 12. Scope Boundaries

**In scope:** SHA-256, 512-bit block compression in hardware, multi-block chaining, two configurations, PS–PL integration, FIPS 180-4 conformance.

**Out of scope, with reasons:**

- **Hardware message padding** — trivial bookkeeping performed by the PS. A hardware padder adds byte-alignment logic and a length counter for no insight into the unrolling question. Documented as future work.
- **SHA-224 / SHA-384 / SHA-512** — SHA-224 is only a change of initial values; the 384/512 variants require a 64-bit datapath and eighty rounds, making them a different design.
- **HMAC-SHA256** — two nested hash invocations plus key padding; a wrapper around this core, not a modification of it.
- **Four-way multi-stream interleaving** — the architecturally correct way to obtain high hash throughput, since *independent messages* pipeline perfectly even though a single message cannot. Genuinely interesting and the natural next step, but a third configuration beyond this scope.
- **Side-channel resistance** — a separate research field.

Naming exclusions with technical reasons demonstrates command of the topic more convincingly than attempting all of it superficially.

---

## 13. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Big-endian word ordering errors in block loading | **High** | High | The classic hash bug. Golden model emits blocks in exactly the expected order; verified before RTL integration |
| Message schedule window off-by-one | **High** | Medium | Golden schedule file gives W[0..63]; compared word by word rather than only at the digest |
| Forgetting the final H += a..h accumulation | Medium | High | Caught immediately by the `"abc"` vector |
| Config B fails timing badly | Medium | **Low** | This is a *result*, not a failure. A large frequency drop is the answer to the research question. |
| Multi-block chaining not carried forward | Medium | High | Explicitly tested by the 56-byte two-block NIST vector |
| Scope creep into HMAC or SHA-512 | Medium | High | Frozen in Week 1 |
| Placement-season disruption | High | Medium | Week 6 buffer; Config A demonstrable by Week 9 |

---

## 14. Cover-Page Summary

> This project implements a SHA-256 hash accelerator on the Zynq-7000 XC7Z020 and determines by measurement whether loop unrolling benefits a cryptographic primitive whose rounds are strictly sequential. The compression round is built from bitwise choose and majority functions and four sigma functions, all of which reduce to shallow XOR and AND networks because their constituent rotations and shifts are fixed bit reorderings realised as pure routing. The message schedule uses a rolling sixteen-word window rather than storing all sixty-four expanded words. SHA-256 contains no multiplication, so the design occupies zero DSP48 slices and its critical path is modulo-2³² addition alone. Two configurations are built from the identical round module: an iterative core requiring 66 cycles per 512-bit block, and a two-way unrolled core requiring 34. Because consecutive rounds are data-dependent, the unrolled configuration cannot be pipelined without forfeiting the cycle saving, so its maximum frequency necessarily falls; the design is a net throughput improvement only if that frequency exceeds 51.5% of the iterative core's. Both configurations are verified exactly against NIST FIPS 180-4 vectors including multi-block chaining, cross-validated against each other, and deployed as a complete PS–PL co-design driven by a Vitis bare-metal application on the ARM Cortex-A9.

---

*End of synopsis.*
