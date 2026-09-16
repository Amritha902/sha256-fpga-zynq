# IMPLEMENTATION GUIDE

## SHA-256 Accelerator on ZedBoard — from empty machine to working demo

**Everything in this project is written and verified. This guide is the plug-in-and-finish path.**

Read this once end to end before starting. Total hands-on time is roughly 8 working days spread over 12 weeks; the rest is buffer.

---

## 0. What is already done, and what is left

| | Status |
|---|---|
| Python golden model, all 5 NIST vectors | ✅ **Done, passing** |
| SHA-256 core RTL — Config A and Config B | ✅ **Done, 21/21 checks passing** |
| AXI4-Lite register file | ✅ **Done, verified in simulation** |
| AXI4-Stream wrapper | ✅ **Done, verified in simulation** |
| Top-level IP | ✅ **Done, 9/9 system checks passing, both configs** |
| Software SHA-256 + padding + byte-swap | ✅ **Done, verified natively against NIST** |
| Vitis driver and application | ✅ **Written** — needs compiling against your BSP |
| Vivado build automation | ✅ **Written** — needs running |
| **Synthesis, board bring-up, measurement** | ⬜ **This is your remaining work** |

You are not writing an algorithm. You are running builds, bringing up a board, and collecting numbers.

---

## 1. Prerequisites

### 1.1 Software

| Tool | Version | Notes |
|---|---|---|
| Vivado | 2022.2 | Must include the Zynq-7000 device family |
| Vitis | 2022.2 | Must match Vivado exactly |
| Icarus Verilog | any recent | `sudo apt-get install iverilog gtkwave` — for simulation |
| Python 3 | 3.6+ | For the golden model. No external packages needed. |
| A serial terminal | — | PuTTY, TeraTerm, `minicom`, or `screen` |

### 1.2 Hardware

- ZedBoard (XC7Z020-1CLG484C)
- Micro-USB cable for **UART** (the port labelled UART, not PROG)
- Micro-USB cable for **JTAG/PROG**
- 12 V power supply

### 1.3 ZedBoard jumper settings — JTAG boot

Set the five MIO jumpers **JP7–JP11** all to **GND** (the position nearest the board edge). This selects JTAG boot mode, which is what Vitis uses to download the bitstream and the application.

If the board does nothing when you program it, check these jumpers first. It is the most common bring-up problem.

---

## 2. Simulate first (30 minutes)

Do this before touching Vivado. If the simulation does not pass on your machine, nothing downstream will work.

```bash
cd sha_project

# 1. golden model — regenerates the K constants and test vectors
make model
#    expect: RESULT: ALL CHECKS PASSED

# 2. core-level RTL verification (21 checks)
make
#    expect: CHECKS RUN : 21   FAILURES : 0

# 3. system-level AXI verification, Configuration A (9 checks)
make sys
#    expect: CHECKS RUN : 9    FAILURES : 0

# 4. system-level AXI verification, Configuration B
make sysB
#    expect: CHECKS RUN : 9    FAILURES : 0

# 5. software reference, compiled natively
make swtest
#    expect: RESULT: ALL SOFTWARE CHECKS PASSED
```

**All five must pass before continuing.** They take about a minute in total.

To capture waveforms for the report:

```bash
make wave        # opens sim/tb_sha256.vcd in GTKWave
```

---

## 3. Build the hardware (20 minutes per configuration)

### 3.1 Automated build — do this

```bash
cd sha_project

# Configuration A (iterative)
vivado -mode batch -source vivado/build_system.tcl

# Configuration B (2x unrolled)
vivado -mode batch -source vivado/build_system.tcl -tclargs 1
```

Each run packages the IP, builds the entire block design, synthesises, implements, generates the bitstream and exports the `.xsa` for Vitis.

**Outputs:**

```
build_cfgA/sha256_system.xsa          <- import this into Vitis
build_cfgA/sha256_system.bit
build_cfgA/reports/summary.txt        <- the numbers for your report
build_cfgA/reports/address_map.txt    <- check the base address
build_cfgA/reports/utilization.rpt
build_cfgA/reports/timing.rpt

build_cfgB/...                        <- same, for Configuration B
```

### 3.2 Check three things immediately

Open `build_cfgA/reports/summary.txt`:

