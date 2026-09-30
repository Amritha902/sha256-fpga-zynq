# Patent Grilling — adversarial prior-art assessment

**SHA-256 accelerator on Zynq-7000 · Amritha S (23BEC1368) · 30 September 2026**

Every claim this project could plausibly make, attacked with the strongest
prior art I could find. Written adversarially on purpose: the point is to find
what kills each claim *before* an examiner or a reviewer does.

**Verdict up front: no claim survives. Present the project as a measurement
study, not as an invention.** §7 gives the framing that is defensible.

---

## 1. Claim: a two-message interleaved SHA-256 core (Config C)

**DEAD — and by a commercial product datasheet from 2010.**

**Helion Technology, *Tiny Hash Core Family for Lattice FPGA*, Full Datasheet,
Revision 1.0, 27 October 2010**, distributed by Lattice Semiconductor.

From the feature list on page 1:

> "Supports state unload/reload operations to optimise hashing of interleaved
> message streams"

And from the functional description:

> "Additionally using the state unload/reload functionality, the core may also
> switch between messages on a **block by block basis** in order to facilitate
> efficient handling of **multiple interleaved message streams** which require
> independent authentication."

That is a **shipping, purchasable FPGA IP core**, publicly documented sixteen
years ago, doing block-by-block switching between independent interleaved
message streams. It is the exact deployment concept behind Config C, sold as a
product before this project existed.

A commercial datasheet is among the worst kinds of prior art to face: it is
public, dated, unambiguous, and it demonstrates the idea was not merely
conceivable but *commercially routine*.

---

## 2. Claim: two messages in lockstep through a pipelined round (Config C/D)

**DEAD — by an applicant's own admission, in a patent filed 2023.**

**IBM, US20250070957A1, "High throughput data flow for SHA-2 hashing module"**,
inventors Mueller, Kumar, Fricke. Filed **22 August 2023**, published
**27 February 2025**.

In its background discussion of existing approaches, the application states:

> "It has two main ideas: (1) **Lockstep of two messages, to fully exploit a
> two-cycle pipeline** and not applicable for Central Processing Unit (CPU) use."

IBM is describing lockstep-of-two-messages-through-a-two-cycle-pipeline as
**known art that their invention is distinguished from**. When an applicant
characterises a technique as existing background in order to claim around it,
that is close to the strongest public admission available that the technique is
not novel.

IBM's own claimed invention is something else — partitioning the SHA-2 state
update into three blocks with backward data transfer — precisely because the
two-message lockstep route was already taken.

**This is the single most damaging document for Config C and Config D.**

---

## 3. Claim: hashing multiple independent messages simultaneously, generally

**DEAD several times over.** A non-exhaustive list, any one of which is fatal:

| Prior art | Date | What it establishes |
|---|---|---|
| **Gueron & Krasnov**, "Simultaneous hashing of multiple messages", IACR ePrint 2012/371 | 2012 | The multi-buffer method itself, named and published |
| **Intel IPP Crypto Multi-Buffer** | shipping since ~2020 | 8 independent cryptographic requests processed in parallel, commercial library |
| **Intel ISA-L**, **intel-ipsec-mb** | shipping | Multi-buffer hashes in production storage and IPsec stacks |
| **Intel US12413388B2**, "Methods and apparatus to hash data" | filed Dec 2021, granted Sep 2025 | Separates message schedule from compression rounds so one schedule serves multiple compressions across chunks; SIMD interleaved processing of independent blocks |
| **US9917689**, "Generating multiple secure hashes from a single data buffer" | granted 2018 | Interleaved segments → parallel digests |
| **US8856547**, SHA via SIMD parallel functional units | granted 2014 | Parallel independent hash lanes |
| **US7684563**, unified hash algorithm pipeline | granted 2010 | Multiple cores sharing one cryptographic unit |
| **US6091821**, "Pipelined hardware implementation of a hashing algorithm" | granted 2000 | The pipelined hash datapath itself |

The technique has been in commercial silicon and shipping software for over a
decade. Bitcoin mining ASICs have done it at scale since 2013.

---

## 4. Claim: unrolling combined with pipelining (Config D)

