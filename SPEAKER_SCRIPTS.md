# SPEAKER SCRIPTS — Review 1 and Review 2

**SHA-256 Hardware Accelerator on Zynq-7000**
Team of four · Amritha S (23BEC1368) + three teammates

---

## How to use this document

- **Bold** = stress the word when speaking
- *(italics in brackets)* = stage direction, do not read aloud
- `[SLIDE n]` = advance the slide here
- Each speaker has their own section. Print only your pages.
- **Practise the handoff sentences.** A clean handoff makes a team of four look rehearsed; a fumbled one makes it look like four separate talks.

**Fill in your names below and use them in the handoffs.**

| Role | Name | Owns |
|---|---|---|
| Speaker 1 | Amritha S | Problem, question, objectives |
| Speaker 2 | ______________ | Literature, positioning |
| Speaker 3 | ______________ | Algorithm, architecture, truth tables |
| Speaker 4 | ______________ | Verification, specs, plan, close |

---

# REVIEW 1 — PROPOSAL

**Total target: 12 minutes speaking + 3–5 minutes questions**
**Each speaker: roughly 3 minutes**

---

## SPEAKER 1 — Problem and Question
### Slides 1–5 · ~3 minutes

`[SLIDE 1 — Title]`

Good morning. We're presenting our FPGA project: a **SHA-256 hardware accelerator** on the ZedBoard.

I want to be clear at the start about what kind of project this is. We are not just implementing SHA-256 — that has been done many times. We are answering a specific engineering question about it, and I'll state that question precisely in about ninety seconds.

I'm [name], and I'll cover the problem and our objectives. [Speaker 2] takes the literature, [Speaker 3] the architecture, and [Speaker 4] verification and our plan.

`[SLIDE 2 — Agenda]`

*(Do not read the agenda aloud. Two seconds on screen, then move on.)*

`[SLIDE 3 — Problem Statement]`

Here is the problem.

A block cipher like AES, running in ECB mode, processes **independent** blocks. That means if you unroll the rounds, you can put pipeline registers between them. The logic depth per stage stays the same, the clock frequency survives, and throughput scales with area. Unrolling is nearly free.

A hash function cannot do that.

SHA-256 has sixty-four rounds, and round *t+1* consumes the working variables produced by round *t*. They are **strictly sequential**. If you unroll two rounds and put a register between them, you have gained nothing — you're back to one round per cycle. So the two rounds have to sit back to back, combinationally, and the adder chains **stack in series**.

And the critical path here is entirely addition. The rotations are free — I'll let [Speaker 3] explain why. Ch and Maj are one LUT deep. Everything expensive is the five-input, thirty-two-bit sum that forms T1.

So unrolling a hash **must** cost you frequency. The only question is how much.

`[SLIDE 4 — The Research Question]`

Which brings us to the question this project answers.

*(Slow down here. This is the most important slide in the deck.)*

We build the same round function two ways. Configuration A runs one round per cycle — sixty-six cycles per five-hundred-and-twelve-bit block. Configuration B chains two rounds — thirty-four cycles.

That's **one point nine four times fewer cycles**. But Configuration B's clock will be slower.

So: is the product a net gain?

It's a net win if and only if Configuration B retains more than **fifty-one point five percent** of Configuration A's maximum frequency. Thirty-four over sixty-six.

We are declaring that threshold **now**, before we have run a single synthesis. Most implementation reports measure first and rationalise afterwards. We wanted a falsifiable prediction — which also means that if the answer comes back as a loss, that's still a result. It quantifies exactly why hash functions parallelise badly.

`[SLIDE 5 — Objectives]`

Six objectives, each with a pass-fail criterion rather than something subjective.

The ones I'd point at: **O4** — Configuration B must produce bit-identical digests to Configuration A. That's a strong self-check that needs no external reference. And **O6** — characterise the trade-off, which is where the answer to our question comes from.

Definition of done is at the bottom: the board hashes a message typed over UART, the digest matches the NIST reference, and both configurations are synthesised under identical constraints.

*(Handoff)*

[Speaker 2] will now cover what the literature already tells us — and, importantly, what it doesn't.

---

## SPEAKER 2 — Literature and Positioning
### Slides 6–9 · ~3 minutes

`[SLIDE 6 — Literature Survey I: Specification]`

