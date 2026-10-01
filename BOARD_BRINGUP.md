# ZedBoard Bring-Up — runbook

**SHA-256 accelerator · Zynq-7000 XC7Z020-1CLG484 · Amritha S (23BEC1368)**

## Hardware

| Item | Note |
|---|---|
| Avnet/Digilent **ZedBoard** (Rev C or D) | XC7Z020-1CLG484, 512 MB DDR3 |
| 12 V / 3 A supply | ships with the board |
| 2 × micro-USB cable | **J17** PROG (JTAG), **J14** UART |
| Host PC | Windows 10/11 or Ubuntu 20.04/22.04, 16 GB RAM, 60 GB free |

**Boot-mode jumpers JP7–JP11 must all be on GND (JTAG boot).** JP6 is not used.

## Software

| Tool | Version | Licence |
|---|---|---|
| AMD **Vivado** ML Standard | 2022.2 | free; XC7Z020 included |
| AMD **Vitis** Unified (XSCT) | 2022.2 | free |
| Digilent cable drivers | bundled with Vivado | free |
| Serial terminal (PuTTY, Tera Term or minicom) | any | free |

ZedBoard board files (`em.avnet.com:zed:part0:1.4`) ship with Vivado 2022.2.

## Steps

```bash
source /tools/Xilinx/Vivado/2022.2/settings64.sh
source /tools/Xilinx/Vitis/2022.2/settings64.sh
cd sha256-fpga-zynq
board/run_zedboard.sh A          # then B, C, D
```

The script runs these three stages. Each can also be run on its own:

| Stage | Command | Output | Time |
|---|---|---|---|
| 1. Hardware | `vivado -mode batch -source vivado/build_system.tcl -tclargs 0` | `build_cfgA/sha256_system.bit`, `.xsa`, `reports/` | 10–20 min |
| 2. Software | `xsct vitis/build_app.tcl cfgA` | `vitis_ws_cfgA/sha256_app/*/sha256_app.elf` | 2–3 min |
| 3. Run | `xsct vitis/run_on_board.tcl cfgA` | the program runs on the A9 and reports over the UART | < 1 min |

Open the UART (J14) at **115200 8N1** *before* stage 3.

Run the four out-of-context Fmax builds (the headline measurement) separately:

```bash
for i in 0 1 2 3; do vivado -mode batch -source vivado/build_core_ooc.tcl -tclargs $i; done
python3 scripts/compare_configs.py
```

## Expected UART output

This transcript is the output of the **same program**, unmodified, running on the virtual board
(`make cosim`), so the board must reproduce it. The cycle counts differ by a few cycles because of
the real PS7 bus latency. The timing lines will differ: on the board they measure the Cortex-A9.

| Config | NIST vectors | `cycles =` per block (virtual board) | Dual-stream test |
|---|---|---:|---|
| A | 4 / 4 PASS | 84 | skipped (single-stream core) |
| B | 4 / 4 PASS | 52 | skipped |
| C | 4 / 4 PASS | 100 per pair | PASS |
| D | 4 / 4 PASS | 68 per pair | PASS |

```
 SHA-256 HARDWARE ACCELERATOR  -  ZedBoard XC7Z020
 Accelerator detected and initialised.
 TEST 1 : register map
  VERSION       = 0x53480001  expected 0x53480001  [PASS]
  BLOCK_CNT r/w = 0x00001234  expected 0x00001234  [PASS]
 TEST 2 : NIST FIPS 180-4 conformance
  [PASS] empty message      e3b0c442...7852b855
  [PASS] "abc"              ba7816bf...f20015ad
  [PASS] 56-byte message    248d6a61...19db06c1
  [PASS] 112-byte message   cf5b16a7...7afee9d1
 SUMMARY
  ALL CONFORMANCE CHECKS PASSED
 INTERACTIVE : type a message, get its SHA-256
  msg>
```

The full transcripts for all four configurations are in `reports_cosim/board_{A,B,C,D}.log`.

## If something fails

| Symptom | Cause | Fix |
|---|---|---|
| `VERSION` reads other than 0x53480001 | wrong base address or stale bitstream | check `XPAR_SHA256_TOP_0_S_AXI_BASEADDR` in the BSP's `xparameters.h`; rerun stage 3 |
| `AXI DMA init failed` | DMA built with scatter-gather | `c_include_sg = 0` in `build_system.tcl` (already set) |
| Digest mismatch only on 2-block vectors | cache not flushed | `Xil_DCacheFlushRange` must precede the DMA transfer (it does in `sha256_hw.c`) |
| `driver error -1` on C or D | the pre-fix driver | fixed: on a dual core a lone message is hashed as a pair |
| No JTAG target | jumpers not in JTAG mode, or J17 not connected | set JP7–JP11 to GND, power-cycle |

## What is already verified without the board

| Check | Tool | Result |
|---|---|---|
| RTL simulation | Icarus Verilog | 129 / 129 |
| Software reference | gcc | 21 / 21 |
| Board program compiled for the Cortex-A9 | arm-none-eabi-gcc 13.2, `-Wall -Wextra -Werror` | clean |
| Gate-level netlists | Yosys + Icarus (Xilinx cell models) | 67 / 67 |
| Formal equivalence B′ ≡ B | Yosys SAT and induction | proven |
| Place and route on XC7Z020 | nextpnr-xilinx | `OPEN_FLOW_RESULTS.md` |
| Board program against the RTL over AXI | Verilator virtual board | A–D all pass |
| Tcl scripts | tclsh | parse clean |