**DEAD — twice in the academic literature, one of which is already cited in our
own survey.**

- **McEvoy, Crowe, Murphy & Marnane**, "Optimisation of the SHA-2 Family of Hash
  Functions on FPGAs", ISVLSI 2006, pp. 317–322. The paper contains a figure
  captioned **"2x-Unrolled-Pipelined SHA-2 Core"**. That is Config D's structure,
  in 2006, in a paper reference [11] of our own literature survey.
- **Gamgam**, "An Unrolled and Pipelined Architecture for SHA2 Family of Hash
  Functions on FPGA", ISCTürkiye 2023, IEEE doc. 10336096. SHA-512's 80 steps
  completed in 42 — the signature of 2× unroll plus a pipeline stage, exactly
  analogous to our 64 → 34.

Citing prior art in your own survey and then claiming it is the fastest way to
lose credibility in a viva.

---

## 5. Claim: the dual-stream AXI wrapper (alternating blocks over one stream port)

**DEAD, and it was never inventive to begin with.**

Multiplexing two logical channels over one physical stream by alternating
fixed-size frames is elementary time-division multiplexing. The CAPS discovery
register is a capability bit — standard practice in every peripheral register
map ever written, and the pattern AMBA itself encourages.

Helion's 2010 core already switches message context block-by-block over a single
host interface (§1). The AXI4-Stream framing around it adds no inventive step;
it is the obvious way to connect that behaviour to a Zynq DMA.

This is good engineering. It is not an invention.

---

## 6. Claim: the operand-scheduling finding, and the orthogonality claim

**Both DEAD, for different reasons.**

**Operand scheduling** — hoisting the round-independent operands (`h₂ = g₁`,
`K[t+1]`, `W[t+1]`) to the front of the adder chain so only two adds sit on the
late path — **is Chaves, Kuzmanov, Sousa & Vassiliadis, "Improving SHA-2
Hardware Implementations", CHES 2006**. Operation rescheduling is the paper's
headline contribution. Our ngspice work *measured* its effect inside an unrolled
pair, which is a useful measurement, but the technique is twenty years old and
is reference [10] of our own survey.

**Orthogonality of the two axes** follows from **C-slow retiming theory
(Leiserson & Saxe, "Retiming Synchronous Circuitry", Algorithmica, 1991)**. The
entire point of C-slowing is that throughput scales with thread count largely
independently of the combinational structure. Confirming it holds at two unroll
depths is verification of a thirty-five-year-old theorem, not a discovery.

---

## 7. Claim: the 2×2 controlled comparison methodology

**Not patentable subject matter at all**, before novelty even arises.

A method of measuring and comparing designs is a methodology. Under India's
**Patents Act §3(k)** it falls among "a mathematical method or business method or
a computer programme per se or algorithms". Commentary on the CRI guidelines is
blunt that device claims over a published algorithm are "mostly rejected under
Section 3(k) for allegedly not having any novel or inventive hardware
orientation" — and SHA-256 is a published algorithm (FIPS 180-4), so the
algorithm itself is both excluded and long-expired as anything.

---

## 8. Already closed: operand-dependent adder bypass

Documented in full in `ADDER_BYPASS_FINDING.md`. Two independent kills:

- **Prior art on both readings.** Carry-sense bypass *is* the carry-skip adder
  (US5337269, US5581497, US6567836 — textbook, expired). Operand-sense bypass is
  operand isolation / data gating, covered by US8578196, US20100017635,
  US5023826, US6366943, US5975749, US5367477, and US12399684 (2025). SHA-256-
  specific low-power work is published too: *Implementation of Efficient Low
  Power SHA-256 Algorithm* (2024) already uses gated-clock conversion and
  arithmetic resource sharing.
- **It does not work here.** Measured in ngspice on real SHA-256 operand streams:
  **1.68×–2.00× worse** than the plain adder, including on padded short messages
  which are its best possible case. SHA-256's operands are uniform by
  construction — that is the security property — so value-dependent optimisation
  has nothing to bite on.

---

## 9. The one route that remains open, and its honest odds

**A measured Zynq result that contradicts Suhaili & Julai (2022).**

