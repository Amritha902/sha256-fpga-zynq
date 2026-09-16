# Base Paper Comparison — why Suhaili & Julai measured a frequency gain

**Amritha S (23BEC1368) · September 2026**

Reproduce:
```
python3 spice/gen_round_delay.py --verify
python3 spice/gen_round_delay.py --curve
```

---

## The conflict

**Base paper.** Suhaili, S. and Julai, N., *"FPGA-based Implementation of SHA-256
with Improvement of Throughput using Unfolding Transformation"*, Pertanika Journal
of Science and Technology **30**(1), 581–603, 2022. Three designs on an Altera
Arria II GX — iterative, unfolding ×2, unfolding ×4. Their factor-two design
reduces the block cost from 64 to 34 cycles, bit-for-bit this project's
Configuration B, and they report that it **surpassed the iterative design in
maximum frequency**.

**This project's structural argument.** Two rounds chained combinationally put
two five-input adder chains in series. The critical path doubles, so the clock
must slow. Fmax **must fall**.

Both cannot be true of the same architecture. Something else differs, and their
three separately-built designs cannot say what — a frequency difference there
could be architecture, device family, or toolchain.

## What was measured here

The part that is pure circuit, independent of any FPGA fabric or vendor tool:
**how the round's critical-path delay scales with the number of 32-bit additions
in series.**

The round's path is `Σ1(e)` — two XOR levels over rewired copies, the rotations
being free routing — feeding five chained 32-bit additions:

```
T1 = h + Σ1(e) + Ch(e,f,g) + K[t] + W[t]      four adds
T2 = Σ0(a) + Maj(a,b,c)                        one add, off the critical path
a' = T1 + T2                                   one add
```

Transistor-level ngspice, generic 180 nm CMOS, VDD 1.8 V, ripple-carry adders
built from the same full-adder cell used throughout. Addends held at
`0x55555555` so every stage keeps switching; delay taken as the **last of all 32
output bits to settle**.

### Measured delay vs chain depth

| Adds in series | Delay (ns) | ns per add |
|---:|---:|---:|
| 1 | 0.5506 | 0.5506 |
| 2 | 0.8461 | 0.4230 |
| 3 | 1.0890 | 0.3630 |
| 5 | 1.8387 | 0.3677 |
| 7 | 2.4562 | 0.3509 |
| 10 | 3.3595 | 0.3359 |

Least-squares fit of `delay(n) = t_σ + n · t_add`:

```
t_σ    (Σ1 network, 2 XOR levels)  = 0.2110 ns
t_add  (one 32-bit addition)       = 0.3169 ns
R²                                 = 0.99847
```

**Delay is linear in chain depth.** There is no circuit-level effect that would
let an unrolled round run at the iterative round's speed.

### Configuration critical paths

A depth-*n* chain contains **one** Σ1. Config B is two rounds and therefore
carries **two** Σ1 networks, so each configuration is modelled explicitly rather
than read off the raw curve:

| | Σ1 | adds | Path (ns) | Fmax vs A |
|---|---:|---:|---:|---:|
| **A** iterative | 1 | 5 | 1.7957 | 1.000 |
| **B** unrolled, naive order | 2 | 10 | 3.5913 | **0.500** |
| **B** unrolled, reordered | 2 | 7 | 2.6405 | **0.680** |
| **C** interleaved | 1 | 5 | 1.7957 | 1.000 |
| **D** both levers | 2 | 10 | 3.5913 | 0.500 |

## The finding

Against the thresholds committed before synthesis — **0.515** at core level,
**0.624** at system level:

| | Fmax ratio | core | system |
|---|---:|---|---|
| B, naive operand order | 0.500 | **misses** | **misses** |
| B, reordered | 0.680 | clears | clears |

**The outcome of unrolling is decided by operand scheduling, not by unroll
depth.**

### The reordering, and why it is available

In the *second* round of an unrolled pair, three of T1's five operands do not
depend on the first round's result at all:

- `h₂ = g₁` — a pure rename, free in hardware, available immediately
- `K[t+1]` — a compile-time constant
- `W[t+1]` — from the message schedule, which runs independently of compression

Only `Σ1(e₂)` and `Ch(e₂,f₂,g₂)` are late. An adder chain that sums the three
early operands **first** leaves just two adds on the late path, so the second
round costs ~2 extra adds instead of 5. This is Chaves *et al.*'s operation
rescheduling (CHES 2006) applied inside the unrolled pair rather than across a
register boundary.

A synthesiser may or may not find this ordering. That is the point.

### What this says about the base paper

A design whose adder chain happens to be ordered well gains frequency from
unrolling; one ordered naively does not. **That is a concrete, measured mechanism
by which Suhaili & Julai could report a frequency improvement while the
structural argument predicts a fall** — and it is precisely what their
separately-built designs cannot distinguish from a device or toolchain effect.

It also sharpens this project's own hypothesis. The prediction should not be
"unrolling must lose"; it should be **"unrolling loses unless the adder chain is
scheduled to hoist the round-independent operands, and whether that happens is a
property of the synthesiser, not of the architecture."**

### And why interleaving is the robust lever

Config C keeps one round per pipeline stage, so its path equals Config A's and
its Fmax ratio is **1.000 by construction**. Interleaving changes the cycle count
and never touches the critical path.

So the two levers differ in kind, not just degree:

- **Unrolling** is contingent — its payoff depends on a scheduling decision made
  downstream of the designer.
- **Interleaving** is structural — it cannot be undone by a scheduling choice.

That contrast is stronger than the orthogonality claim it replaces, because it
is measured rather than inherited from C-slow retiming theory.

## Scope, stated honestly

- Generic SPICE LEVEL-1 models at 180 nm, **not a foundry PDK**.
- **Ripple-carry** adders, not the carry-select or carry-lookahead structures a
  synthesiser infers on FPGA fabric, and not Xilinx CARRY4 primitives.
- What transfers is the **shape of the curve** (delay is linear in depth,
  R² = 0.998) and the **ratios between configurations**. Absolute nanoseconds are
  not claimable and no Fmax in MHz should be quoted from this study.
- The reordered-B figure assumes the ideal 2-add late path. A real synthesiser
  may land anywhere between 7 and 10 adds; the two rows bracket the outcome.
- This does **not** replace the Vivado measurement. It predicts what that
  measurement should find and explains what it would mean either way.

## Files

| Path | What |
|---|---|
| `spice/gen_round_delay.py` | Netlist generator, ngspice driver, curve fit |
| `spice/cmos180.lib` | Shared CMOS cell library |
| `reports_ooc/round_path_delay.csv` | The measured curve |