1. **`DSP : 0`** — if this is not zero, something is very wrong. SHA-256 has no multiplication.
2. **`Fmax estimate`** — record this. You need it for both configurations.
3. **Worst negative slack** — if negative, timing did not close; see §7.

Open `build_cfgA/reports/address_map.txt` and find the base address assigned to `sha256_0`. It is almost always `0x43C00000`. If it is something else, note it — §4.3 covers this.

### 3.3 The number the whole project turns on

```
                Fmax(Config B)
    ratio  =  ------------------      break-even = 34/66 = 0.515
                Fmax(Config A)
```

- **ratio > 0.515** → unrolling is a net throughput win
- **ratio < 0.515** → unrolling is a net loss

Either outcome is a valid result. Write it up as measured.

### 3.4 If you must use the GUI instead

The automated script is strongly preferred — it guarantees both configurations see an identical surrounding system, which is what makes the comparison controlled. If you need the GUI anyway:

1. Create a project, part `xc7z020clg484-1`
2. Add all six files from `rtl/`
3. Tools → Create and Package New IP → Package your current project, top = `sha256_top`
4. Create Block Design, add: ZYNQ7 Processing System, AXI Direct Memory Access, SHA-256 Accelerator
5. **ZYNQ PS:** Run Block Automation with the ZedBoard preset; then in Re-customize IP set PL Fabric Clock FCLK_CLK0 to **100 MHz** and enable **S_AXI_HP0**
6. **AXI DMA:** uncheck **Enable Scatter Gather Engine**, uncheck **Enable Write Channel (S2MM)**, keep Read Channel (MM2S), set stream width **32**
7. Connect `axi_dma_0/M_AXIS_MM2S` → `sha256_0/s_axis`
8. Run Connection Automation for everything else (it wires the AXI-Lite control paths and the HP port to DDR)
9. Validate Design, then Create HDL Wrapper
10. Generate Bitstream
11. File → Export → Export Hardware → **Include bitstream**

---

## 4. Build the software (1 hour, first time)

### 4.1 Create the Vitis workspace

1. Launch Vitis, choose a workspace directory (keep it **outside** the Vivado project folder)
2. **File → New → Application Project**
3. **Create a new platform from hardware (XSA)** → Browse → `build_cfgA/sha256_system.xsa`
4. Platform name: `sha256_platform`
5. Application name: `sha256_app`
6. Target processor: **ps7_cortexa9_0**
7. Domain: **standalone**
8. Template: **Empty Application (C)**
9. Finish

### 4.2 Add the source files

Copy these four files into `sha256_app/src/`:

```
sw/sha256_sw.c      sw/sha256_sw.h
sw/sha256_hw.c      sw/sha256_hw.h
sw/main.c
```

Delete any `helloworld.c` the template created.

### 4.3 Check the base address

Open `sha256_platform/export/.../include/xparameters.h` and search for `SHA256`. You should find something like:

```c
#define XPAR_SHA256_TOP_0_S_AXI_BASEADDR 0x43C00000
```

`sha256_hw.c` uses `XPAR_SHA256_TOP_0_S_AXI_BASEADDR` automatically. **If your macro has a different name**, either rename it or add this line near the top of `sha256_hw.c`:

```c
#define SHA256_BASEADDR 0x43C00000   /* whatever xparameters.h says */
```

Same for the DMA: the driver expects `XPAR_AXIDMA_0_DEVICE_ID`.

### 4.4 Enable floating-point printf

The benchmark prints `%.2f`. The default Vitis settings strip float support from `printf`.

Right-click `sha256_app` → **C/C++ Build Settings** → **ARM v7 gcc linker** → **Miscellaneous** → **Other flags**, add:

```
-Wl,--start-group,-lxil,-lgcc,-lc,-lm,--end-group
```

Alternatively replace the three `printf` calls in `benchmark()` with integer arithmetic — `xil_printf` does not support floats at all.

### 4.5 Increase the heap and stack

The driver holds a 64 KB DMA buffer in `.bss` and the benchmark uses a 4 KB message.

Right-click the platform → **Board Support Package Settings** → **standalone** → set:

```
stack_size = 0x4000     (16 KB)
heap_size  = 0x4000     (16 KB)
```

### 4.6 Build

**Project → Build All.** Expect zero errors and zero warnings.

---

## 5. Run on the board (15 minutes)

