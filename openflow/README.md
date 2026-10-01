# Open-source FPGA flow: the 2×2 run without Vivado

The same experiment as `vivado/build_core_ooc.tcl` (same part, same rules), run
entirely with open-source tools so it works on any Linux box or cloud container.

| Step | Tool |
|---|---|
| Synthesis to Xilinx 7-series primitives (LUT6, CARRY4, FDRE…) | Yosys ≥ 0.40, `synth_xilinx -arch xc7 -abc9` |
| Placement, routing and static timing on **XC7Z020-1 CLG484** | nextpnr-xilinx (openXC7) with the Project X-Ray database |

## One-time setup (Ubuntu 24.04, about 15 minutes)

```bash
sudo apt-get install -y iverilog yosys ngspice cmake libboost-all-dev libeigen3-dev \
                        python3-dev build-essential pypy3
pip install yowasp-yosys            # Yosys 0.6x; Ubuntu's 0.33 aborts in abc9 on these cores

git clone --depth 1 https://github.com/openXC7/nextpnr-xilinx /opt/xc7/nextpnr-xilinx
cd /opt/xc7/nextpnr-xilinx
git submodule update --init --depth 1 xilinx/external/nextpnr-xilinx-meta
(cd xilinx/external && git clone --depth 1 --filter=blob:none --sparse \
     https://github.com/openxc7/prjxray-db && cd prjxray-db && git sparse-checkout set zynq7)
mkdir build && cd build
cmake .. -DARCH=xilinx -DBUILD_GUI=OFF -DCMAKE_BUILD_TYPE=Release \
      -DPython3_EXECUTABLE=/usr/bin/python3.12 \
      -DPython3_INCLUDE_DIR=/usr/include/python3.12 \
      -DPython3_LIBRARY=/usr/lib/x86_64-linux-gnu/libpython3.12.so
make -j$(nproc)
cd .. && pypy3 xilinx/python/bbaexport.py --device xc7z020clg484-1 --bba xilinx/xc7z020.bba
./build/bbasm --l xilinx/xc7z020.bba xilinx/xc7z020.bin
```

## Run

```bash
make all sched                       # 103 + 26 RTL checks and 21 software checks
openflow/build_open.sh               # A, B, C, D and B', 5 seeds each, about 30 minutes
```

The outputs go in `reports_open/`: `results.csv` (median Fmax per configuration, in the same
format as the Vivado flow), `seeds.csv` (every seed), and the per-run logs.
`scripts/compare_configs.py` and `openflow/compare_sched.py` print the verdicts.

## What this flow does differently from Vivado, and why that is acceptable

- **A harness has to sit around the core.** The cores' 512/1024-bit ports exceed the
  device's I/O, and nextpnr has no out-of-context mode. `ooc_harness.v` puts registers
  on every core input and output. Every config gets the identical harness, and area is
  taken from synthesising the bare core, so the harness does not count against anyone.
- **Absolute MHz are lower than Vivado's.** nextpnr-xilinx's routing-delay model is
  conservative, and its placer and router are less mature. **Use the ratios, not the
  MHz.** Ratios are what the pre-registered thresholds are stated in.
- **The median over 5 seeds is reported**, so one lucky placement cannot decide a
  comparison. The spread is in `seeds.csv`.
- Treat this as independent corroboration. When a Vivado 2022.2 machine is available,
  `vivado/build_core_ooc.tcl` is still the reference result.
