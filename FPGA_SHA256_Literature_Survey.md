# Literature Survey

## Unrolling Analysis of a SHA-256 Hardware Accelerator on Zynq-7000

**Author:** Amritha S (23BEC1368)
**Platform:** ZedBoard / XC7Z020-1CLG484C · Vivado 2022.2 · Vitis 2022.2
**Revision:** v2 — September 2026 (supersedes the Review 1 survey, retained as `FPGA_SHA256_Literature_Survey.v1-review1.md.bak`)

---

> **Verification status — read this first.**
> Every citation in this revision has been checked against a live record (publisher page, DOI resolver, IEEE Xplore, dblp or IACR ePrint). Venue, year, volume and page numbers are as printed by the publisher. §10 records exactly what was verified for each entry and flags the three that remain unconfirmed.
>
> The Review 1 survey was assembled from memory and carried `[VERIFY]` markers throughout. Those markers are gone because the checks were done — **not** because they were deleted. All eight flagged entries survived verification unchanged.
>
> **What did not survive is the framing.** Review 1 asserted that the SHA-256 hardware design space "was mapped between 2002 and 2009." That is false. There is an active 2022–2026 literature on exactly this question, including a 2022 result that contradicts this project's central hypothesis and a 2026 paper on this project's own board. §3 is the consequence, and it is now the centre of this document.

---

## 1. Scope and method

This survey is organised **recency-first**. Cryptographic hardware is not a settled field kept alive by textbooks; SHA-256 FPGA implementation has produced peer-reviewed work in every year from 2022 to 2026, and the papers that constrain this project were published in the last three years, not the first decade of the century.

| Cluster | Question | Where |
|---|---|---|
| **A** | Why is a SHA-256 hardware core a 2026 problem rather than a solved 2006 one? | §2 |
| **B** | **What does the 2022–2026 literature say about unrolling SHA-256 on FPGA?** | **§3 — the core of this survey** |
| C | What foundational results still constrain the design? | §4 |
| D | What, precisely, is the open question this project answers? | §5 |
| E | What may this project legitimately claim, and what must it not? | §6–§8 |

The foundational 2002–2009 cluster is retained but compressed. It explains *why the round is slow*; it no longer describes the frontier.

---

## 2. Cluster A — Why SHA-256 hardware is a current problem

A survey that motivates SHA-256 with TLS and Bitcoin alone reads as fifteen years out of date. Three developments since 2024 put a hardware SHA-256 core back on the critical path.

### 2.1 FIPS 205 makes SHA-256 a signature primitive, not just an integrity primitive

NIST published **FIPS 205, the Stateless Hash-Based Digital Signature Standard (SLH-DSA)**, in **August 2024** [1]. SLH-DSA is the most conservative of NIST's standardised post-quantum signature schemes precisely because it derives its security *entirely* from hash functions — there is no lattice, no structured algebraic assumption. Its SHA-2 parameter sets are built on SHA-256.

The performance consequence matters to this project. A single SLH-DSA signature requires thousands of hash evaluations across WOTS⁺ chains and Merkle tree nodes. **The overwhelming majority of those hashes are mutually independent.** This is not a footnote; it is the workload shape that determines which parallelisation strategy is correct for a hash accelerator, and §5 returns to it.

**Sahu et al., SPHINCSLET (2025)** [2] is the current reference point: the first fully standard-compliant, area-efficient SLH-DSA hardware implementation, parameterisable across security levels and hash functions. Their SHA-2 configuration reports a 2×–4× signing speedup in 6K–15K LUTs on Artix-7, which they describe as the fastest SHA-2-based SLH-DSA hardware to date. The existence of a competitive area-efficient SHA-2 SLH-DSA accelerator establishes that the throughput of the underlying SHA-256 core is a live engineering variable in 2025–2026.

### 2.2 Blockchain-class IoT keeps the low-cost-FPGA case alive

**Santos Jr., da Silva, Torquato, Silva & Fernandes, *Sensors* 24(12):3908 (June 2024)** [3] implement SHA-256 on a Virtex-6 for IoT blockchain nodes, reporting roughly 1.4 Gbps from 16 clustered parallel cores at 0.503 W dynamic power — approximately a thousandfold dynamic-power reduction against the prior work they compare to.

**Their results carry a warning this project must read carefully.** At 16 cores the design occupies 107,609 LUTs (71.4% of the device) and the reported maximum frequency collapses to approximately **11.13 MHz**. Their per-hash cost is 65 clock cycles, essentially the iterative baseline. So: replicating whole cores bought throughput, and the frequency paid for it — at 71% occupancy, routing congestion dominated. This is the same class of effect this project predicts for unrolling, observed at a different level of the hierarchy, and published in 2024. It is direct supporting evidence for the structural argument in §5.1 and should be cited there rather than buried in a comparison table.

