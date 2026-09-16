/*============================================================================
 *  sha256_sw.c
 *----------------------------------------------------------------------------
 *  Portable SHA-256 software implementation, message padding, and the
 *  byte-swap helper the hardware path needs.
 *
 *  This file compiles UNCHANGED both natively (for host-side testing) and
 *  under Vitis for the ARM Cortex-A9.  It serves three purposes:
 *
 *    1. the software baseline the hardware speedup is measured against
 *    2. an independent check of the hardware digest on the board
 *    3. the padding and byte-ordering used to prepare DMA buffers
 *
 *  BYTE ORDER -- READ THIS BEFORE DEBUGGING ANYTHING
 *  --------------------------------------------------
 *  SHA-256 treats the message as BIG-ENDIAN 32-bit words.
 *  The Zynq PS is LITTLE-ENDIAN, and the AXI DMA copies bytes verbatim:
 *  memory bytes at offsets 0,1,2,3 arrive as tdata[7:0],[15:8],[23:16],[31:24].
 *
 *  So a padded buffer sent directly would give the hardware byte-reversed
 *  words.  sha256_swap_words32() reverses each 4-byte group in place so that
 *  the value the fabric sees on tdata IS the big-endian message word.
 *
 *  Call order for the hardware path:
 *      sha256_pad()            -> padded buffer, correct SHA byte order
 *      sha256_swap_words32()   -> pre-compensate for the DMA's byte order
 *      Xil_DCacheFlushRange()  -> make it visible to the DMA
 *      XAxiDma_SimpleTransfer()
 *==========================================================================*/

#include "sha256_sw.h"
#include <string.h>

/*---------------------------------------------------------------------------
 *  Constants
 *-------------------------------------------------------------------------*/

/* first 32 bits of the fractional parts of the square roots of primes 2..19 */
static const uint32_t H_INIT[8] = {
    0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
    0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u
};

/* first 32 bits of the fractional parts of the cube roots of the first
 * 64 primes -- "nothing up my sleeve" numbers */
static const uint32_t K[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u
};

/*---------------------------------------------------------------------------
 *  Primitives -- mirror the Verilog exactly
 *-------------------------------------------------------------------------*/
#define ROTR(x,n)   (((x) >> (n)) | ((x) << (32 - (n))))
#define SHR(x,n)    ((x) >> (n))
#define CH(x,y,z)   (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z)  (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define BSIG0(x)    (ROTR(x, 2) ^ ROTR(x,13) ^ ROTR(x,22))
#define BSIG1(x)    (ROTR(x, 6) ^ ROTR(x,11) ^ ROTR(x,25))
#define SSIG0(x)    (ROTR(x, 7) ^ ROTR(x,18) ^ SHR (x, 3))
#define SSIG1(x)    (ROTR(x,17) ^ ROTR(x,19) ^ SHR (x,10))

/*---------------------------------------------------------------------------
 *  One 512-bit block through the compression function
 *-------------------------------------------------------------------------*/
static void sha256_compress(uint32_t h[8], const uint8_t block[64])
{
    uint32_t w[64];
    uint32_t a, b, c, d, e, f, g, hh, t1, t2;
    int t;

    for (t = 0; t < 16; t++) {
        w[t] = ((uint32_t)block[4*t + 0] << 24) |
               ((uint32_t)block[4*t + 1] << 16) |
               ((uint32_t)block[4*t + 2] <<  8) |
               ((uint32_t)block[4*t + 3]);
    }
    for (t = 16; t < 64; t++) {
        w[t] = SSIG1(w[t-2]) + w[t-7] + SSIG0(w[t-15]) + w[t-16];
    }

    a = h[0]; b = h[1]; c = h[2]; d  = h[3];
    e = h[4]; f = h[5]; g = h[6]; hh = h[7];

    for (t = 0; t < 64; t++) {
        t1 = hh + BSIG1(e) + CH(e,f,g) + K[t] + w[t];
        t2 = BSIG0(a) + MAJ(a,b,c);
        hh = g;  g = f;  f = e;  e = d + t1;
        d  = c;  c = b;  b = a;  a = t1 + t2;
    }

    h[0] += a;  h[1] += b;  h[2] += c;  h[3] += d;
    h[4] += e;  h[5] += f;  h[6] += g;  h[7] += hh;
}

