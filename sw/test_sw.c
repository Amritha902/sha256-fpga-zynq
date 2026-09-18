#include <stdio.h>
#include <string.h>
#include "sha256_sw.h"
#include "sha256_hw.h"

static int check(const char *msg, size_t len, const char *expect, const char *label) {
    uint8_t d[32]; char hex[65];
    sha256_sw((const uint8_t*)msg, len, d);
    sha256_hex(d, hex);
    int ok = (strcmp(hex, expect) == 0);
    printf("  [%s]  %-34s %s\n", ok ? "PASS" : "FAIL", label, hex);
    if (!ok) printf("          expected                           %s\n", expect);
    return ok;
}

int main(void) {
    int ok = 1;
    static char million[1000000];
    printf("\n=== SOFTWARE SHA-256 SELF-TEST (FIPS 180-4) ===\n");
    ok &= check("", 0,
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "empty message");
    ok &= check("abc", 3,
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "\"abc\"");
    ok &= check("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56,
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "56-byte, two blocks");
    ok &= check("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu", 112,
        "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1", "112-byte");
    memset(million, 'a', sizeof million);
    ok &= check(million, sizeof million,
        "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", "one million 'a'");

    printf("\n=== PADDING + BYTE-SWAP ROUND TRIP ===\n");
    {
        uint8_t buf[128]; size_t n;
        n = sha256_pad((const uint8_t*)"abc", 3, buf, sizeof buf);
        printf("  padded length for \"abc\"      : %zu bytes (%zu block%s)  %s\n",
               n, n/64, n/64==1?"":"s", n==64 ? "PASS" : "FAIL");
        ok &= (n == 64);
        printf("  first 8 padded bytes         : %02x %02x %02x %02x %02x %02x %02x %02x\n",
               buf[0],buf[1],buf[2],buf[3],buf[4],buf[5],buf[6],buf[7]);
        printf("  last 4 (bit length = 24)     : %02x %02x %02x %02x  %s\n",
               buf[60],buf[61],buf[62],buf[63],
               (buf[63]==0x18 && buf[62]==0) ? "PASS" : "FAIL");
        ok &= (buf[63] == 0x18);

        sha256_swap_words32(buf, n);
        printf("  after swap, first word bytes : %02x %02x %02x %02x   (was 61 62 63 80)  %s\n",
               buf[0],buf[1],buf[2],buf[3],
               (buf[0]==0x80 && buf[1]==0x63 && buf[2]==0x62 && buf[3]==0x61) ? "PASS" : "FAIL");
        ok &= (buf[0]==0x80 && buf[3]==0x61);

        sha256_swap_words32(buf, n);   /* swapping twice must restore */
        printf("  swap is its own inverse      : %s\n",
               (buf[0]==0x61 && buf[3]==0x80) ? "PASS" : "FAIL");
        ok &= (buf[0]==0x61);

        n = sha256_pad((const uint8_t*)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56, buf, sizeof buf);
        printf("  padded length for 56 bytes   : %zu bytes (%zu blocks)  %s\n",
               n, n/64, n==128 ? "PASS" : "FAIL");
        ok &= (n == 128);
    }

    /*=====================================================================
     *  DUAL-STREAM WIRE FORMAT  (Configs C and D)
     *
     *  Configs C and D hash two independent messages at once, so the PS must
     *  interleave two padded buffers block-by-block before the DMA sees them:
     *
     *      [s0 block 0][s1 block 0][s0 block 1][s1 block 1] ...
     *
     *  Get this wrong and BOTH digests come back looking like valid SHA-256
     *  output while both are wrong -- the worst class of bug to chase on a
     *  board. So it is tested here, natively, before it reaches hardware.
     *===================================================================*/
    printf("\n=== DUAL-STREAM BLOCK INTERLEAVING ===\n");
    {
        /* --- blocks_for() at the padding boundaries -------------------- */
        static const struct { size_t len; uint32_t blocks; } BL[] = {
            {  0, 1}, {  1, 1}, { 54, 1}, { 55, 1}, { 56, 2}, { 63, 2},
            { 64, 2}, { 65, 2}, {119, 2}, {120, 3}, {128, 3},
        };
        int i, bl_ok = 1;
        for (i = 0; i < (int)(sizeof BL / sizeof BL[0]); i++) {
            uint32_t got = sha256_hw_blocks_for(BL[i].len);
            if (got != BL[i].blocks) {
                printf("  [FAIL]  blocks_for(%zu) = %u, expected %u\n",
                       BL[i].len, got, BL[i].blocks);
                bl_ok = 0;
            }
        }
        printf("  [%s]  blocks_for() at padding boundaries\n",
               bl_ok ? "PASS" : "FAIL");
        ok &= bl_ok;

        /* 55 and 56 bytes straddle the boundary, so they must NOT pair --
         * the two streams advance through the core in lockstep. */
        printf("  [%s]  55-byte and 56-byte messages refuse to pair\n",
               sha256_hw_blocks_for(55) != sha256_hw_blocks_for(56)
               ? "PASS" : "FAIL");
        ok &= (sha256_hw_blocks_for(55) != sha256_hw_blocks_for(56));

        /* --- layout, with distinguishable per-block fill --------------- */
        {
            uint8_t a[128], b[128], out[256], small[64];
            size_t  n, j, k;
            int     order_ok = 1, rt = 1;

            for (j = 0; j < 128; j++) {
                a[j] = (uint8_t)(0x10 + (j / 64));    /* 0x10 then 0x11 */
                b[j] = (uint8_t)(0xA0 + (j / 64));    /* 0xA0 then 0xA1 */
            }

            n = sha256_interleave_blocks(a, b, 128, out, sizeof out);
            printf("  [%s]  interleaved length = %zu for 2 x 128 bytes\n",
                   n == 256 ? "PASS" : "FAIL", n);
            ok &= (n == 256);

            if (n == 256) {
                const uint8_t expect[4] = {0x10, 0xA0, 0x11, 0xA1};
                for (j = 0; j < 4; j++)
                    for (k = 0; k < 64; k++)
                        if (out[j*64 + k] != expect[j]) order_ok = 0;
                printf("  [%s]  block order is s0,s1,s0,s1\n",
                       order_ok ? "PASS" : "FAIL");
                ok &= order_ok;

                /* de-interleaving is what the wrapper does in hardware */
                for (j = 0; j < 2; j++)
                    for (k = 0; k < 64; k++) {
                        if (out[j*128 + k]      != a[j*64 + k]) rt = 0;
                        if (out[j*128 + 64 + k] != b[j*64 + k]) rt = 0;
                    }
                printf("  [%s]  de-interleave recovers both streams exactly\n",
                       rt ? "PASS" : "FAIL");
                ok &= rt;
            }

            /* malformed input must be refused, not silently truncated */
            printf("  [%s]  rejects non-block-aligned length\n",
                   sha256_interleave_blocks(a, b, 100, out, sizeof out) == 0
                   ? "PASS" : "FAIL");
            ok &= (sha256_interleave_blocks(a, b, 100, out, sizeof out) == 0);

            printf("  [%s]  rejects undersized output buffer\n",
                   sha256_interleave_blocks(a, b, 128, small, sizeof small) == 0
                   ? "PASS" : "FAIL");
            ok &= (sha256_interleave_blocks(a, b, 128, small, sizeof small) == 0);

            printf("  [%s]  rejects NULL input\n",
                   sha256_interleave_blocks(NULL, b, 128, out, sizeof out) == 0
                   ? "PASS" : "FAIL");
            ok &= (sha256_interleave_blocks(NULL, b, 128, out, sizeof out) == 0);
        }

        /* --- end to end: the exact sequence the driver performs -------- */
        {
            static const char *M56 =
                "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
            uint8_t p0[128], p1[128], fresh0[128], fresh1[128], wire[256];
            size_t  n0, n1, nw, j;
            int     e2e = 1;

            /* two 56-byte messages: both pad to exactly two blocks */
            n0 = sha256_pad((const uint8_t*)M56, 56, p0, sizeof p0);
            n1 = sha256_pad((const uint8_t*)M56, 56, p1, sizeof p1);
            memcpy(fresh0, p0, n0);
            memcpy(fresh1, p1, n1);

            e2e &= (n0 == 128 && n1 == 128);
            e2e &= (sha256_hw_blocks_for(56) == 2);

            sha256_swap_words32(p0, n0);
            sha256_swap_words32(p1, n1);
            nw = sha256_interleave_blocks(p0, p1, n0, wire, sizeof wire);
            e2e &= (nw == 256);

            printf("  [%s]  pad + swap + interleave, 2 x 56-byte messages\n",
                   e2e ? "PASS" : "FAIL");
            ok &= e2e;

            /* Undo exactly what the hardware will do, and confirm each
             * stream is bit-identical to its freshly padded form. If this
             * holds, the digests the accelerator returns must be correct. */
            if (nw == 256) {
                uint8_t back0[128], back1[128];
                int s0_ok, s1_ok;
                for (j = 0; j < 2; j++) {
                    memcpy(back0 + j*64, wire + j*128,      64);
                    memcpy(back1 + j*64, wire + j*128 + 64, 64);
                }
                sha256_swap_words32(back0, 128);
                sha256_swap_words32(back1, 128);
                s0_ok = (memcmp(back0, fresh0, 128) == 0);
                s1_ok = (memcmp(back1, fresh1, 128) == 0);
                printf("  [%s]  stream 0 survives the full round trip\n",
                       s0_ok ? "PASS" : "FAIL");
                printf("  [%s]  stream 1 survives the full round trip\n",
                       s1_ok ? "PASS" : "FAIL");
                ok &= (s0_ok && s1_ok);
            }
        }
    }

    printf("\nRESULT: %s\n\n", ok ? "ALL SOFTWARE CHECKS PASSED" : "FAILURES PRESENT");
    return ok ? 0 : 1;
}
