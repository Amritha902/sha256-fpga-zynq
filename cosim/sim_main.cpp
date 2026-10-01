// sim_main.cpp — the virtual ZedBoard.
//
// The unmodified bare-metal program (sw/main.c + sw/sha256_hw.c +
// sw/sha256_pair.c + sw/sha256_sw.c) runs natively on the host. Every
// register access and every DMA transfer it makes reaches a Verilator model
// of rtl/sha256_top.v as a real AXI4-Lite or AXI4-Stream transaction,
// clocked cycle by cycle. This is the board bring-up of NEXT_STEPS.md §3,
// minus the board: same software, same RTL, same bus protocol.
//
// What it does NOT model: the PS7 interconnect's latency (an AXI-Lite access
// here takes a few PL cycles; on silicon it takes more) and the A9's speed.
// Functional results and the accelerator's own CYCLE_CNT are exact; the
// "speedup" line of the benchmark compares PL cycles with host-CPU time.
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "Vsha256_top.h"
#include "verilated.h"

extern "C" {
#include "xaxidma.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xtime_l.h"
int board_main(void);
}

static Vsha256_top *top;
static uint64_t cycles = 0;
static const uint64_t TIMEOUT = 2000;   // cycles allowed for one handshake

// Host time spent inside the model is excluded from "software" time.
using clk = std::chrono::steady_clock;
static clk::time_point t_start;
static double model_host_sec = 0.0;
struct InModel {
    clk::time_point t0 = clk::now();
    ~InModel() { model_host_sec += std::chrono::duration<double>(clk::now() - t0).count(); }
};

static void tick() {
    top->s_axi_aclk = 0; top->eval();
    top->s_axi_aclk = 1; top->eval();
    cycles++;
}

static void fail(const char *what) {
    std::fprintf(stderr, "\nVIRTUAL BOARD: bus timeout in %s after %llu cycles\n", what,
                 (unsigned long long)cycles);
    std::exit(2);
}

// ---- AXI4-Lite master ------------------------------------------------------
extern "C" u32 Xil_In32(UINTPTR addr) {
    InModel m;
    top->s_axi_araddr = (uint32_t)(addr & 0xFF);
    top->s_axi_arvalid = 1;
    top->s_axi_rready = 1;
    uint64_t n = 0;
    while (!top->s_axi_arready) { tick(); if (++n > TIMEOUT) fail("AR"); }
    tick();
    top->s_axi_arvalid = 0;
    n = 0;
    while (!top->s_axi_rvalid) { tick(); if (++n > TIMEOUT) fail("R"); }
    u32 v = top->s_axi_rdata;
    tick();
    top->s_axi_rready = 0;
    return v;
}

extern "C" void Xil_Out32(UINTPTR addr, u32 val) {
    InModel m;
    top->s_axi_awaddr = (uint32_t)(addr & 0xFF);
    top->s_axi_wdata = val;
    top->s_axi_wstrb = 0xF;
    top->s_axi_awvalid = 1;
    top->s_axi_wvalid = 1;
    top->s_axi_bready = 1;
    bool aw = false, w = false;
    uint64_t n = 0;
    while (!(aw && w)) {
        top->eval();
        bool aw_hs = top->s_axi_awvalid && top->s_axi_awready;
        bool w_hs = top->s_axi_wvalid && top->s_axi_wready;
        tick();
        if (aw_hs) { aw = true; top->s_axi_awvalid = 0; }
        if (w_hs) { w = true; top->s_axi_wvalid = 0; }
        if (++n > TIMEOUT) fail("AW/W");
    }
    n = 0;
    while (!top->s_axi_bvalid) { tick(); if (++n > TIMEOUT) fail("B"); }
    tick();
    top->s_axi_bready = 0;
}

// ---- AXI DMA, simple mode, MM2S only ---------------------------------------
static XAxiDma_Config g_cfg = {0, 0x40400000u, 0};

extern "C" XAxiDma_Config *XAxiDma_LookupConfig(u32 id) { return id == 0 ? &g_cfg : nullptr; }
extern "C" int XAxiDma_CfgInitialize(XAxiDma *d, XAxiDma_Config *c) { d->cfg = *c; d->busy = 0; return XST_SUCCESS; }
extern "C" int XAxiDma_HasSg(XAxiDma *d) { return d->cfg.HasSg; }
extern "C" void XAxiDma_IntrDisable(XAxiDma *, u32, int) {}
extern "C" int XAxiDma_Busy(XAxiDma *d, int) { InModel m; tick(); return d->busy; }

// The A9 is little-endian, so MM2S puts byte 0 of each word on TDATA[7:0].
// The driver pre-swaps for exactly this; the model must not undo it.
extern "C" int XAxiDma_SimpleTransfer(XAxiDma *d, UINTPTR buf, u32 len, int dir) {
    if (dir != XAXIDMA_DMA_TO_DEVICE || (len & 3)) return XST_FAILURE;
    InModel m;
    const uint8_t *p = (const uint8_t *)buf;
    u32 beats = len / 4;
    d->busy = 1;
    for (u32 i = 0; i < beats; i++) {
        top->s_axis_tdata = (uint32_t)p[4 * i] | ((uint32_t)p[4 * i + 1] << 8) |
                            ((uint32_t)p[4 * i + 2] << 16) | ((uint32_t)p[4 * i + 3] << 24);
        top->s_axis_tkeep = 0xF;
        top->s_axis_tlast = (i == beats - 1);
        top->s_axis_tvalid = 1;
        uint64_t n = 0;
        for (;;) {
            top->eval();
            bool hs = top->s_axis_tready;
            tick();
            if (hs) break;
            if (++n > 200000) fail("AXIS beat");
        }
    }
    top->s_axis_tvalid = 0;
    top->s_axis_tlast = 0;
    d->busy = 0;
    return XST_SUCCESS;
}

// ---- UART and timer ---------------------------------------------------------
extern "C" char inbyte(void) {
    int c = std::getchar();
    return c == EOF ? '\n' : (char)c;
}
extern "C" void outbyte(char c) { std::putchar(c); }

extern "C" void XTime_GetTime(XTime *t) {
    double host = std::chrono::duration<double>(clk::now() - t_start).count();
    double sw_sec = host - model_host_sec;                  // CPU time outside the model
    *t = cycles + (XTime)(sw_sec * (double)COUNTS_PER_SECOND);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vsha256_top;
    t_start = clk::now();
    top->s_axi_aresetn = 0;
    for (int i = 0; i < 8; i++) tick();
    top->s_axi_aresetn = 1;
    for (int i = 0; i < 4; i++) tick();

    int rc = board_main();

    std::printf("\n[virtual board] board_main returned %d after %llu PL cycles\n", rc,
                (unsigned long long)cycles);
    top->final();
    delete top;
    return rc;
}