Thank you. We reviewed twenty-two works across five clusters. I'll cover them quickly and then spend most of my time on positioning, because that's where we have something honest to say.

Our primary reference is **NIST FIPS 180-4**, the Secure Hash Standard. It gives us the padding rules, the initial hash values, the sixty-four round constants, the logical functions, and worked examples.

This topic has an unusual advantage: our ground truth is a **free, permanent, authoritative government publication** with test vectors included. There's no ambiguity about what correct looks like.

One detail worth mentioning. The sixty-four round constants are the fractional parts of the cube roots of the first sixty-four primes. Those are **"nothing up my sleeve" numbers** — derived from a publicly verifiable procedure so nobody can allege a hidden trapdoor was embedded in them. It's a design decision about trust, not arithmetic.

`[SLIDE 7 — Literature Survey II: Critical Path]`

This cluster is where the real hardware work is.

Every serious SHA-2 hardware paper is about one thing: **shortening the adder chain**.

The most relevant to us is **Chaves and colleagues, CHES 2006** — "Improving SHA-2 Hardware Implementations." They introduce operation rescheduling: precompute part of T1 one cycle ahead so the adder chain splits across the register boundary. You shorten the critical path without changing the round count.

*(If you are asked "how would you improve this?", that paper is your answer. Know the name.)*

Dadda and colleagues at DATE 2004 confirm the adder is the bottleneck and apply carry-save addition. McEvoy and colleagues at ISVLSI 2006 make the FPGA-specific point that the message schedule and the compression function should be optimised **separately** — which turns out to matter for us, and [Speaker 3] will show why.

`[SLIDE 8 — Why Hashes Resist Unrolling]`

This slide is the structural argument, side by side.

Left column, AES-ECB: blocks independent, registers between stages, depth constant, frequency preserved.

Right column, SHA-256: rounds dependent, a register would forfeit the saving, depth doubles, frequency **must** fall.

But here's the part I want to flag — **one thing does unroll for free**. The message schedule. W of t plus sixteen and W of t plus seventeen both depend only on the current sixteen-word window. There's no serial dependency between them, so those two adders run in parallel.

So it isn't that "SHA-256 doesn't parallelise." It's that the **compression loop** doesn't. Knowing exactly where the dependency lives is the difference between understanding the algorithm and just implementing it.

And the genuinely correct way to make a hash fast is **multi-stream interleaving** — independent messages have no dependency, so N of them pipeline perfectly through an N-stage round unit. That's what high-throughput hashing hardware does. We've documented it as future work.

`[SLIDE 9 — Positioning]`

I want to be straightforward about novelty.

SHA-256 hardware is a **mature field**. The architectural options were mapped between 2002 and 2009. We are not claiming a new architecture, and we're not claiming a record throughput. Anyone who knows this field would see through that immediately.

What we do claim is four things.

A **falsifiable prediction with a numeric threshold**, stated before measuring. A **controlled comparison** — both configurations share the identical round module, so only unroll depth varies. **Hierarchical verification**, which [Speaker 4] will detail. And **honest accounting** of a modest software speedup, with the structural reason for it.

That's a claim that survives questioning. An inflated one wouldn't.

*(Handoff)*

[Speaker 3] will now take you through the algorithm and what we're actually building.

---

## SPEAKER 3 — Algorithm, Architecture, Truth Tables
### Slides 10–15 · ~3.5 minutes

`[SLIDE 10 — SHA-256 Round Structure]`

Thanks. Here's one compression round.

T1 is *h* plus big-Sigma-one of *e*, plus Ch of *e, f, g*, plus the round constant, plus the schedule word. T2 is big-Sigma-zero of *a* plus Maj of *a, b, c*.

Then the working variables shift along. And notice — **six of the eight updates are just a rename**. B becomes A, C becomes B, and so on. In hardware those are wires. Only *a* and *e* need arithmetic.

Look at the four boxes. Ch and Maj: one LUT per bit. The four Sigma functions: thirty-two LUTs each. The T1 five-input add: **that's the bottleneck**, and everything else is nearly free.

Which is why there are **zero DSP slices** in this design. SHA-256 contains no multiplication anywhere. Only addition, XOR, AND, and rewiring.

`[SLIDE 11 — Two Configurations]`

Same round module, instantiated once or twice.