1. Set jumpers JP7–JP11 to **GND** (§1.3)
2. Connect both USB cables and power on
3. Open a serial terminal on the ZedBoard's UART port at **115200 8N1**
   - Linux: `screen /dev/ttyACM0 115200`
   - Windows: check Device Manager for the COM port number
4. In Vitis: **Xilinx → Program Device**, select `sha256_system.bit`, click Program
5. Right-click `sha256_app` → **Run As → Launch Hardware**

### Expected output

```
==========================================================
 SHA-256 HARDWARE ACCELERATOR  -  ZedBoard XC7Z020
==========================================================
 Amritha S  -  23BEC1368
 PL clock : 100000000 Hz
 Accelerator detected and initialised.

==========================================================
 TEST 1 : register map
==========================================================
  VERSION       = 0x53480001  expected 0x53480001  [PASS]
  BLOCK_CNT r/w = 0x00001234  expected 0x00001234  [PASS]
  STATUS        = 0x00000004  (busy=0 ready=1)

==========================================================
 TEST 2 : NIST FIPS 180-4 conformance
==========================================================
  [PASS] empty message           (1 block )
         hw : e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
         cycles = 85
  [PASS] "abc"                    (1 block )
         hw : ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
         cycles = 85
  ...

==========================================================
 TEST 3 : hardware vs software throughput
==========================================================
  hardware  : 0.0xxxxx s   xxx.xx Mbit/s
  software  : 0.0xxxxx s   xxx.xx Mbit/s
  speedup   : x.xxx

==========================================================
 INTERACTIVE : type a message, get its SHA-256
==========================================================
  msg> hello
  hw  : 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
  sw  : 2cf24dba...   [cross-check]
```

That interactive mode is your demo. Type a message, get the hash. Deliverable ⑥ complete.

---

## 6. Collect the results (Week 10–11)

### 6.1 The measurement table

| Metric | Config A | Config B | Where from |
|---|---|---|---|
| Cycles per block | 66 | 34 | simulation, already confirmed |
| Fmax (MHz) | ___ | ___ | `reports/summary.txt` |
| **Fmax ratio** | — | ___ | B ÷ A |
| **vs break-even 0.515** | — | ___ | win or loss |
| Accelerator LUT | ___ | ___ | `reports/summary.txt` |
| Accelerator FF | ___ | ___ | `reports/summary.txt` |
| BRAM | ___ | ___ | should be 0 |
| **DSP** | ___ | ___ | **must be 0** |
| Measured throughput (Mbit/s) | ___ | ___ | board, TEST 3 |
| Software throughput (Mbit/s) | ___ | ___ | board, TEST 3 |
| Speedup | ___ | ___ | board, TEST 3 |

Fill this in and the results chapter writes itself.

### 6.2 Waveforms for deliverable ③

```bash
make wave
```

Capture these five in GTKWave:

1. **Compression round** — `u_round.t1`, `u_round.t2`, and `a`/`e` updating
2. **Message schedule** — the `w[0]`…`w[15]` window shifting, `w_new` appearing
3. **Sigma as pure rewiring** — `sha256_big_sigma0` input and output in the same delta cycle
4. **AXI4-Lite** — `awvalid`/`awready`/`wvalid`/`wready`/`bvalid` during a register write
5. **AXI4-Stream** — `tvalid`/`tready`/`tlast` across 16 beats, showing back-pressure between blocks

### 6.3 Optional secondary experiment

Move the K constants from LUT ROM to BRAM: register the output of `sha256_k_rom` and load it with `$readmemh("model/k_const.mem", ...)`. Rebuild and compare LUT vs BRAM in the summary. Ten minutes of work, one more data point.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `sha256_hw_init` returns −4 (VERSION) | Wrong base address, or the bitstream on the board is not this build | Check `address_map.txt` against `xparameters.h`; reprogram the device |
| `sha256_hw_init` returns −2 (DMA) | Scatter-gather enabled in the DMA IP | Re-customize AXI DMA, **uncheck** Enable Scatter Gather |
| Hardware digest wrong, software digest right | **Missing cache flush** — the single most common bug | Confirm `Xil_DCacheFlushRange()` runs before `XAxiDma_SimpleTransfer()` in `sha256_hw.c` |
| Digest is byte-reversed in groups of four | `sha256_swap_words32()` not called, or called twice | It must be called exactly once, after padding |
| Application hangs on the first hash | DMA never started, or TLAST never arrived | Check `M_AXIS_MM2S` → `s_axis` is connected; check the transfer length is a multiple of 64 |
| Board does nothing | Boot jumpers | JP7–JP11 all to GND |
| `printf` prints garbage for floats | Float support not linked | §4.4, or switch to integer arithmetic |
| Timing fails on Config B | Expected — the adder chains stack | **This is the result.** Record the negative slack and the achieved Fmax. Do not "fix" it by loosening the constraint on only one configuration. |
| Timing fails on Config A | Not expected | Check the clock constraint applied to the right pin; try `-directive Performance_Explore` on impl_1 |

