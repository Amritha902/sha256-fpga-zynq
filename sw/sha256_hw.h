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

/*--- dual-stream extension: Configs C and D only ---------------------------*/
#define SHA256_REG_DIGEST_B0    0x38u   /* R  stream 1's H0 .. H7, 0x38..0x54 */
#define SHA256_REG_CAPS         0x58u   /* R  capability bits                 */

#define SHA256_CAPS_DUAL        (1u << 0)  /* two digests; BLOCK_CNT is per
                                            * stream and both streams must
                                            * have the SAME block count      */

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
#define SHA256_ERR_NOT_DUAL    -5   /* pair API used on a single-stream build */
#define SHA256_ERR_LEN_MISMATCH -6  /* the two messages need the same block
                                     * count -- see sha256_hw_blocks_for()   */

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
 * Works on every configuration: on a dual-stream build (C or D) the message
 * is hashed as a pair with itself, wasting one slot, and is limited to
 * 32 KB padded.
 * Returns SHA256_OK or a negative error code. */
int sha256_hw_hash(const uint8_t *msg, size_t msg_len, uint8_t digest[32]);

/* Cycles counted by the accelerator for the most recent message. */
uint32_t sha256_hw_last_cycles(void);

/*--- dual-stream API -------------------------------------------------------
 *
 *  Configs C and D hash TWO INDEPENDENT messages at once. Discover support at
 *  run time rather than assuming it: a single-stream bitstream reports 0 and
 *  everything above still works unchanged.
 *-------------------------------------------------------------------------*/

/* 1 if the loaded bitstream is an interleaved core (Config C or D). */
int sha256_hw_is_dual(void);

/* Number of 512-bit blocks a message of this length pads to. Use it to check
 * two messages will pair before calling sha256_hw_hash_pair(). */
uint32_t sha256_hw_blocks_for(size_t msg_len);

/* Hash two independent messages in a single pass.
 *
 * Both must pad to the SAME number of blocks -- the two streams advance
 * through the core in lockstep, so there is no way to retire one early.
 * Returns SHA256_ERR_LEN_MISMATCH if they do not, and SHA256_ERR_NOT_DUAL on
 * a single-stream build.
 *
 * On success digest0 and digest1 hold the two results, and
 * sha256_hw_last_cycles() reports the cycles for the PAIR -- halve it for a
 * per-message figure. */
int sha256_hw_hash_pair(const uint8_t *msg0, size_t len0,
                        const uint8_t *msg1, size_t len1,
                        uint8_t digest0[32], uint8_t digest1[32]);

/* Interleave two already-padded buffers into the wire order the dual-stream
 * wrapper expects: 64 bytes of stream 0's block i, then 64 bytes of stream
 * 1's block i, repeating.
 *
 * Exposed separately from the driver so the ordering can be unit-tested on a
 * host with no Xilinx headers -- see sw/test_sw.c. Returns the interleaved
 * length, or 0 if out_cap is too small. */
size_t sha256_interleave_blocks(const uint8_t *p0, const uint8_t *p1,
                                size_t padded_len_each,
                                uint8_t *out, size_t out_cap);

/* Raw register access, exposed for the register-map self-test. */
uint32_t sha256_hw_read_reg(uint32_t offset);
void     sha256_hw_write_reg(uint32_t offset, uint32_t value);

#endif /* SHA256_HW_H */
