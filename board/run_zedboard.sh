#!/usr/bin/env bash
#=============================================================================
#  run_zedboard.sh  —  bitstream, software and on-board run in one command
#
#      board/run_zedboard.sh A        (A, B, C or D)
#
#  Needs Vivado + Vitis 2022.2 on PATH (source <install>/settings64.sh) and
#  a ZedBoard on JTAG. See BOARD_BRINGUP.md.
#=============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-A}" in
    A) SEL=0 ;; B) SEL=1 ;; C) SEL=2 ;; D) SEL=3 ;;
    *) echo "usage: $0 A|B|C|D"; exit 1 ;;
esac
CFG="cfg${1:-A}"

command -v vivado >/dev/null || { echo "vivado not on PATH - source settings64.sh"; exit 1; }
command -v xsct   >/dev/null || { echo "xsct not on PATH - source Vitis settings64.sh"; exit 1; }

echo "=== 1/3 Vivado: block design, bitstream, XSA ($CFG)"
vivado -mode batch -nojournal -source vivado/build_system.tcl -tclargs $SEL

echo "=== 2/3 Vitis: platform and application"
xsct vitis/build_app.tcl "$CFG"

echo "=== 3/3 JTAG: program and run (watch the UART at 115200 8N1)"
xsct vitis/run_on_board.tcl "$CFG"