### 2.3 Zynq-class SoC FPGAs are the current deployment target

Two 2026 papers place SHA-256 accelerators on precisely this project's platform class:

- **Shah, Agrawal & Shah (2026)** [4] implement SHA-256 in VHDL on the **ZedBoard (Zynq-7000)** — the identical board — with a modular, pipelined datapath including message buffering and preprocessing, targeted at Bitcoin mining.
- **Bal (2026)** [5] compares **HLS-generated against hand-written RTL** SHA-256 accelerators on a PYNQ-Z1 (Zynq-7000) at a 100 MHz target, packaged as AXI IP — the same integration pattern this project uses. Both met timing; the RTL design was the more resource-efficient; both delivered approximately 16× over a software baseline.

§8 discusses why Bal's 16× and this project's expected ~3× are not in conflict, and why quoting Bal's figure as a target would be an error.

---

## 3. Cluster B — The recent unrolling literature (2022–2026)

**This is the cluster that defines the project's contribution.** It did not appear in the Review 1 survey at all.

### 3.1 Suhaili & Julai (2022) — the result this project exists to re-test

> **Suhaili, S. and Julai, N.** — "FPGA-based Implementation of SHA-256 with Improvement of Throughput using Unfolding Transformation." *Pertanika Journal of Science and Technology*, **30**(1), 581–603, 2022. [6]

The authors build three SHA-256 designs on an Altera **Arria II GX**: an iterative design, an unfolding-factor-two design, and an unfolding-factor-four design, simulated and verified in ModelSim. "Unfolding" is the DSP-architecture term for what this project calls unrolling.

Their factor-two design **reduces the block cost from 64 to 34 clock cycles** — bit-for-bit this project's Configuration B. Their reported outcomes:

| Design | Reported outcome |
|---|---|
| Iterative | Baseline |
| **Unfolding ×2** | **Surpassed the classic design in maximum frequency**; throughput 2429.52 Mbps; latency −46.4% |
| Unfolding ×4 | Highest throughput, 4196.30 Mbps; +13.7% over ×2; +58.1% over conventional; latency −45.1% |

**Read the second row against this project's hypothesis.**

This project's structural argument says that because round *t+1* consumes round *t*'s working variables, two unrolled rounds cannot be separated by a register without forfeiting the cycle saving; the five-input adder chains therefore stack in series and **maximum frequency must fall**. Suhaili and Julai report that on their device and flow, it rose.

A published, peer-reviewed, recent result contradicts the premise. That is not a reason to abandon the hypothesis. It is the reason the question is still open, and it is the strongest possible justification for running the experiment properly.

### 3.2 Why the contradiction is unresolved in the source

Three explanations are consistent with what the paper reports, and the paper does not distinguish between them:

1. **The comparison may not be constraint-matched.** Three designs synthesised as three separate projects can differ in effort level, strategy, optimisation directives and floorplan. A frequency difference then measures the toolchain, not the architecture.
2. **The device may absorb the second chain.** Arria II GX adaptive logic modules and Altera's carry-chain structure are not Xilinx 7-series CLBs with CARRY4 primitives. Whether a second five-input adder chain fits inside the same timing budget is a *device-family* question, and an Altera answer does not transfer to a Zynq-7020.
3. **The designs may not be architecturally isolated.** If the unfolded variant differs from the iterative one in any way beyond unroll depth — a retimed register, a restructured adder, a different schedule buffer — the measurement attributes to unrolling an effect caused by something else.

Distinguishing (1) from (2) from (3) requires an experiment where **the round logic is provably identical and the constraints are provably identical**. That experiment has not been published. It is what this project is.

### 3.3 Gamgam (2023) — unrolling *and* pipelining, on the closest architecture

> **Gamgam, O. B.** — "An Unrolled and Pipelined Architecture for SHA2 Family of Hash Functions on FPGA." *16th International Conference on Information Security and Cryptology (ISCTürkiye)*, IEEE, October 2023. [7]

Combines unrolling with pipelining for SHA-256 and SHA-512, reporting that SHA-512's 80-step block completes in 42 steps — the signature of two-way unrolling plus a pipeline stage (80/2 + 2), exactly analogous to the 64 → 34 transformation here.

**Relevance:** this is the closest published architecture to the C-slow / interleaved extension previously considered for this project, and it is two years old. Any claim of novelty for "unrolled plus pipelined SHA-2 on FPGA" is foreclosed by this paper. §7 states the consequence plainly.

