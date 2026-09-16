# Operand-Dependent Adder Bypass in SHA-256 — a measured negative result

**Amritha S (23BEC1368) · September 2026**

Reproduce:
```
python3 spice/gen_energy_exp.py --check --bits 32 --vectors 6
python3 spice/gen_energy_exp.py --sweep --fine --bits 32 --vectors 32
python3 spice/gen_energy_exp.py --sha-spice
python3 spice/gen_energy_exp.py --sha --blocks 2000
```

---

## Summary

Operand-dependent bypass was evaluated as a patent candidate for the SHA-256
T1 adder and **rejected on measured evidence**. Two independent grounds, either
of which is sufficient:

1. **Prior art.** The technique is occupied several times over.
2. **It does not work here.** Driven with real SHA-256 operand streams in
   ngspice, the bypass costs **1.68x to 2.00x** the energy of the plain adder —
   including on padded short messages, which are its best possible case in this
   algorithm.

Not a marginal call, and not an extrapolation: the figures below are the actual
operand stream through the actual transistor-level circuits.

---

## 1. Prior art

"Bypass in an adder chain" has two readings and both are taken.

**Carry-sense bypass** is the carry-skip adder, also called literally the
*carry-bypass* adder — a textbook structure with expired patents including
US5337269, US5581497 and US6567836.

**Operand-sense bypass** is operand isolation / data gating, a named synthesis
feature that EDA tools insert automatically:

| Patent | Covers |
|---|---|
| US8578196 / US20100017635 | Zero-indication forwarding; gates the clock to multiplier, aligner **and adder** on a zero operand |
| US5023826 | Skipping arithmetic calculations involving leading zeros |
| US6366943 | Ignoring the add and proceeding when operands combine to zero |
| US5975749, US5367477 | Zero-detect chains in carry-select adders |
| US12399684 (2025) | Low-power adder tree structure |

SHA-256-specific low-power work is also published: *Implementation of Efficient
Low Power SHA-256 Algorithm* (2024) already applies gated-clock conversion and
arithmetic resource sharing, and *Low power and area SHA-256 hardware
accelerator on Virtex-7* (IEEE, 2020) covers the FPGA case.

---

## 2. The measurement

### 2.1 Method

Transistor-level ngspice simulation, generic 180 nm CMOS, VDD 1.8 V.

- **Baseline** — 32-bit ripple-carry adder.
- **Bypass** — the *same* adder plus a zero-detect reduction tree on operand B,
  AND-gate operand isolation on both operands, and a 2:1 output mux that passes
  A through when B is zero.

Both designs instantiate the identical full-adder cell, so model error is
common-mode and the **ratio** is the meaningful output.

**Both were functionally verified at 32 bits — the same width the energy is
reported at — against `a + b`, covering full carry propagation and the bypass
path.** Verifying an 8-bit circuit and then reporting 32-bit energy would be
reporting numbers from a circuit whose correctness was never established.

The bypass is implemented in its *favourable* standard form — what a synthesis
tool inserts. If it does not pay in this form, it does not pay.

### 2.2 THE DIRECT MEASUREMENT — real SHA-256 operands

No synthetic vectors, no interpolation. The T1 chain's last two-input stage is
driven with the genuine operand stream from the golden model, all 64 rounds:

- **operand A** = `h + Sigma1(e) + Ch(e,f,g) + K[t]`, the accumulated partial
- **operand B** = `W[t]`, the zero-detected one — and the only T1 operand that
  is ever genuinely zero, because the padding region of a short message leaves
  `W[1..14]` at zero

A padded short message is therefore the **best case the bypass can get** in
SHA-256. It still loses:

| Message | zero `W[t]` | fraction | Baseline | Bypass | Ratio |
|---|---:|---:|---:|---:|---:|
| `"abc"` | 14 / 64 | 0.219 | 3.547 pJ | 5.972 pJ | **1.68x** |
| empty | 18 / 64 | 0.281 | 2.685 pJ | 5.357 pJ | **2.00x** |
| 55-byte | 1 / 64 | 0.016 | 3.822 pJ | 6.595 pJ | **1.73x** |

**The bypass loses on every real operand stream tested**, by between 68% and
100% extra energy. A multi-block message is worse still: only the final block
carries padding, so the zero-fraction tends to zero as message length grows.

#### The ordering effect — why "break-even fraction" was the wrong question