Configuration A: one instance, feedback, sixty-six cycles, one adder chain.
Configuration B: two chained combinationally, thirty-four cycles, **two adder chains in series**.

Bottom of the slide is the message schedule point [Speaker 2] mentioned. Both new schedule words depend only on the current window, so they compute in parallel. The schedule unrolls for free; only the compression stacks.

`[SLIDE 12 — System Architecture]`

Complete processor-plus-fabric co-design.

The ARM does the padding and streams blocks over AXI DMA. The fabric packs sixteen thirty-two-bit beats into a block, runs the compression, and chains the hash value across blocks. The digest comes back over eight AXI-Lite register reads.

We put padding in **software deliberately** — it's byte-alignment bookkeeping. Compression is the expensive part and that's what we accelerate. Saying that clearly is better than letting it look like an omission.

`[SLIDE 13 — Truth Table I: Ch and Maj]`

Two truth tables, exhaustive.

Ch on the left. Read it down the *x* column: when *x* is zero the output tracks *z* exactly; when *x* is one it tracks *y*. So **Ch is a bitwise two-to-one multiplexer** with *x* as the select line.

Maj on the right. The rightmost column counts the ones in the input. The output is one exactly when two or more inputs are one — a **three-input majority gate**. One LUT per bit.

`[SLIDE 14 — Truth Table II: Why Rotation Costs Nothing]`

This is the table I'd most like you to look at.

Big-Sigma-zero is three rotations XORed together. The table shows where each output bit comes from. Output bit zero takes input bits two, thirteen and twenty-two. Output bit ten wraps around and takes bit zero.

**Every one of those source indices is a compile-time constant.**

So the rotation itself is **wires** — zero LUTs, zero flip-flops, zero delay. The only logic in the entire function is one three-input XOR per bit. Thirty-two LUTs for the whole thing.

Shift is the same, except the shifted-in bits are hard zeros instead of wrapping.

That's the whole reason the adder dominates: everything around it is nearly free.

`[SLIDE 15 — Truth Table III: FSM and Schedule]`

Control FSM at the top — four states, and the round counter differs between the two configurations because B advances by two.

Below it, the rolling window. W of t depends only on t minus two, t minus seven, t minus fifteen and t minus sixteen. It never reaches back further than sixteen words.

So we keep a **sixteen-deep shift register**, not all sixty-four words. That's five hundred and twelve bits instead of two thousand and forty-eight — we save fifteen hundred and thirty-six bits for no functional cost.

*(Handoff)*

[Speaker 4] will cover how we prove all of this is correct, and our plan.

---

## SPEAKER 4 — Verification, Specs, Plan, Close
### Slides 16–24 · ~3 minutes

`[SLIDE 16 — Verification Strategy]`

This is the strongest part of our project and I want to spend my time here.

FIPS 180-4 doesn't just publish input and output. It publishes the **state after every transformation of every round**. So we verify hierarchically, at eight levels — not end to end.

The Sigma functions against a Python model. The K ROM against the standard. The message schedule word by word. The working variables at all sixty-four rounds. Single-block digests, multi-block chaining, and finally the two configurations against **each other**.

That last one matters. A and B share submodules but differ completely in control and unroll depth. Requiring bit-identical digests is an independent check that needs no external reference.

Why hierarchy? Because hash bugs — a wrong Sigma constant, a schedule off-by-one, a missing final accumulation — **all produce output that still looks like a valid digest**. End-to-end testing tells you something is wrong. Per-round traces tell you *where*.

`[SLIDE 17 — Hardware Specification]`

ZedBoard, XC7Z020. Both configurations sit under ten percent of the device, no BRAM, no DSP.

The point at the bottom: **area is not the binding constraint here**. That's exactly what makes the unrolling question interesting. The trade is cycles against frequency, and the device has room for either answer.

`[SLIDE 18 — Software Specification]`

Both mandated tools are load-bearing. Vivado does the RTL, both implementations, and the timing comparison that answers our question. Vitis runs the padding, the DMA driver, the timing measurement and the software baseline.

`[SLIDES 19–20 — Design Flow and Timeline]`

*(Move through these briskly — ten seconds each.)*

Nine stages, model first. Twelve weeks with a genuine buffer week at six.

Configuration B is deliberately scheduled **last**, at Week 10, after Configuration A works on hardware. If we slip, we still have a complete, verified, measured deliverable and B becomes documented future work rather than a failure.

