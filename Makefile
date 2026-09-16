#=============================================================================
#  SHA-256 Accelerator — verification makefile
#
#  Requires: iverilog, gcc, python3
#      sudo apt-get install iverilog gtkwave build-essential
#
#      make          core RTL verification      (21 checks)
#      make cslow    config C + D verification  (27 checks)
#      make sys      system AXI verification A  ( 9 checks)
#      make sysB     system AXI verification B  ( 9 checks)
#      make sysC     system AXI verification C  (dual stream)
#      make sysD     system AXI verification D  (dual stream)
#      make soak     trace + soak verification  ( 5 checks)
#      make swtest   software reference test    native gcc
#      make model    regenerate golden vectors
#      make all      run everything
#      make wave     open the core waveform
#      make lint     elaborate only, report warnings
#      make clean    remove build products
#=============================================================================

CORE_RTL := rtl/sha256_functions.v \
            rtl/sha256_core_iter.v \
            rtl/sha256_core_unroll2.v \
            rtl/sha256_core_cslow2.v \
            rtl/sha256_core_u2c2.v

SYS_RTL  := $(CORE_RTL) \
            rtl/sha256_axi_lite_regs.v \
            rtl/sha256_axis_wrapper.v \
            rtl/sha256_axis_wrapper_dual.v \
            rtl/sha256_top.v

IV := iverilog -g2012 -Wall

.PHONY: all sim cslow sys sysB sysC sysD soak swtest model wave lint clean

all: model sim cslow sys sysB sysC sysD soak swtest
	@echo ""
	@echo "============================================================"
	@echo " ALL VERIFICATION STAGES COMPLETE"
	@echo "============================================================"

sim: sim/tb_sha256.vvp
	@echo ""
	@echo "--- CORE RTL VERIFICATION ---"
	@vvp $<

sim/tb_sha256.vvp: $(CORE_RTL) tb/tb_sha256.v
	@mkdir -p sim
	@$(IV) -o $@ $(CORE_RTL) tb/tb_sha256.v

cslow: sim/tb_cslow.vvp
	@echo ""
	@echo "--- CONFIG C + D VERIFICATION : INTERLEAVED CORES ---"
	@vvp $<

sim/tb_cslow.vvp: $(CORE_RTL) tb/tb_sha256_cslow.v
	@mkdir -p sim
	@$(IV) -o $@ $(CORE_RTL) tb/tb_sha256_cslow.v

sys: sim/tb_top_A.vvp
	@echo ""
	@echo "--- SYSTEM VERIFICATION : CONFIG A ---"
	@vvp $<

sim/tb_top_A.vvp: $(SYS_RTL) tb/tb_sha256_top.v
	@mkdir -p sim
	@$(IV) -o $@ $(SYS_RTL) tb/tb_sha256_top.v

sysB: sim/tb_top_B.vvp
	@echo ""
	@echo "--- SYSTEM VERIFICATION : CONFIG B ---"
	@vvp $<

sim/tb_top_B.vvp: $(SYS_RTL) tb/tb_sha256_top.v
	@mkdir -p sim
	@$(IV) -DCORE_B -o $@ $(SYS_RTL) tb/tb_sha256_top.v

sysC: sim/tb_top_C.vvp
	@echo ""
	@echo "--- SYSTEM VERIFICATION : CONFIG C (dual stream) ---"
	@vvp $<

sim/tb_top_C.vvp: $(SYS_RTL) tb/tb_sha256_top_dual.v
	@mkdir -p sim
	@$(IV) -o $@ $(SYS_RTL) tb/tb_sha256_top_dual.v

sysD: sim/tb_top_D.vvp
	@echo ""
	@echo "--- SYSTEM VERIFICATION : CONFIG D (dual stream) ---"
	@vvp $<

sim/tb_top_D.vvp: $(SYS_RTL) tb/tb_sha256_top_dual.v
	@mkdir -p sim
	@$(IV) -DCORE_D -o $@ $(SYS_RTL) tb/tb_sha256_top_dual.v

soak: sim/tb_soak.vvp
	@echo ""
	@echo "--- TRACE + SOAK VERIFICATION ---"
	@vvp $<

sim/tb_soak.vvp: $(CORE_RTL) tb/tb_sha256_soak.v
	@mkdir -p sim
	@$(IV) -o $@ $(CORE_RTL) tb/tb_sha256_soak.v

swtest:
	@echo ""
	@echo "--- SOFTWARE REFERENCE (native) ---"
	@mkdir -p sim
	@gcc -O2 -Wall -Wextra -Isw -o sim/swtest sw/test_sw.c sw/sha256_sw.c
	@./sim/swtest

model:
	@cd model && python3 sha256_golden.py

wave: sim/tb_sha256.vcd
	@gtkwave sim/tb_sha256.vcd &

lint:
	@$(IV) -t null $(SYS_RTL) tb/tb_sha256.v && echo "core lint clean"
	@$(IV) -t null $(SYS_RTL) tb/tb_sha256_top.v && echo "system lint clean"
	@$(IV) -t null $(CORE_RTL) tb/tb_sha256_soak.v && echo "soak lint clean"
	@$(IV) -t null $(CORE_RTL) tb/tb_sha256_cslow.v && echo "cslow lint clean"
	@$(IV) -t null $(SYS_RTL) tb/tb_sha256_top_dual.v && echo "dual system lint clean"

clean:
	@rm -f sim/*.vvp sim/*.vcd sim/swtest
	@echo cleaned