### 3.4 The rest of the recent cluster

| Work | Year | Device | What it contributes |
|---|---|---|---|
| **Lawhale & Kale** [8] — "Efficient FPGA-Based Implementation of SHA-256 Hash Function for Higher Throughput," ICSM 2024, LNEE vol. 1381, Springer | 2025 | Stratix-III | VHDL/Quartus-II throughput optimisation reporting 1090.512 Mbps; confirms throughput tuning remains an active publication target |
| **Kumar et al.** [9] — "A Constructive High-Speed Crypto-mining Approach with Dual SHA-256 on an FPGA," VLSID 2025 | 2025 | Virtex-7 | Dual SHA-256 datapath; 6.09% speed/power gain, 13.40% functional-efficiency gain. Note the **scale of a credible 2025 improvement**: single-digit percent, not multiples |
| **Sahu et al., SPHINCSLET** [2] | 2025 | Artix-7 | SHA-2 SLH-DSA accelerator, 6K–15K LUTs; establishes the post-quantum demand for fast SHA-256 |
| **Santos Jr. et al.**, *Sensors* [3] | 2024 | Virtex-6 | 16 clustered cores, ~1.4 Gbps, 65 cycles/hash; **Fmax collapse to ~11 MHz at 71% occupancy** |
| **Shah, Agrawal & Shah** [4] | 2026 | **ZedBoard / Zynq-7000** | Pipelined VHDL SHA-256 on the identical board |
| **Bal** [5] | 2026 | PYNQ-Z1 / Zynq-7000 | HLS vs RTL at 100 MHz as AXI IP; RTL more area-efficient; ~16× over software |

### 3.5 What the recent cluster establishes

1. **Unrolling SHA-256 on FPGA is an actively published question in the 2020s** — Suhaili & Julai 2022, Gamgam 2023 — not a question closed in 2009.
2. **The published answers disagree with the structural prediction.** Suhaili & Julai report unrolling *helping* frequency.
3. **No published comparison isolates unroll depth as the only variable.** Every result compares separately-built designs.
4. **Core-level replication demonstrably costs frequency on FPGA** (Santos Jr. et al., ~11 MHz at 16 cores), which is consistent with the structural argument and inconsistent with a naive reading of Suhaili & Julai.
5. **Zynq-7000 is a current and contested target** — two 2026 papers, including one on this exact board.

---

## 4. Cluster C — The foundational layer

These results are not the frontier. They are retained because they explain *why* the round is slow, and every recent paper builds on them.

**The critical path is the five-input modulo-2³² addition forming T1.** Every serious hardware paper is about shortening it.

| Ref | Work | Contribution | Why it is still cited |
|---|---|---|---|
| [10] | **Chaves, Kuzmanov, Sousa & Vassiliadis**, CHES 2006 | **Operation rescheduling** — precompute part of T1 one cycle ahead so the adder chain splits across the register boundary, shortening the critical path without changing the round count. Also applies carry-save addition in the round. Reports >50% improvement for SHA-256 over commercial cores on Virtex-II Pro | The canonical answer to "how would you shorten the path without unrolling?" — and the basis of this project's entire cost argument |
| [11] | **McEvoy, Crowe, Murphy & Marnane**, ISVLSI 2006 | A VLSI architecture for SHA-256/512 that **combines pipelining and unrolling**, including a 2×-unrolled-pipelined SHA-2 core | **Corrected characterisation.** The Review 1 survey described this as a paper about balancing the message schedule against the compression function. It is not. It is a 2006 unrolled-and-pipelined SHA-2 paper, and it is therefore prior art for both Configuration B and the pipelined-interleaving extension. Misdescribing it would have concealed the closest classical prior art |
| [12] | **Dadda, Macchetti & Owen**, DATE 2004 Designers' Forum, pp. 70–76 | Carry-save adder trees in the compressor and expander; critical-path reduction in 0.13 µm | CSA is the standard mitigation for the T1 bottleneck. **Caution:** a near-twin paper by the same authors exists at GLSVLSI 2004 (DOI `10.1145/988952.989053`) with a similar title — cite the correct one |
| [13] | **Michail, Kakarountas, Milidonis & Goutis**, IEEE TDSC 6(4):255–268, 2009 | Systematic top-down methodology for unrolling and pipelining hashing cores | The methodological ancestor. Its comparisons span papers and devices; this project's span one board and one constraint set |
| [14] | **Ting, Yuen, Lee & Leong**, FPL 2002, LNCS 2438 | The iterative baseline: 1261 slices, 87 MB/s at 88 MHz on Virtex XCV300E-8; 53 MB/s measured in-system at 66 MHz | Configuration A follows this architecture. Note their honesty about measured-versus-synthesised throughput — a model for §8 |
| [15] | **Sklavos & Koufopavlou**, ISCAS 2003 | Early comparative SHA-2 hardware study; 83 MHz, 326 Mbps on Virtex v200pq240 | Historical area/performance baseline |
| [16] | **Sklavos & Koufopavlou**, *J. Supercomputing* 31:227–248, 2005 | FPGA implementations across the SHA-2 family | Cross-variant figures |
| [17] | **Padhi & Chaudhari**, *Microprocessors and Microsystems*, 2019 | Fully-pipelined SHA-1/SHA-256 hashing cores using BRAM; >300 MHz via loop unrolling and precomputation; 154.88 Gbps and 10.94 Mbps/slice on Kintex-7 | The high-water mark for pipelined hashing throughput, and the reason throughput-per-slice is the honest comparison metric |

