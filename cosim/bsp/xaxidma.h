/* Virtual-board stub of the AXI DMA driver: simple-mode MM2S only, which is
 * all sha256_hw.c uses. SimpleTransfer streams the buffer into the RTL
 * model's AXI4-Stream port beat by beat, honouring TREADY. */
#ifndef XAXIDMA_H
#define XAXIDMA_H
#include "xil_types.h"
#include "xstatus.h"
#define XAXIDMA_DMA_TO_DEVICE  0x00
#define XAXIDMA_DEVICE_TO_DMA  0x01
#define XAXIDMA_IRQ_ALL_MASK   0x00007000
typedef struct { u32 DeviceId; UINTPTR BaseAddr; int HasSg; } XAxiDma_Config;
typedef struct { XAxiDma_Config cfg; int busy; } XAxiDma;
#ifdef __cplusplus
extern "C" {
#endif
XAxiDma_Config *XAxiDma_LookupConfig(u32 id);
int  XAxiDma_CfgInitialize(XAxiDma *d, XAxiDma_Config *c);
int  XAxiDma_HasSg(XAxiDma *d);
void XAxiDma_IntrDisable(XAxiDma *d, u32 mask, int dir);
int  XAxiDma_SimpleTransfer(XAxiDma *d, UINTPTR buf, u32 len, int dir);
int  XAxiDma_Busy(XAxiDma *d, int dir);
#ifdef __cplusplus
}
#endif
#endif