`[SLIDE 21 — Evaluation Metrics]`

Nine measurements, each against a named baseline.

One I want to pre-empt. Our expected speedup over software is about **three times**, not a hundred.

That's correct and expected. SHA-256 is thirty-two-bit add, XOR and rotate — precisely what a general-purpose ALU executes in one cycle each. There is no arithmetic the CPU has to emulate. A block cipher would show a hundred times because its finite-field arithmetic must be emulated in software.

So the value of a SHA-256 accelerator is **offload and deterministic latency**, not raw throughput multiplication. We'd rather say that plainly than quote an inflated number.

`[SLIDE 22 — Scope and Risks]`

Left side, what we've excluded and why — decryption-equivalents, the other SHA variants, HMAC, multi-stream interleaving, side channels. Each with a technical reason.

Right side, risks. I'll draw attention to R4: **Configuration B failing timing badly is the result, not a failure.** Our report is written to accommodate either outcome.

`[SLIDES 23–24 — References and Close]`

*(Skip the references slide unless asked.)*

To close: build SHA-256 in fabric two ways from the same round module, verify both exactly against the NIST vectors, and measure whether unrolling a strictly sequential hash is worth what it costs in frequency.

We have three asks on screen. Happy to take questions.

---

## REVIEW 1 — Q&A PREPARATION

**Everyone should be able to answer the first three.**

| Question | Who | Answer |
|---|---|---|
| "Why no DSP slices?" | Anyone | SHA-256 has no multiplication. Only 32-bit add, XOR, AND and fixed bit reorderings. |
| "Why does unrolling cost frequency here but not in AES?" | Anyone | AES-ECB blocks are independent so unrolled rounds can be pipelined and depth per stage stays constant. SHA-256 rounds are data-dependent — a register between them forfeits the cycle saving, so the adder chains stack. |
| "Only 3× speedup? Isn't that poor?" | Anyone | Expected. SHA-256 is exactly what an ALU is built for. The value is offload and deterministic latency. |
| "How would you shorten the critical path without unrolling?" | S2 | Operation rescheduling — Chaves et al., CHES 2006. Precompute part of T1 one cycle ahead so the chain splits across the register boundary. Also carry-save adders. |
| "Why only sixteen schedule words?" | S3 | W[t] reaches back at most sixteen. Storing all sixty-four wastes 1536 bits for nothing. |
| "Why is padding in software?" | S3 | Deliberate scope decision. Padding is bookkeeping; compression is the expensive part. |
| "What if Config B is slower overall?" | S4 | That's the answer to our question, and it's reportable. It quantifies why hash functions parallelise badly within a message. |
| "How do you know it's correct?" | S4 | FIPS 180-4 publishes per-round intermediates. We verify at eight levels, and cross-validate the two architectures against each other. |
| "What's genuinely new here?" | S2 | Not the architecture — that field is mature. A stated falsifiable threshold, a controlled comparison, exhaustive verification, and honest measurement on current silicon. |

---
---

# REVIEW 2 — PROGRESS

**Total target: 9 minutes speaking + 3–5 minutes questions**
**Each speaker: roughly 2 to 2.5 minutes**

> **Before you present:** check slide 1 of the Review 2 deck says the right week, and that the status colours on slide 01 match your actual progress. Do not present amber items as green.

---

## SPEAKER 1 — Status
### Slides 1–3 · ~2 minutes

`[SLIDE 1 — Title]`

Good morning. This is our progress review for the SHA-256 accelerator.

Short version before I go into detail: **design and verification are complete**. Forty-four RTL checks passing, zero failures, both configurations. What remains is synthesis, board bring-up, and measurement.

And we have one finding to report that changed our own analysis — [Speaker 3] will present it.

`[SLIDE 2 — Where the Project Stands]`