### 4.1 Specification and cryptographic context

| Ref | Work | Role |
|---|---|---|
| [18] | **NIST, FIPS PUB 180-4**, *Secure Hash Standard*, August 2015 | **The primary reference.** Padding §5.1.1, initial hash values §5.3.3, K constants §4.2.2, logical functions §4.1.2, compression §6.2.2, plus worked examples. Every element of this project's verification strategy derives from it. Free, permanent, authoritative — there is no ambiguity about ground truth |
| [19] | **NIST CAVP**, Secure Hashing test vectors | Short-message, long-message and Monte Carlo sets. The long-message set exercises multi-block chaining, which single-block vectors do not |
| [20] | **NIST SP 800-107** | Security strengths; supports one paragraph on why SHA-256 rather than SHA-1 or SHA-3 |
| [21] | **Gilbert & Handschuh**, SAC 2003, LNCS 3006, pp. 175–193 | Early SHA-2 cryptanalysis. Supports "SHA-256 remains unbroken." Do not overstate — this is a hardware project |
| [22] | **Wang, Yin & Yu**, CRYPTO 2005 | The theoretical SHA-1 break that drove SHA-2 migration |
| [23] | **Stevens, Bursztein, Karpman, Albertini & Markov**, CRYPTO 2017 | The practical SHAttered collision. One sentence of motivation |

### 4.2 Integration standards

| Ref | Document |
|---|---|
| [24] | ARM, *AMBA AXI and ACE Protocol Specification* (IHI 0022) — TVALID/TREADY/TLAST semantics for the waveform deliverable |
| [25] | Xilinx, *AXI Reference Guide* (UG1037) |
| [26] | Xilinx, *AXI DMA LogiCORE IP Product Guide* (PG021) — register map and driver model |
| [27] | Xilinx, *Zynq-7000 SoC Technical Reference Manual* (UG585) — AXI-HP ports and PS–PL paths |
| [28] | Xilinx, *Vivado Design Suite User Guide: Synthesis* (UG901) — read the ROM inference section before fixing the K constants in LUT or BRAM |
| [29] | Avnet, *ZedBoard Hardware User's Guide* |

---

## 5. Cluster D — The gap, stated precisely

### 5.1 The structural argument

State this in the report in the project's own words, citing [10], [11] and [3] in support:

> In a block cipher operating in ECB mode, blocks are independent. An unrolled implementation can therefore be pipelined: registers between stages hold the combinational depth per stage constant, maximum frequency is preserved, and throughput scales linearly with area.
>
> A hash function cannot do this within one message. Round *t+1* consumes the working variables produced by round *t*, and consecutive blocks chain through the hash value. Two unrolled rounds cannot be separated by a register without forfeiting the cycle-count saving that motivated unrolling. The adder chains stack in series, and maximum frequency must fall.
>
> The design is therefore a net throughput improvement if and only if the frequency retained exceeds the cycle-count ratio.

### 5.2 The threshold

Two thresholds apply, and the distinction is itself a finding.

| Level | Cycles A | Cycles B | Break-even ratio |
|---|---|---|---|
| Compression core only | 66 | 34 | 34/66 = **0.515** |
| Full system over AXI | 85 | 53 | 53/85 = **0.624** |

The system figures include a **fixed 19-cycle streaming overhead** — sixteen AXI beats plus handshake — identical in both configurations. A fixed overhead dilutes a proportional saving, so the bar unrolling must clear in the deployed system is **0.624**, not 0.515.

Review 1 committed to 0.515 from core cycle counts before any integration existed. Integration exposed the overhead and the prediction was refined rather than abandoned. **Report both numbers and the reason they differ.** A prediction that moved for a stated, measured reason is stronger evidence of real engineering than one that never moved.

