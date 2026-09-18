/*============================================================================
 *  sha256_pair.c  —  dual-stream wire-format helpers
 *----------------------------------------------------------------------------
 *  Deliberately free of Xilinx headers so the block-interleaving order can be
 *  unit-tested on a host with gcc. Getting this ordering wrong produces two
 *  digests that both look plausible and are both wrong, which is exactly the
 *  class of bug that is miserable to find on a board -- so it is tested
 *  natively, before it ever reaches hardware. See sw/test_sw.c.
 *
 *  THE WIRE FORMAT
 *  ---------------
 *  sha256_axis_wrapper_dual collects 16 beats into stream 0's block, then 16
 *  beats into stream 1's block, then submits both to the core. Over a 32-bit
 *  AXI-Stream that is:
 *
 *      bytes    0.. 63   stream 0, block 0
 *      bytes   64..127   stream 1, block 0
 *      bytes  128..191   stream 0, block 1
 *      bytes  192..255   stream 1, block 1      ... and so on
 *
 *  One DMA channel, one descriptor, no second stream port.
 *==========================================================================*/

#include "sha256_hw.h"

#define SHA256_BLOCK_BYTES 64u

/*---------------------------------------------------------------------------
 *  How many 512-bit blocks a message of this length pads to.
 *
 *  FIPS 180-4 §5.1.1: append 0x80, then zeros, then a 64-bit big-endian bit
 *  length -- so the overhead is 9 bytes minimum, rounded up to a block.
 *-------------------------------------------------------------------------*/
uint32_t sha256_hw_blocks_for(size_t msg_len)
{
    return (uint32_t)((msg_len + 9u + (SHA256_BLOCK_BYTES - 1u))
                      / SHA256_BLOCK_BYTES);
}

/*---------------------------------------------------------------------------
 *  Interleave two equal-length padded buffers into the wire order above.
 *-------------------------------------------------------------------------*/
size_t sha256_interleave_blocks(const uint8_t *p0, const uint8_t *p1,
                                size_t padded_len_each,
                                uint8_t *out, size_t out_cap)
{
    size_t nblocks;
    size_t total;
    size_t b;
    size_t i;

    if (p0 == 0 || p1 == 0 || out == 0) {
        return 0u;
    }
    if (padded_len_each == 0u
        || (padded_len_each % SHA256_BLOCK_BYTES) != 0u) {
        return 0u;                      /* not a whole number of blocks */
    }

    nblocks = padded_len_each / SHA256_BLOCK_BYTES;
    total   = padded_len_each * 2u;
    if (total > out_cap) {
        return 0u;
    }

    for (b = 0; b < nblocks; b++) {
        const uint8_t *src0 = p0 + (b * SHA256_BLOCK_BYTES);
        const uint8_t *src1 = p1 + (b * SHA256_BLOCK_BYTES);
        uint8_t *dst = out + (b * 2u * SHA256_BLOCK_BYTES);

        for (i = 0; i < SHA256_BLOCK_BYTES; i++) {
            dst[i] = src0[i];
        }
        for (i = 0; i < SHA256_BLOCK_BYTES; i++) {
            dst[SHA256_BLOCK_BYTES + i] = src1[i];
        }
    }

    return total;
}
