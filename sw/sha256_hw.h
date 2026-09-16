/*============================================================================
 *  sha256_hw.h  —  driver for the SHA-256 accelerator IP
 *----------------------------------------------------------------------------
 *  Register map (byte offsets from the AXI4-Lite base address).
 *  Must match rtl/sha256_axi_lite_regs.v exactly.
 *==========================================================================*/
#ifndef SHA256_HW_H
#define SHA256_HW_H

#include <stdint.h>
#include <stddef.h>

/*--- register offsets ------------------------------------------------------*/
#define SHA256_REG_CTRL         0x00u   /* W  */
#define SHA256_REG_STATUS       0x04u   /* R  */
#define SHA256_REG_BLOCK_CNT    0x08u   /* RW */
#define SHA256_REG_BLOCKS_DONE  0x0Cu   /* R  */
#define SHA256_REG_DIGEST0      0x10u   /* R  H0 .. H7 at 0x10 .. 0x2C */
#define SHA256_REG_CYCLE_CNT    0x30u   /* R  */
#define SHA256_REG_VERSION      0x34u   /* R  */

/*--- CTRL bits -------------------------------------------------------------*/
#define SHA256_CTRL_START       (1u << 0)
#define SHA256_CTRL_INIT        (1u << 1)   /* 1 = new message, load H(0) */
#define SHA256_CTRL_SOFT_RESET  (1u << 2)

/*--- STATUS bits -----------------------------------------------------------*/
#define SHA256_STAT_BUSY        (1u << 0)
#define SHA256_STAT_DIGEST_VLD  (1u << 1)
#define SHA256_STAT_CORE_READY  (1u << 2)
#define SHA256_STAT_AXIS_ACTIVE (1u << 3)

/*--- expected VERSION value ------------------------------------------------*/
#define SHA256_VERSION_ID       0x53480001u

/*--- return codes ----------------------------------------------------------*/
#define SHA256_OK               0
#define SHA256_ERR_TIMEOUT     -1
#define SHA256_ERR_DMA         -2
#define SHA256_ERR_TOO_BIG     -3
#define SHA256_ERR_VERSION     -4

/*--- API -------------------------------------------------------------------*/

/* Initialise the DMA and check the accelerator VERSION register.
 * Call once at start-up.  Returns SHA256_OK or a negative error code. */
int sha256_hw_init(void);

/* Hash a message in hardware.
 *   msg      : input bytes
 *   msg_len  : length in bytes
 *   digest   : 32-byte output
 * Pads, byte-swaps, flushes the cache, runs the DMA, polls for completion
 * and reads the digest back over AXI4-Lite.
 * Returns SHA256_OK or a negative error code. */
int sha256_hw_hash(const uint8_t *msg, size_t msg_len, uint8_t digest[32]);

/* Cycles counted by the accelerator for the most recent message. */
uint32_t sha256_hw_last_cycles(void);

/* Raw register access, exposed for the register-map self-test. */
uint32_t sha256_hw_read_reg(uint32_t offset);
void     sha256_hw_write_reg(uint32_t offset, uint32_t value);

#endif /* SHA256_HW_H */