### 5.3 The open question, and the three-way experiment

> Suhaili and Julai (2022) report that two-way unrolling of SHA-256 *increases* maximum frequency on an Arria II GX, contradicting the structural prediction that stacked five-input adder chains must reduce it. Their three designs, like every comparison in the literature, are separately constructed; the measurement therefore cannot distinguish an architectural effect from a device-family effect or a toolchain effect.
>
> This project re-tests the claim as a controlled experiment, and extends it to a third configuration that the literature has never placed in the same comparison.

**The design space is two-dimensional, and the literature has only ever sampled it one point at a time.** Unroll depth **U** and interleave depth **C** are independent axes:

| | **U = 1** | **U = 2** |
|---|---|---|
| **C = 1** | **A** — 66 cyc/block, depth 1 round | **B** — 34 cyc/block, depth **2 rounds** |
| **C = 2** | **C** — 33 eff. cyc/block, depth 1 round | **D** — 17 eff. cyc/block, depth **2 rounds** |

| | Structure | Round instances |
|---|---|---|
| **A** iterative | `reg → round → reg` | 1 |
| **B** 2× unrolled | `reg → round → round → reg` | 2 combinational |
| **C** 2-msg C-slow | `reg → round → reg → round → reg` | 2 register-separated |
| **D** unrolled + interleaved | `reg → round → round → reg → round → round → reg` | 4 |

The interleaved configurations run two independent messages through the round instances: round *t+1* of message 0 and round *t* of message 1 have no data dependency, so the register between stages is legal. Each message advances a full stage per cycle, both simultaneously, and the effective per-block cost halves.

All four are built from a single out-of-context Tcl script under an identical, deliberately aggressive timing constraint, so every configuration is pushed to its own limit under the same pressure. The number of round instances and the placement of registers are the only variables.

### 5.4 The finding: the two axes behave differently, and orthogonally

Read the grid by row and by column, and the claim falls out before any number is measured.

**Configuration B trades frequency for cycles.** It buys a 1.94× cycle reduction and pays for it in critical path. Whether the trade is profitable is a genuine empirical question with a threshold that can come out either way — which is exactly what makes it a falsifiable prediction worth pre-registering.

**Configuration C trades area for frequency.** Its combinational depth is one round instance, identical to Configuration A, so its Fmax is not traded away at all; it pays instead in registers — two working-variable banks, two chaining-value sets, two schedule windows. It then retires a block every 33 effective cycles instead of 66.

So the interleaved configurations' advantage is **structural rather than empirical**: shorter effective cycle count at unchanged combinational depth. Barring a build error, they cannot lose. A measurement showing C below A, or D below B, indicates a constraint-set problem or a pipeline register retimed away — not an architectural failure.

**The orthogonality claim.** Because the interleave register does not touch the combinational path, the gain from moving down a column should be the same regardless of which column it is:

> gain(A→C)  ≈  gain(B→D)  ≈  2×,   independent of unroll depth
>
> gain(A→B)  ≈  gain(C→D),           independent of interleave depth

Measuring both axes independently, from one round module under one constraint set, is what separates this from a benchmark table. **No published SHA-256 study has done it.** The existing work samples single points: Suhaili & Julai vary U only [6]; McEvoy [11] and Gamgam [7] combine unrolling with pipelining at one operating point each; nobody reports the grid.

If confirmed, the statement is:

> **Unroll depth and interleave depth are orthogonal in SHA-256. Unrolling is a gamble on the device — it may or may not pay, and the recent literature disagrees with theory about which. Interleaving is a guaranteed linear area-for-throughput trade, and it holds at any unroll depth.**

**The consequence for the project is that the deliverable no longer depends on B's outcome.** B's threshold stays exactly as pre-registered and may still be missed; that remains a valid reportable finding. The column results supply a positive, quotable finding either way.

### 5.5 Why this matters now

Interleaving is standard practice in high-throughput hashing hardware, including Bitcoin mining ASICs, and it is published for SHA-2 on FPGA by McEvoy et al. [11] in 2006 and by Gamgam [7] in 2023. **The project claims no novelty in the technique** — see §7.

What has not been published is the **controlled 2×2 grid**: unroll depth and interleave depth varied independently, all four cores built from one round module, on one device, under one constraint set, reported as throughput-per-LUT. Every existing comparison samples isolated points, and most span separate papers and devices.