Note the empty message: a **higher** zero-fraction (0.281 vs 0.219) yet a
**worse** ratio (2.00x vs 1.68x).

The cost is not driven by how many operands are zero, but by how many times the
zero flag *changes*. Every transition toggles all 64 isolation gates and the
32 output muxes. Scattered zeros therefore cost more than clustered ones at the
same fraction.

So a single "break-even zero-fraction" is not a well-defined quantity — it
depends on operand ordering as well as operand statistics. That is why the
direct measurement above is the claim, and the sweep below is only context.

### 2.3 Supporting sweep — synthetic vectors

32 additions per point, exact zero count per point, extra points near the
crossing. Included to show the shape of the trade, not to derive the claim.

| Zero fraction | Baseline (pJ) | Bypass (pJ) | Ratio | |
|---:|---:|---:|---:|---|
| 0.000 | 4.221 | 7.119 | 1.69 | bypass loses |
| 0.250 | 3.656 | 8.561 | 2.34 | bypass loses |
| 0.500 | 2.893 | 7.755 | 2.68 | bypass loses |
| 0.750 | 1.707 | 4.723 | 2.77 | bypass loses |
| 0.812 | 1.654 | 3.703 | 2.24 | bypass loses |
| 0.875 | 1.354 | 2.711 | 2.00 | bypass loses |
| 0.938 | 1.247 | 1.758 | 1.41 | bypass loses |
| 1.000 | 0.942 | 0.726 | 0.77 | bypass wins |

The crossing sits between 0.938 and 1.000 — the bypass only wins when
essentially every addition has a zero operand and the flag rarely changes. Do
not quote a single break-even percentage from this table: per the ordering
effect above, the crossing is not a function of zero-fraction alone, and the
ratio falls steeply across that last interval (1.41 to 0.77) because at exactly
1.000 the adder stops switching altogether.

### 2.4 Zero-operand statistics across random blocks

Zero-operand counts across the four variable T1 inputs, 2,000 random blocks,
128,000 rounds:

| Operand | Zero count | Fraction |
|---|---:|---:|
| `h` | 0 | 0 |
| `Σ1(e)` | 0 | 0 |
| `Ch(e,f,g)` | 0 | 0 |
| `W[t]` | 0 | 0 |
| **any zero** | **0** | **0** |

Expected for uniform 32-bit values: 2⁻³² ≈ 2.3 × 10⁻¹⁰ per operand.

### 2.5 Why this was predictable, and why it is general

SHA-256's working variables are **uniformly distributed by construction** —
indistinguishable from random output is the security property the function is
designed to have. Value-dependent optimisation needs operand sparsity. A
cryptographic hash is engineered to destroy exactly that.

This generalises: **operand-value-dependent power optimisation is structurally
mismatched to any cryptographic primitive whose design goal is uniform output.**
That is a more useful statement than the negative result alone, and it is the
part worth putting in the report.

The one place sparsity does exist is `W[0..15]` of a padded block, which is
mostly zeros for short messages. It is not enough: 16 of 64 rounds, final block
only, and in the schedule adder, which is neither the critical path nor
expensive.

---

## 3. Conclusion

Not pursued. Not patentable, and it would not work if it were.

Recorded here as documented, evidence-backed future work that was evaluated and
rejected — which is stronger than omitting it, and considerably stronger than
listing it as a speculative extension.

**Scope of the numbers.** Generic SPICE LEVEL-1 models, not a foundry PDK. The
energy *ratio* and the *break-even bracket* are the claims. Absolute picojoules
are not claimable — quoting them as silicon measurements would be the same
mistake as quoting Vivado's power estimator as a measurement.

**No inference left.** An earlier draft read the SHA-256 energy figure off the
synthetic sweep's zero-fraction-0.000 point. That inference has been replaced by
the direct measurement in §2.2: real operands, real netlists, measured.

---

## Files

| Path | What |
|---|---|
| `spice/cmos180.lib` | CMOS cell library: INV, NAND2, NOR2, AND2, OR2, XOR2, FA, MUX2 |
| `spice/gen_energy_exp.py` | Netlist generator, ngspice driver, sweep and SHA-256 statistics |
| `reports_ooc/adder_bypass_sha_operands.csv` | **Direct measurement behind §2.2** |
| `reports_ooc/adder_bypass_energy.csv` | Synthetic sweep behind §2.3 |
