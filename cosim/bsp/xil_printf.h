#ifndef XIL_PRINTF_H
#define XIL_PRINTF_H
#include <stdio.h>
#define xil_printf printf
#ifdef __cplusplus
extern "C" {
#endif
char inbyte(void);                      /* UART RX <- stdin                   */
void outbyte(char c);                   /* UART TX -> stdout                  */
#ifdef __cplusplus
}
#endif
#endif
