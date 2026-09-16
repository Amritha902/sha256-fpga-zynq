/*============================================================================
 *  sha256_hw.c  —  Vitis bare-metal driver for the SHA-256 accelerator
 *----------------------------------------------------------------------------
 *  Drives the accelerator through AXI4-Lite (control and digest readback)
 *  and AXI DMA MM2S (the message stream).
 *
 *  SEQUENCE PER MESSAGE
 *  --------------------
 *    1. sha256_pad()              pad to a whole number of 512-bit blocks
 *    2. sha256_swap_words32()     pre-compensate for the DMA's byte order
 *    3. Xil_DCacheFlushRange()    make the buffer visible to the DMA
 *    4. write BLOCK_CNT
 *    5. write CTRL = START | INIT
 *    6. XAxiDma_SimpleTransfer()  stream the padded buffer
 *    7. poll STATUS until DIGEST_VALID
 *    8. read DIGEST0..DIGEST7
 *
 *  Step 3 is the one everybody forgets.  The Cortex-A9 has a write-back
 *  data cache; without the flush the DMA reads stale DDR contents and the
 *  digest is silently wrong.  If the hardware disagrees with the software
 *  reference, check this FIRST.
 *==========================================================================*/

#include "sha256_hw.h"
#include "sha256_sw.h"

#include "xparameters.h"
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xstatus.h"

/*---------------------------------------------------------------------------
 *  Platform addresses.
 *
 *  Adjust these two if Vivado assigns different addresses -- check
 *  xparameters.h in the BSP after exporting the hardware.
 *-------------------------------------------------------------------------*/
#ifndef SHA256_BASEADDR
#define SHA256_BASEADDR   XPAR_SHA256_TOP_0_S_AXI_BASEADDR
#endif

#ifndef DMA_DEVICE_ID
#define DMA_DEVICE_ID     XPAR_AXIDMA_0_DEVICE_ID
#endif

/* Largest message this driver will handle in one call.
 * 64 KB of padded data = 1024 blocks.  Raise if your linker script allows. */
#define SHA256_MAX_PADDED  (64u * 1024u)

/* Polling guard: at 100 MHz a 1024-block message takes about 70k cycles,
 * so a million loop iterations is a very generous ceiling. */
#define SHA256_POLL_LIMIT  1000000u

/*---------------------------------------------------------------------------
 *  Module state
 *-------------------------------------------------------------------------*/
static XAxiDma  g_dma;
static uint32_t g_last_cycles = 0;

/* DMA source buffer.  Aligned to a cache line so the flush is exact.
 * Placed in .bss, which lives in DDR by default in the standard linker
 * script -- do NOT put it in OCM without checking the DMA can reach it. */
static uint8_t  g_padbuf[SHA256_MAX_PADDED] __attribute__((aligned(64)));

/*---------------------------------------------------------------------------
 *  Raw register access
 *-------------------------------------------------------------------------*/
uint32_t sha256_hw_read_reg(uint32_t offset)
{
    return Xil_In32(SHA256_BASEADDR + offset);
}

void sha256_hw_write_reg(uint32_t offset, uint32_t value)
{
    Xil_Out32(SHA256_BASEADDR + offset, value);
}

uint32_t sha256_hw_last_cycles(void)
{
    return g_last_cycles;
}

/*---------------------------------------------------------------------------
 *  Initialisation
 *-------------------------------------------------------------------------*/
int sha256_hw_init(void)
{
    XAxiDma_Config *cfg;
    int status;
    uint32_t version;

    cfg = XAxiDma_LookupConfig(DMA_DEVICE_ID);
    if (cfg == NULL) {
        return SHA256_ERR_DMA;
    }

    status = XAxiDma_CfgInitialize(&g_dma, cfg);
    if (status != XST_SUCCESS) {
        return SHA256_ERR_DMA;
    }

    if (XAxiDma_HasSg(&g_dma)) {
        /* This design uses Simple mode.  If the DMA was configured with
         * scatter-gather in Vivado, uncheck it and rebuild. */
        return SHA256_ERR_DMA;
    }

    /* interrupts off -- this driver polls */
    XAxiDma_IntrDisable(&g_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    XAxiDma_IntrDisable(&g_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);

    /* clear any stale state in the accelerator */
    sha256_hw_write_reg(SHA256_REG_CTRL, SHA256_CTRL_SOFT_RESET);

    version = sha256_hw_read_reg(SHA256_REG_VERSION);
    if (version != SHA256_VERSION_ID) {
        return SHA256_ERR_VERSION;
    }

    return SHA256_OK;
}

/*---------------------------------------------------------------------------
 *  Hash one message
 *-------------------------------------------------------------------------*/
int sha256_hw_hash(const uint8_t *msg, size_t msg_len, uint8_t digest[32])
{
    size_t   padded_len;
    uint32_t nblocks;
    uint32_t status_reg;
    uint32_t guard;
    uint32_t word;
    int      rc;
    int      i;

    /* ---- 1. pad ---------------------------------------------------------*/
    padded_len = sha256_pad(msg, msg_len, g_padbuf, SHA256_MAX_PADDED);
    if (padded_len == 0) {
        return SHA256_ERR_TOO_BIG;
    }
    nblocks = (uint32_t)(padded_len / 64u);

    /* ---- 2. pre-compensate for the DMA byte order -----------------------*/
    sha256_swap_words32(g_padbuf, padded_len);

    /* ---- 3. flush the cache so the DMA sees the real data ---------------*/
    Xil_DCacheFlushRange((UINTPTR)g_padbuf, padded_len);

    /* ---- 4/5. arm the accelerator ---------------------------------------*/
    sha256_hw_write_reg(SHA256_REG_BLOCK_CNT, nblocks);
    sha256_hw_write_reg(SHA256_REG_CTRL,
                        SHA256_CTRL_START | SHA256_CTRL_INIT);

    /* ---- 6. stream the padded message -----------------------------------*/
    rc = XAxiDma_SimpleTransfer(&g_dma, (UINTPTR)g_padbuf,
                                padded_len, XAXIDMA_DMA_TO_DEVICE);
    if (rc != XST_SUCCESS) {
        return SHA256_ERR_DMA;
    }

    /* wait for the DMA engine itself to drain */
    guard = 0;
    while (XAxiDma_Busy(&g_dma, XAXIDMA_DMA_TO_DEVICE)) {
        if (++guard > SHA256_POLL_LIMIT) {
            return SHA256_ERR_TIMEOUT;
        }
    }

    /* ---- 7. wait for the accelerator to finish the last block -----------*/
    guard = 0;
    do {
        status_reg = sha256_hw_read_reg(SHA256_REG_STATUS);
        if (++guard > SHA256_POLL_LIMIT) {
            return SHA256_ERR_TIMEOUT;
        }
    } while ((status_reg & SHA256_STAT_DIGEST_VLD) == 0u);

    g_last_cycles = sha256_hw_read_reg(SHA256_REG_CYCLE_CNT);

    /* ---- 8. read the digest back ----------------------------------------*/
    for (i = 0; i < 8; i++) {
        word = sha256_hw_read_reg(SHA256_REG_DIGEST0 + (uint32_t)(4 * i));
        digest[4*i + 0] = (uint8_t)(word >> 24);
        digest[4*i + 1] = (uint8_t)(word >> 16);
        digest[4*i + 2] = (uint8_t)(word >>  8);
        digest[4*i + 3] = (uint8_t)(word);
    }

    return SHA256_OK;
}
