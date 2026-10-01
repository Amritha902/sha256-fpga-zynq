#!/usr/bin/env python3
"""Emit pin constraints for ooc_harness on the XC7Z020-CLG484.

The pins carry no meaning (the harness is never put on a board); nextpnr
just needs every port on a real I/O site. clk goes on Y9, the ZedBoard's
100 MHz clock-capable input.
"""
import csv
import sys

PORTS = (["clk", "rst_n", "shift", "go", "init_0", "init_1", "ready_q", "dvalid_q"]
         + [f"din[{i}]" for i in range(32)]
         + [f"dout[{i}]" for i in range(32)]
         + [f"sel[{i}]" for i in range(4)])

pins = []
with open(sys.argv[1]) as fh:
    for r in csv.DictReader(fh):
        if r["bank"] in ("13", "33", "34", "35") and r["pin_function"].startswith("IO_") \
                and "VREF" not in r["pin_function"] and r["pin"] != "Y9":
            pins.append(r["pin"])

if len(pins) < len(PORTS) - 1:
    sys.exit(f"only {len(pins)} free I/O pins for {len(PORTS)} ports")

assign = {"clk": "Y9"}
it = iter(pins)
for p in PORTS[1:]:
    assign[p] = next(it)

for port, pin in assign.items():
    print(f"set_property PACKAGE_PIN {pin} [get_ports {{{port}}}]")
    print(f"set_property IOSTANDARD LVCMOS33 [get_ports {{{port}}}]")
