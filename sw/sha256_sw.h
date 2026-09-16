/*============================================================================
 *  sha256_sw.h  —  portable SHA-256 software reference and helpers
 *==========================================================================*/
#ifndef SHA256_SW_H
#define SHA256_SW_H

#include <stdint.h>
#include <stddef.h>

/* Pad a message per FIPS 180-4 §5.1.1.
 * Returns the padded length in bytes, or 0 if out_cap is too small.
 * Required capacity: ((msg_len + 9 + 63) / 64) * 64  */
size_t sha256_pad(const uint8_t *msg, size_t msg_len,
                  uint8_t *out, size_t out_cap);

/* Reverse each 4-byte group in place, pre-compensating for the DMA's
 * little-endian byte packing.  Apply AFTER padding, BEFORE the transfer. */
void sha256_swap_words32(uint8_t *buf, size_t len);

/* Full software SHA-256 — baseline and on-board cross-check. */
void sha256_sw(const uint8_t *msg, size_t msg_len, uint8_t digest[32]);

/* Format a digest as 64 lowercase hex chars plus NUL (needs 65 bytes). */
void sha256_hex(const uint8_t digest[32], char *out65);

#endif /* SHA256_SW_H */