Its relevance has grown sharply. FIPS 205 SLH-DSA [1] is precisely a workload of thousands of independent hash evaluations per signature, and SPHINCSLET [2] is its current hardware exemplar. The question "which form of parallelism should a SHA-256 core use?" is a live 2026 design decision, not a retrospective one.

**The honest caveat, which must be stated and not buried:** interleaving helps only for independent messages. Single-message latency is unchanged — 66 cycles for C, 34 for D, no better than A and B respectively — and a lone message wastes one of the two slots.

---

## 6. Positioning

> SHA-256 hardware is a mature field with an active present. The classical architectural options were mapped between 2002 and 2009; unrolling on modern FPGA fabric has been re-examined continuously since 2022, and the published results are not consistent with one another or with the structural theory. This project does not claim a new architecture or a record throughput. It formulates the unrolling trade-off as an explicit, falsifiable inequality; builds two configurations from an identical round module under an identical constraint set so that unroll depth is the sole variable; verifies both exhaustively against NIST FIPS 180-4 vectors including multi-block chaining and per-round intermediate state; and reports the outcome against a recent published claim that predicts the opposite.

### Legitimate claims

1. **A stated hypothesis with a numeric threshold** — 0.515 at core level, refined to 0.624 at system level — declared before measurement.
2. **A controlled 2×2 design-space measurement.** All four configurations instantiate the same `sha256_round_comb` and build from one out-of-context script under one constraint set. No published SHA-256 study varies unroll depth and interleave depth independently on one device.
3. **A direct re-test of a specific recent result** — Suhaili & Julai (2022) — on a different device family, with the confound removed.
4. **An orthogonality claim about the design space**, not merely a ranking of implementations — that the frequency cost of unrolling and the area cost of interleaving are independent, so the two levers can be chosen separately.
5. **A result that does not depend on the measurement going a particular way.** Configuration B's outcome is genuinely open; the column results are structural. The project therefore yields a positive finding without compromising the falsifiability of the pre-registered prediction.
6. **Hierarchical verification** at eight levels including per-round `a..h` and the full `W[0..63]` schedule, not end-to-end digest matching alone.
7. **Four-way cross-validation** — bit-identical digests from A, B and both streams of C and D — an independent self-check requiring no external reference.
8. **Honest accounting of the modest software speedup** and the structural reason for it.

---

## 7. What this project must not claim

Stated explicitly, because each of these has been foreclosed by a paper in this survey.

| Do not claim | Foreclosed by |
|---|---|
| Novelty in SHA-256 architecture | The entire field |
| Novelty in unrolling SHA-256 on FPGA | Suhaili & Julai 2022 [6]; McEvoy et al. 2006 [11] |
| Novelty in combining unrolling with pipelining | McEvoy et al. 2006 [11]; Gamgam 2023 [7] |
| Novelty in multi-message interleaved hashing — **Configuration C's technique is not claimed as new** | Standard practice; [11], [7]; and prior patents including US9917689, US8856547, US7684563, US6091821. What is claimed is the controlled 2×2 measurement of it against unrolling, not inventing it |
| A record throughput | Padhi & Chaudhari 2019 [17] report 154.88 Gbps on Kintex-7 |
| Being first to put SHA-256 on a ZedBoard | Shah, Agrawal & Shah 2026 [4] |
| A power or energy result | Vivado's estimator is a model, not a measurement. No power claim can be defended from a ZedBoard without instrumented measurement |

**A modest accurate claim survives questioning; an inflated one does not.** The contribution here is experimental design and verification rigour, not architecture.

---

## 8. Two numbers that will be questioned

**"Your speedup over software is ~3×. Bal (2026) reports 16× on the same device family."**

Both can be correct, because the denominators differ. A speedup figure is only as meaningful as the software baseline it is measured against — an unoptimised or interpreted reference inflates it. This project's baseline is a compiled C SHA-256 running on the same Cortex-A9, which is the strict comparison. State the baseline explicitly, report the measured number honestly, and do not adopt another paper's ratio as a target.

The structural reason the ratio is modest: SHA-256 is built from 32-bit addition, XOR and rotation — exactly the operations a general-purpose ALU executes in one cycle each. Unlike a block cipher, whose finite-field arithmetic a processor must emulate, there is nothing here the CPU is bad at. The value of a SHA-256 accelerator is **offload and deterministic latency**, not raw throughput multiplication. Ting et al. [14] made the same distinction in 2002 by separating synthesised throughput from measured in-system throughput.

**"Suhaili & Julai got a frequency increase. Did you get it wrong?"**

