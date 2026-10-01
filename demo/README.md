# Demo video

`SHA256_Verification_Demo.mp4` (2 min, 1280×720) shows, in order:

1. RTL simulation (Icarus Verilog): 129 checks, and the RTL waveform of Config A hashing "abc"
2. Formal equivalence B′ ≡ B (Yosys)
3. Gate-level simulation of the synthesised netlists (Yosys + Icarus)
4. Place and route of Config B on the XC7Z020 (nextpnr-xilinx)
5. The 2×2 comparison and the B versus B′ comparison
6. The ngspice transistor-level check
7. The virtual board: the unmodified board program on A–D, including the UART transcript
8. The Cortex-A9 cross-compilation

Every terminal frame is captured output from the real command, run in the project's cloud
environment on 1 October 2026. Only the time is compressed. To regenerate:

```bash
scripts/capture_demo.sh /tmp/demo/cap
make sim                                   # fresh RTL waveform in sim/tb_sha256.vcd
python3 scripts/make_demo_video.py /tmp/demo/cap sim/tb_sha256.vcd demo/SHA256_Verification_Demo.mp4
```
