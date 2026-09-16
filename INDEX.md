# PROJECT INDEX — SHA-256 Hardware Accelerator on Zynq-7000

**Amritha S · 23BEC1368 · Team of four · ZedBoard XC7Z020 · Vivado/Vitis 2022.2**

Start here. Every file, what it is, and who needs it.

---

## Read in this order

| # | File | Purpose |
|---|---|---|
| 1 | `INDEX.md` | This file |
| 2 | `RESULTS_AND_GAPS.md` | **What is done, what is not, what still needs writing** |
| 3 | `IMPLEMENTATION_GUIDE.md` | Step by step, jumpers to demo |
| 4 | `README.md` | Team handoff and work split |
| 5 | `SPEAKER_SCRIPTS.md` | Review 1 and 2 speeches, split four ways |

---

## Deliverable documents

| File | Status |
|---|---|
| `Review1_SHA256.pptx` | 24 slides — proposal |
| `Review2_SHA256_Progress.pptx` | 12 slides — progress |
| `FPGA_SHA256_Synopsis.md` | Submission-ready synopsis |
| `FPGA_SHA256_Literature_Survey.md` | 22 works, five clusters |
| `SPEAKER_SCRIPTS.md` | Speeches + Q&A prep |
| `RESULTS_AND_GAPS.md` | Results template + report skeleton |
| **Final report** | **NOT WRITTEN — see RESULTS_AND_GAPS.md Part 4** |
| **Review 3 deck** | **NOT WRITTEN** |

---

## RTL — all verified in simulation

| File | Lines | Contents |
|---|---|---|
| `rtl/sha256_functions.v` | 195 | Ch, Maj, Sigma×4, K ROM, one compression round |
| `rtl/sha256_core_iter.v` | 166 | Config A — 1 round/cycle, 66 cycles/block |
| `rtl/sha256_core_unroll2.v` | 178 | Config B — 2 rounds/cycle, 34 cycles/block |
| `rtl/sha256_axi_lite_regs.v` | 216 | AXI4-Lite slave, 14-register map |
| `rtl/sha256_axis_wrapper.v` | 190 | AXI4-Stream, block packing, chaining |
| `rtl/sha256_top.v` | 190 | Top-level IP, CORE_SELECT parameter |

## Testbenches — 44 checks, zero failures

| File | Checks | Covers |
|---|---|---|
| `tb/tb_sha256.v` | 21 | Primitives, K ROM, NIST digests, cycle counts |
| `tb/tb_sha256_top.v` | 9 + 9 | Full system over AXI, both configs |
| `tb/tb_sha256_soak.v` | 5 | Per-round trace, 12-message soak |

## Software — verified natively

| File | Purpose |
|---|---|
| `sw/sha256_sw.c/.h` | Software SHA-256, padding, byte-swap |
| `sw/sha256_hw.c/.h` | Vitis driver — DMA, registers, digest readback |
| `sw/main.c` | Application: conformance, benchmark, interactive demo |
| `sw/test_sw.c` | Native test harness |

## Model and build

| File | Purpose |
|---|---|
| `model/sha256_golden.py` | Python reference + vector generator |
| `model/*.mem`, `*.txt` | Generated: K constants, blocks, traces, digests |
| `vivado/build_system.tcl` | **Fully automated build** — IP, block design, bitstream, XSA |
| `Makefile` | `make all` runs every verification suite |

---

## Commands

```bash
make all        # every verification suite, ~90 seconds
make model      # regenerate golden vectors
make wave       # open waveforms in GTKWave

vivado -mode batch -source vivado/build_system.tcl            # Config A
vivado -mode batch -source vivado/build_system.tcl -tclargs 1 # Config B
```

---

## Numbers to remember

| | Config A | Config B |
|---|---|---|
| Cycles/block, compression | 66 | 34 |
| Cycles/block, full system | 85 | 53 |
| Streaming overhead | 19 | 19 |
| DSP48 | 0 | 0 |

**Break-even: Fmax(B)/Fmax(A) > 53/85 = 0.624**