That is the experiment, not an embarrassment. §5.3 is the answer. If the measured ratio on Zynq-7020 falls below threshold, the finding is that the 2022 result does not generalise across device families or does not survive constraint matching — and the controlled construction is what licenses that conclusion. If it clears the threshold, the structural argument needs revision and that is a more interesting result still. **Both outcomes are publishable; neither is a failure.**

---

## 9. Comparison table for the report

Columns: device, architecture, LUTs/slices, Fmax, throughput, throughput-per-area. Annotate every row with its device and year.

**Mandatory caveat:** results spanning Virtex-II (2003) to Zynq-7000 (2026) cross more than twenty years of process technology. Raw throughput comparison across that span is not meaningful. What transfers is the **structural relationship** — the ratio between iterative and unrolled configurations built under matched conditions — and that ratio is what this project measures. State this limitation rather than presenting a table that implies a 2026 student project has beaten a 2019 Kintex-7 result.

---

## 10. Citation verification record

| Ref | Verified | Confirmed against |
|---|---|---|
| [1] FIPS 205, Aug 2024 | ✅ | NIST CSRC publication record |
| [2] SPHINCSLET, 2025 | ✅ | ACM TECS `10.1145/3728469`; IACR ePrint 2025/621. Author list confirm before citing |
| [3] Santos Jr. et al., *Sensors* 24(12):3908, 2024 | ✅ | DOI `10.3390/s24123908`; full author list and all figures verified |
| [4] Shah, Agrawal & Shah, 2026 | ✅ | SmartCom 2025, LNNS vol. 1463, DOI `10.1007/978-981-96-7514-2_28` |
| [5] Bal, 2026 | ✅ | *Int. J. Adv. Eng. Pure Sci.* 38(2):272–280, 30 June 2026, DOI `10.7240/jeps.1864699` |
| [6] Suhaili & Julai, 2022 | ✅ | *Pertanika JST* 30(1):581–603 |
| [7] Gamgam, 2023 | ✅ | ISCTürkiye 2023, IEEE Xplore doc. 10336096 |
| [8] Lawhale & Kale, 2025 | ✅ | LNEE vol. 1381, DOI `10.1007/978-981-96-3644-0_26` |
| [9] Kumar et al., 2025 | ⚠️ | VLSID 2025, IEEE Xplore doc. 10900629 confirmed. **Full author list not confirmed** — check Xplore before citing |
| [10] Chaves et al., CHES 2006 | ✅ | LNCS 4249, DOI `10.1007/11894063_24` |
| [11] McEvoy et al., ISVLSI 2006 | ✅ | pp. 317–322, IEEE Xplore doc. 1602458 |
| [12] Dadda et al., DATE 2004 | ✅ | Designers' Forum, pp. 70–76. Distinct from the GLSVLSI 2004 twin |
| [13] Michail et al., TDSC 2009 | ✅ | 6(4):255–268, DOI `10.1109/TDSC.2008.15` |
| [14] Ting et al., FPL 2002 | ✅ | LNCS 2438, DOI `10.1007/3-540-46117-5_60` |
| [15] Sklavos & Koufopavlou, ISCAS 2003 | ✅ | DOI `10.1109/ISCAS.2003.1206214` |
| [16] Sklavos & Koufopavlou, 2005 | ✅ | *J. Supercomputing* 31:227–248 |
| [17] Padhi & Chaudhari, 2019 | ⚠️ | *Microproc. & Microsyst.*, ScienceDirect `S0141933118302758`; title and figures confirmed. **Author names and exact volume/pages not confirmed** |
| [18]–[20] NIST documents | ✅ | NIST CSRC |
| [21] Gilbert & Handschuh, SAC 2003 | ✅ | LNCS 3006, pp. 175–193, DOI `10.1007/978-3-540-24654-1_13`. Conference 2003; proceedings published 2004 |
| [22] Wang, Yin & Yu, CRYPTO 2005 | ⚠️ | Widely known; **not independently re-verified in this revision** |
| [23] Stevens et al., CRYPTO 2017 | ⚠️ | Widely known; **not independently re-verified in this revision** |
| [24]–[29] Standards and vendor docs | ✅ | Document numbers as published |

Four entries carry ⚠️. Resolve them before submission; do not let a viva find them first.

---

## 11. Anticipated questions