---

## 8. Week-by-week checklist

| Week | Task | Done when |
|---|---|---|
| 1 | Run all five simulations (§2) | All pass on your machine |
| 2 | Read `sha256_functions.v` and the synopsis; understand `xtime`-free rotation and the T1 path | You can explain why there are no DSPs |
| 3 | Run the Config A build (§3.1) | `summary.txt` exists, DSP = 0 |
| 4 | Vitis workspace, build the app (§4) | Clean build, zero warnings |
| 5 | **Buffer** | — |
| 6 | Board bring-up (§5) | TEST 1 and TEST 2 all PASS |
| 7 | Benchmark; record software vs hardware | TEST 3 numbers recorded |
| 8 | Run the Config B build | Second `summary.txt` exists |
| 9 | **Buffer** | — |
| 10 | Compute the Fmax ratio; fill in the table (§6.1) | Table complete |
| 11 | Capture waveforms; draft the report | Five waveforms captured |
| 12 | Slides, demo rehearsal, submission | Deliverables complete |

---

## 9. File map

```
sha_project/
├── model/
│   ├── sha256_golden.py          Python reference + vector generator
│   ├── k_const.mem               64 K constants for $readmemh
│   ├── blocks.txt                padded blocks + expected digests
│   ├── abc_round_trace.txt       a..h after every one of the 64 rounds
│   └── abc_schedule.txt          W[0..63] for the "abc" block
├── rtl/
│   ├── sha256_functions.v        Ch, Maj, Sigma x4, K ROM, one round
│   ├── sha256_core_iter.v        CONFIG A — 1 round/cycle
│   ├── sha256_core_unroll2.v     CONFIG B — 2 rounds/cycle
│   ├── sha256_axi_lite_regs.v    AXI4-Lite control + digest readback
│   ├── sha256_axis_wrapper.v     AXI4-Stream, packs 32-bit beats into blocks
│   └── sha256_top.v              top-level IP, CORE_SELECT parameter
├── tb/
│   ├── tb_sha256.v               core verification, 21 checks
│   └── tb_sha256_top.v           system verification over AXI, 9 checks
├── sw/
│   ├── sha256_sw.c/.h            software SHA-256, padding, byte-swap
│   ├── sha256_hw.c/.h            Vitis driver
│   └── main.c                    application: tests, benchmark, interactive
├── vivado/
│   └── build_system.tcl          fully automated build
├── Makefile
├── IMPLEMENTATION_GUIDE.md       this file
├── README.md                     team handoff and work split
├── FPGA_SHA256_Synopsis.md
└── FPGA_SHA256_Literature_Survey.md
```

---

## 10. The five things most likely to be asked

1. **Why no DSP slices?** SHA-256 has no multiplication — only 32-bit add, XOR, AND and fixed bit reorderings.

2. **Why are the rotations free?** ROTR and SHR are compile-time-constant bit reorderings. In fabric they are wires. Each Σ function is one 3-input XOR per bit — 32 LUTs.

3. **Why only 16 schedule words?** W[t] reaches back at most 16 words. Storing all 64 would waste 1536 bits for nothing.

4. **Why does unrolling cost frequency here but not in AES-ECB?** AES-ECB blocks are independent, so unrolled rounds can be pipelined and depth per stage stays constant. SHA-256 rounds are data-dependent — a register between them would forfeit the cycle saving, so the adder chains stack.

5. **Your speedup is only ~3×. Is that bad?** No, it is expected. SHA-256 is exactly what an ALU is built for. The value is offload and deterministic latency, not raw speedup. A block cipher would show 100× because its finite-field arithmetic has to be emulated in software.

---

*If something in this guide is wrong or unclear, fix the guide as well as the problem. The next person will thank you.*
