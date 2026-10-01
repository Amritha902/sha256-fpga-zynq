#ifndef XIL_IO_H
#define XIL_IO_H
#include "xil_types.h"
#ifdef __cplusplus
extern "C" {
#endif
u32  Xil_In32(UINTPTR addr);            /* -> AXI4-Lite read on the RTL model  */
void Xil_Out32(UINTPTR addr, u32 val);  /* -> AXI4-Lite write on the RTL model */
#ifdef __cplusplus
}
#endif
#endif