/*---------------------------------------------------------------------------
 *  Padding (FIPS 180-4 section 5.1.1)
 *
 *  Appends 0x80, then zeros, then the 64-bit big-endian bit length, so that
 *  the total is a whole number of 512-bit blocks.
 *
 *  Returns the padded length in bytes, or 0 if out_cap is too small.
 *-------------------------------------------------------------------------*/
size_t sha256_pad(const uint8_t *msg, size_t msg_len,
                  uint8_t *out, size_t out_cap)
{
    size_t   padded_len;
    uint64_t bit_len;
    size_t   i;

    /* 1 byte for 0x80, 8 bytes for the length, round up to 64 */
    padded_len = ((msg_len + 9 + 63) / 64) * 64;
    if (padded_len > out_cap) {
        return 0;
    }

    memcpy(out, msg, msg_len);
    out[msg_len] = 0x80u;
    for (i = msg_len + 1; i < padded_len - 8; i++) {
        out[i] = 0x00u;
    }

    bit_len = (uint64_t)msg_len * 8u;
    for (i = 0; i < 8; i++) {
        out[padded_len - 1 - i] = (uint8_t)(bit_len >> (8 * i));
    }

    return padded_len;
}

/*---------------------------------------------------------------------------
 *  Reverse each 4-byte group in place.
 *
 *  Pre-compensates for the DMA's little-endian byte packing so the fabric
 *  receives correctly ordered big-endian SHA words.  See the header comment.
 *-------------------------------------------------------------------------*/
void sha256_swap_words32(uint8_t *buf, size_t len)
{
    size_t  i;
    uint8_t t;

    for (i = 0; i + 3 < len; i += 4) {
        t = buf[i];     buf[i]     = buf[i + 3]; buf[i + 3] = t;
        t = buf[i + 1]; buf[i + 1] = buf[i + 2]; buf[i + 2] = t;
    }
}

/*---------------------------------------------------------------------------
 *  Full software SHA-256 -- the baseline and the on-board cross-check
 *-------------------------------------------------------------------------*/
void sha256_sw(const uint8_t *msg, size_t msg_len, uint8_t digest[32])
{
    uint8_t  block[64];
    uint32_t h[8];
    uint64_t bit_len = (uint64_t)msg_len * 8u;
    size_t   i, off, rem;
    int      j;

    for (j = 0; j < 8; j++) h[j] = H_INIT[j];

    /* whole blocks straight from the message */
    for (off = 0; off + 64 <= msg_len; off += 64) {
        sha256_compress(h, msg + off);
    }

    /* final partial block plus padding */
    rem = msg_len - off;
    memcpy(block, msg + off, rem);
    block[rem] = 0x80u;

    if (rem >= 56) {
        for (i = rem + 1; i < 64; i++) block[i] = 0x00u;
        sha256_compress(h, block);
        rem = 0;
        memset(block, 0, 64);
    } else {
        for (i = rem + 1; i < 56; i++) block[i] = 0x00u;
    }

    for (i = 0; i < 8; i++) {
        block[63 - i] = (uint8_t)(bit_len >> (8 * i));
    }
    sha256_compress(h, block);

    for (j = 0; j < 8; j++) {
        digest[4*j + 0] = (uint8_t)(h[j] >> 24);
        digest[4*j + 1] = (uint8_t)(h[j] >> 16);
        digest[4*j + 2] = (uint8_t)(h[j] >>  8);
        digest[4*j + 3] = (uint8_t)(h[j]);
    }
}

/*---------------------------------------------------------------------------
 *  Format a 32-byte digest as 64 lowercase hex characters (65 bytes out)
 *-------------------------------------------------------------------------*/
void sha256_hex(const uint8_t digest[32], char *out65)
{
    static const char hexchars[] = "0123456789abcdef";
    int i;
    for (i = 0; i < 32; i++) {
        out65[2*i    ] = hexchars[(digest[i] >> 4) & 0xF];
        out65[2*i + 1] = hexchars[ digest[i]       & 0xF];
    }
    out65[64] = '\0';
}