If the four Vivado runs show unrolling behaving in a way the published record
says it should not, then *prior art teaching away* becomes available — the
strongest inventive-step argument there is, because it rebuts obviousness
directly rather than merely asserting difference.

Honest odds: **low.** Our own ngspice study predicts B lands between 0.500 and
0.680 depending on how well Vivado schedules the adder chain, and both of those
are unsurprising outcomes that the literature already accommodates. A
teaching-away argument needs a result that is not just different but
*inexplicable under the prior art*, and we have already supplied the
explanation ourselves.

It also cannot be assessed until §1 of `NEXT_STEPS.md` is done.

---

## 10. How to present this

Do not present a patent. Present the grilling.

A student who says *"here is my invention"* and gets shown Helion 2010 in the
Q&A has lost the room. A student who says *"here are the six claims I
considered, here is the prior art that kills each one, and here is what survives"*
has demonstrated exactly the judgment a research degree is supposed to produce.
**The second version is stronger, and it is also true.**

### What to say

> We evaluated six candidate claims for patentability and rejected all six on
> prior art. The interleaved core is anticipated by a Helion Technology
> commercial FPGA IP datasheet from 2010 that switches message context block by
> block; two-message lockstep through a two-cycle pipeline is described as known
> background in an IBM patent application filed in 2023; unroll-plus-pipeline is
> McEvoy 2006 and Gamgam 2023; operand rescheduling is Chaves 2006; axis
> independence follows from Leiserson–Saxe retiming theory of 1991; and the
> comparison methodology is excluded subject matter under §3(k).
>
> We also evaluated an operand-dependent adder bypass and rejected it on
> measured evidence rather than on prior art alone: driven with real SHA-256
> operand streams at transistor level it costs 1.68 to 2.00 times the energy of
> a plain adder, because a hash function's operands are uniform by construction.

### What the project actually contributes

State this plainly and it holds up:

1. **A controlled re-test of a specific, recent, contradictory published result.**
   Suhaili & Julai (2022) report 2× unrolling *improving* Fmax; the structural
   argument says it must fall. Their three designs were built separately, so the
   result cannot separate architecture from device from toolchain. We hold the
   round module and the constraint set identical so unroll depth is the only
   variable.
2. **A measured explanation for the conflict.** Transistor-level ngspice:
   `delay(n) = 0.2110 ns + n × 0.3169 ns`, R² = 0.998. Unrolling's payoff is
   decided by whether the adder chain hoists the round-independent operands —
   a synthesiser property, not an architectural one. Naive ordering gives ratio
   0.500 and misses both thresholds; reordered gives 0.680 and clears both.
3. **A pre-registered falsifiable threshold** (0.515 core, 0.624 system),
   committed at Review 1 and never moved.
4. **Exhaustive hierarchical verification** — 103 RTL and 21 software checks,
   including per-round `a..h` and `W[0..63]` at all 64 rounds and four-way
   digest agreement across A, B, C and D.

That is a defensible contribution. It is not a patent, and saying so first is
what makes the rest credible.

---

## Sources

Helion Technology, *Tiny Hash Core Family for Lattice FPGA*, Rev 1.0, 27/10/2010 ·
IBM US20250070957A1 (filed 2023-08-22) · Intel US12413388B2 (granted 2025-09-09) ·
Gueron & Krasnov, IACR ePrint 2012/371 · McEvoy et al., ISVLSI 2006, pp. 317–322 ·
Gamgam, ISCTürkiye 2023, IEEE 10336096 · Suhaili & Julai, *Pertanika JST* 30(1)
581–603, 2022 · Chaves et al., CHES 2006, LNCS 4249 · Leiserson & Saxe,
*Algorithmica*, 1991 · Santos Jr. et al., *Sensors* 24(12):3908, 2024 ·
Saarinen, "Accelerating SLH-DSA…", CRYPTO 2024 · Sahu et al., SPHINCSLET, IACR
ePrint 2025/621 · US9917689, US8856547, US7684563, US6091821, US8578196,
US5023826, US6366943, US12399684 · Indian Patents Act §3(k) and the 2017 CRI
guidelines.