| Question | Answer |
|---|---|
| **"Hasn't unrolling SHA-256 already been done?"** | Yes — most recently by Suhaili & Julai in 2022, who reached 34 cycles per block exactly as we do, and by Gamgam in 2023. Their comparisons are between separately-built designs, so a frequency difference cannot be attributed to unroll depth rather than to the device family or the toolchain. We hold the round module and the constraint set identical so that unroll depth is the only variable, and we test whether their result reproduces. |
| **"Suhaili and Julai say unrolling improves frequency. You predict it falls."** | Correct, and that is why the experiment is worth running. Three explanations fit their data — unmatched constraints, an Altera carry-chain effect that does not transfer to Xilinx CLBs, or architectural differences beyond unroll depth. Our construction eliminates the first and third by design and isolates the second. |
| "Why no DSP slices?" | SHA-256 contains no multiplication — only 32-bit addition, XOR, AND and fixed bit reorderings. There is nothing for a DSP to do. |
| "Why are the rotations free?" | ROTR and SHR are compile-time-constant bit reorderings. In fabric they are routing: zero LUTs, zero delay. Each Σ function is one 3-input XOR per bit. |
| "Why store only 16 schedule words?" | W[t] depends only on W[t−2], W[t−7], W[t−15] and W[t−16]. A 16-deep rolling window suffices; storing all 64 wastes 1536 bits for no benefit. |
| "Why does unrolling cost frequency here but not in AES?" | AES-ECB blocks are independent, so unrolled rounds can be pipelined and combinational depth per stage stays constant. SHA-256 rounds are data-dependent — a register between them would forfeit the cycle saving, so the adder chains stack in series. |
| "Your speedup over software is only ~3×." | Expected and correct; see §8. The value is offload and deterministic latency, not raw throughput multiplication. |
| "How would you actually make this fast?" | Multi-stream interleaving through a pipelined round unit. Independent messages have no dependency, so N of them pipeline perfectly for N× throughput at N× registers and the same round logic. Published for SHA-2 by McEvoy et al. (2006) and Gamgam (2023), and newly important because FIPS 205 SLH-DSA is a workload of thousands of independent hashes. Documented future work — we do not claim it. |
| "How would you shorten the critical path without unrolling?" | Operation rescheduling (Chaves et al., CHES 2006): precompute part of T1 one cycle ahead so the adder chain splits across the register boundary. Also carry-save adders in the five-input sum (Dadda et al., DATE 2004). |
| "Why is padding in software?" | Deliberate scope decision. Padding is byte-alignment bookkeeping and a length counter; compression is the expensive part. A hardware padder adds control complexity and no insight into the unrolling question. Documented as future work. |
| **"Is any of this patentable?"** | No, and we do not claim it is. Every technique here is published: unrolling [6][11], pipelining [11][7], interleaving [11][7] and prior patents, operation rescheduling [10], carry-save addition [12]. The contribution is experimental method — a pre-registered threshold, a controlled variable, and hierarchical verification — which is a research contribution, not an inventive step. |

---

## 12. Search strings for ongoing verification

```
SHA-256 FPGA unfolding transformation throughput Suhaili
SHA-2 unrolled pipelined architecture FPGA 2023 2024 2025
SHA-256 accelerator Zynq AXI4-Stream HLS RTL comparison
SLH-DSA FIPS 205 SPHINCS+ hardware accelerator SHA-2 FPGA
"operation rescheduling" SHA-2 hardware critical path
"carry save adder" SHA-256 compression function
SHA-256 hash core throughput per slice Kintex Virtex
multi-stream interleaved hash pipeline independent messages
```

Prefer **CHES/TCHES**, **FPL**, **FCCM**, **DATE**, **ISVLSI**, **VLSID**, **IEEE TVLSI / TDSC** and **IACR ePrint** (eprint.iacr.org, free preprints of most CHES/TCHES papers). For the 2022–2026 cluster, also check *Sensors* (MDPI), *Microprocessors and Microsystems*, and Springer LNEE/LNNS conference series — that is where several of the recent results appeared.

---

## 13. Recommended reading order

1. **NIST FIPS 180-4** [18] — read it properly, including the worked examples
2. **Suhaili & Julai, 2022** [6] — *the paper this project re-tests; read it first among the research papers*
3. **Gamgam, 2023** [7] — unrolled and pipelined SHA-2, the nearest recent architecture
4. **McEvoy et al., ISVLSI 2006** [11] — the classical unrolled-and-pipelined result; read it to see what was already known in 2006
5. **Chaves et al., CHES 2006** [10] — operation rescheduling; the future-work citation
6. **Shah et al., 2026** [4] and **Bal, 2026** [5] — same board, same year; know what they did
7. **Santos Jr. et al., 2024** [3] — the frequency collapse under core replication
8. **Ting et al., FPL 2002** [14] — the iterative baseline
9. **NIST FIPS 205** [1] — why hash throughput matters again
10. **Xilinx UG901** [28] and **PG021** [26] — before the K-ROM decision and before touching the DMA

---

*End of survey — v2, September 2026.*
