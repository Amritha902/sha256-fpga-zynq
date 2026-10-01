#ifndef XTIME_L_H
#define XTIME_L_H
#include "xil_types.h"
typedef u64 XTime;
/* One count = one 100 MHz PL clock. Time spent in the RTL model is counted
 * in simulated cycles; time the CPU spends in software is host time. */
#define COUNTS_PER_SECOND 100000000ULL
#ifdef __cplusplus
extern "C" {
#endif
void XTime_GetTime(XTime *t);
#ifdef __cplusplus
}
#endif
#endif