*(Point at the four numbers, don't read the table.)*

Forty-four checks passing. All planned RTL written and verified. Both configurations working in simulation. And **zero hardware measurements so far** — that's the amber one, and it's honest.

The table below shows every deliverable with its evidence. Green means measured, amber means running, red means not started. Two rows are red: synthesis, and board bring-up. Both are scheduled and both are on the critical path.

`[SLIDE 3 — Recap of the Question]`

Quick recap for anyone who wasn't at Review 1.

SHA-256 rounds are strictly data-dependent. Unrolling stacks the adder chains, so frequency must fall. Configuration A is sixty-six cycles per block, Configuration B is thirty-four.

We declared at Review 1 that unrolling is a net win only if B retains more than **fifty-one point five percent** of A's frequency.

That prediction still stands. But — as the last line says — Review 2 has **refined it**. [Speaker 3] will explain why.

*(Handoff)*

[Speaker 2] will cover our verification evidence.

---

## SPEAKER 2 — Verification Evidence
### Slides 4–5 · ~2 minutes

`[SLIDE 4 — Verification Evidence]`

Forty-four checks across five suites, and they all run from a **single command**. `make all` regenerates the golden vectors and runs everything in about ninety seconds.

Twenty-one core RTL checks. Nine system-level checks over real AXI for Configuration A, nine more for B. Five trace-and-soak checks. And ten software checks compiled natively.

The reason I'd emphasise reproducibility: this isn't a screenshot of a run that worked once. Anyone on the panel could clone the repository and get the same result.

`[SLIDE 5 — New Since Review 1: Per-Round Verification]`

At Review 1 we flagged per-round verification as **outstanding**. It's now done, and I want to explain the method because it's the part we're most pleased with.

The problem, top of the slide: hash bugs all produce output that still **looks** like a valid digest. A wrong Sigma constant, a schedule off-by-one, a missing accumulation — end-to-end testing can't localise any of them.

So: our Python model emits the working variables and the schedule word at the top of every one of the sixty-four rounds. The testbench reads those with `$readmemh` and compares against the RTL at each round.

Two subtleties, step three. We key the sampling off the **core's own round counter** rather than guessing how many cycles the load phase takes. And we drive all stimulus on the **negative** clock edge — driving on the positive edge races the design's own clocked block, which we found was shifting our entire trace by one round.

Result at the bottom: working variables and message schedule **both match at all sixty-four rounds**.

*(Handoff)*

[Speaker 3] has the finding.

---

## SPEAKER 3 — The New Finding
### Slides 6–7 · ~2.5 minutes

`[SLIDE 6 — The Threshold Moved]`

*(This is your slide. Slow down. It's the most substantive thing in the review.)*

At Review 1 we derived our break-even threshold from the **core** cycle counts alone. Sixty-six and thirty-four. Thirty-four over sixty-six is nought point five one five.

When we measured the **integrated** system — the full design driven over AXI, the way the processor will actually drive it — we found something the original analysis missed.

Look at the table. Compression only: sixty-six and thirty-four. Measured at system level: **eighty-five and fifty-three**.

The saving is still exactly thirty-two cycles. But there's a **fixed nineteen-cycle overhead** in both configurations — sixteen AXI-Stream beats to deliver a block, plus the submit and hash-update handshake. It's identical in both because it sits outside the compression loop.

And a fixed overhead **dilutes a proportional saving**. The gain is now thirty-two out of eighty-five, not thirty-two out of sixty-six.

So the real threshold is **fifty-three over eighty-five — nought point six two four**.

*(Pause here.)*

I want to be clear about what this means. Our Review 1 prediction wasn't wrong — it was **incomplete**. And the correction makes the bar **harder** to clear, not easier. Configuration B now has to retain sixty-two percent of the frequency rather than fifty-two.

We could have quietly kept the old number. We're presenting the revised one because it's the honest threshold, and because it came out of doing the integration work rather than out of theory.

`[SLIDE 7 — System Integration]`

Briefly, how we verified it.

Left side: the exact sequence — AXI-Lite writes to set the block count and start, sixteen stream beats per block with back-pressure, poll status, then eight register reads for the digest. That's precisely what the processor will do.

Right side: eight things verified over real AXI, including multi-block chaining, re-arm without reset, and soft reset.

And at the bottom — we found **two bugs, both in our own testbench**, not the RTL.

First, our AXI model deasserted VALID as soon as READY appeared. A transfer completes on the rising edge where both are high, so VALID has to be held **through** that edge. Dropping it early loses the transfer silently.

Second, the positive-edge stimulus race I mentioned.

I'd rather report those than pretend it went smoothly. Both are documented in the testbench comments so the next person doesn't repeat them.

*(Handoff)*

[Speaker 4] will cover what's running now and what's left.

---

## SPEAKER 4 — In Progress, Results, Plan, Close
### Slides 8–12 · ~2.5 minutes

`[SLIDE 8 — Synthesis and Implementation]`

Synthesis is scripted, not clicked. Two commands, one per configuration.

The script packages the IP, builds the whole block design — Zynq processing system, AXI DMA, our accelerator — applies an **identical** timing constraint, implements, and extracts accelerator-only resource counts filtered from the DMA and interconnect.

The reason it's scripted is at the bottom, and it matters. **The entire project rests on comparing two frequency numbers.** If the two builds differ in interconnect topology or constraint wording, that comparison is worthless. Scripting guarantees only `CORE_SELECT` changes.

`[SLIDE 9 — Results Table]`

Here's our results table, ready to fill.

The top three rows are **already measured** and won't change — cycle counts at core and system level, and the overhead.

Everything else comes from two Vivado reports and one UART session. The row highlighted as "THE RESULT" is the frequency ratio against nought point six two four.

Once those two reports exist, the results chapter is arithmetic.

`[SLIDE 10 — Remaining Work]`

Weeks eight and nine are the only ones on the critical path — the two builds, and board bring-up. Everything after is analysis and writing, which can absorb delay.

If board access slips, our fallback is to report synthesis results only and bring the hardware demo to Review 3.

`[SLIDE 11 — Risk Register]`

Four of our seven Review 1 risks are now **retired** — and retired by evidence, not by assertion. Each one names the test that closed it.

Three remain open. Configuration B failing timing, which is expected and is the result. Cache coherency on the board, which we haven't exercised yet. And board access, which is our only remaining schedule risk.

`[SLIDE 12 — Close]`

To summarise: design and verification are complete and reproducible. Integration measurement has already sharpened our research question. What remains is two synthesis runs, one board session, and arithmetic.

Three asks on screen. Happy to take questions.

---

## REVIEW 2 — Q&A PREPARATION

| Question | Who | Answer |
|---|---|---|
| "Why did your threshold change?" | S3 | Review 1 used core cycle counts. Integration exposed a fixed 19-cycle streaming overhead — 16 AXI beats plus handshake — identical in both configs. A fixed overhead dilutes a proportional saving, so the bar rose from 0.515 to 0.624. |
| "Doesn't that mean Review 1 was wrong?" | S3 | It was incomplete, not wrong. And the correction makes our own prediction harder to satisfy, which is why we're presenting it rather than keeping the old number. |
| "You have no hardware results yet." | S1 | Correct, and slide 01 says so. Synthesis is running this week, board bring-up next. The critical path is two weeks and we have written fallbacks. |
| "How do we know your 44 checks are meaningful?" | S2 | They're hierarchical. Per-round traces against a golden model, twelve messages across padding boundaries, and two independent architectures cross-validated against each other. |
| "What if the ratio comes out below 0.624?" | S4 | Then unrolling is a net loss on this device, and that's our finding. It quantifies why hash functions parallelise badly within a single message. The report is written to accommodate either outcome. |
| "Can you reduce the 19-cycle overhead?" | S3 | Yes — a wider AXI stream. At 64 bits it halves to about eight beats. We haven't done it because it changes the DMA configuration and we wanted both configs measured under identical conditions first. Good future work. |
| "Why did you find bugs in your own testbench?" | S2 | Both were AXI handshake timing — deasserting VALID before the transfer edge, and racing the DUT with posedge stimulus. Common and easy to miss. We documented both in the code. |

---

## PRESENTATION MECHANICS — read this the night before

**Timing.** Practise once with a stopwatch. If you're over, cut from the literature and specification slides — never from the research question or the results.

**Handoffs.** Say the next person's name. One sentence. Then stop talking and step back.

**The three slides that matter most.**
- Review 1: the research question (slide 4) and the rotation truth table (slide 14)
- Review 2: the threshold change (slide 6)

Everything else is context.

**If a demo fails**, do not debug on stage. Say "we have a recorded run, let me show that instead" and move on. Have the recording ready.

**If you're asked something you don't know**, say so and offer to follow up. "I don't have that number in front of me — I'll send it after" is a completely acceptable answer. Guessing is not.

**Don't oversell.** The strongest thing about this project is that every claim is backed by a named test. That only works if you also say clearly what hasn't been measured yet.

---

*Fill in the four names at the top before printing. Practise the handoffs.*
