/*============================================================================
 *  main.c  —  SHA-256 accelerator application (Vitis bare-metal, Cortex-A9)
 *----------------------------------------------------------------------------
 *  Runs on the ZedBoard.  Over the USB-UART (115200 8N1) it:
 *
 *    1. checks the accelerator register map
 *    2. runs the NIST FIPS 180-4 conformance vectors in hardware
 *    3. cross-checks every hardware digest against the software reference
 *    4. benchmarks hardware against software and reports the speedup
 *    5. offers an interactive mode: type a message, get its hash
 *
 *  This is deliverable (6) of the brief -- the end-to-end product.
 *==========================================================================*/

#include <stdio.h>
#include <string.h>

#include "xparameters.h"
#include "xil_printf.h"
#include "xtime_l.h"
#include "xil_cache.h"

#include "sha256_hw.h"
#include "sha256_sw.h"

void init_platform_cache(void);   /* defined at the bottom of this file */

/*---------------------------------------------------------------------------
 *  Configuration
 *-------------------------------------------------------------------------*/
#define PL_CLK_HZ         100000000u    /* PL clock, must match the design */
#define BENCH_BYTES       4096u         /* message size for the benchmark  */
#define BENCH_ITERATIONS  64u

/* COUNTS_PER_SECOND comes from xtime_l.h; the A9 global timer runs at half
 * the CPU clock, so it is typically 333333333 on a 667 MHz ZedBoard. */

/*---------------------------------------------------------------------------
 *  NIST FIPS 180-4 test vectors
 *-------------------------------------------------------------------------*/
typedef struct {
    const char *msg;
    size_t      len;
    const char *digest;
    const char *label;
} vector_t;

static const vector_t VECTORS[] = {
    { "", 0,
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "empty message           (1 block )" },
    { "abc", 3,
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "\"abc\"                    (1 block )" },
    { "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56,
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
      "56-byte message         (2 blocks)" },
    { "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn"
      "hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu", 112,
      "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
      "112-byte message        (2 blocks)" },
};
#define NUM_VECTORS (sizeof(VECTORS) / sizeof(VECTORS[0]))

static uint8_t g_bench_msg[BENCH_BYTES];

/*---------------------------------------------------------------------------
 *  Helpers
 *-------------------------------------------------------------------------*/
static void banner(const char *text)
{
    xil_printf("\r\n");
    xil_printf("==========================================================\r\n");
    xil_printf(" %s\r\n", text);
    xil_printf("==========================================================\r\n");
}

static int uart_getline(char *buf, int cap)
{
    int n = 0;
    int c;
    for (;;) {
        c = inbyte();
        if (c == '\r' || c == '\n') {
            outbyte('\r'); outbyte('\n');
            buf[n] = '\0';
            return n;
        }
        if ((c == 0x08 || c == 0x7F) && n > 0) {     /* backspace */
            n--;
            outbyte('\b'); outbyte(' '); outbyte('\b');
            continue;
        }
        if (c >= 0x20 && c < 0x7F && n < cap - 1) {
            buf[n++] = (char)c;
            outbyte(c);
        }
    }
}

/*---------------------------------------------------------------------------
 *  Test 1 — register map
 *-------------------------------------------------------------------------*/
static int test_registers(void)
{
    uint32_t v, rb;
    int fails = 0;

    banner("TEST 1 : register map");

    v = sha256_hw_read_reg(SHA256_REG_VERSION);
    xil_printf("  VERSION       = 0x%08x  expected 0x%08x  [%s]\r\n",
               v, SHA256_VERSION_ID,
               (v == SHA256_VERSION_ID) ? "PASS" : "FAIL");
    if (v != SHA256_VERSION_ID) fails++;

    sha256_hw_write_reg(SHA256_REG_BLOCK_CNT, 0x1234u);
    rb = sha256_hw_read_reg(SHA256_REG_BLOCK_CNT);
    xil_printf("  BLOCK_CNT r/w = 0x%08x  expected 0x00001234  [%s]\r\n",
               rb, (rb == 0x1234u) ? "PASS" : "FAIL");
    if (rb != 0x1234u) fails++;

    v = sha256_hw_read_reg(SHA256_REG_STATUS);
    xil_printf("  STATUS        = 0x%08x  (busy=%d ready=%d)\r\n",
               v, (int)(v & SHA256_STAT_BUSY),
               (int)((v & SHA256_STAT_CORE_READY) ? 1 : 0));

    return fails;
}

/*---------------------------------------------------------------------------
 *  Test 2 — NIST conformance in hardware, cross-checked in software
 *-------------------------------------------------------------------------*/
static int test_vectors(void)
{
    uint8_t hw_dig[32], sw_dig[32];
    char    hw_hex[65], sw_hex[65];
    int     fails = 0;
    unsigned i;
    int     rc;

    banner("TEST 2 : NIST FIPS 180-4 conformance");

    for (i = 0; i < NUM_VECTORS; i++) {
        rc = sha256_hw_hash((const uint8_t *)VECTORS[i].msg,
                            VECTORS[i].len, hw_dig);
        if (rc != SHA256_OK) {
            xil_printf("  [FAIL] %s  driver error %d\r\n", VECTORS[i].label, rc);
            fails++;
            continue;
        }
        sha256_sw((const uint8_t *)VECTORS[i].msg, VECTORS[i].len, sw_dig);
        sha256_hex(hw_dig, hw_hex);
        sha256_hex(sw_dig, sw_hex);

        int ok_nist = (strcmp(hw_hex, VECTORS[i].digest) == 0);
        int ok_sw   = (strcmp(hw_hex, sw_hex) == 0);

        xil_printf("  [%s] %s\r\n",
                   (ok_nist && ok_sw) ? "PASS" : "FAIL", VECTORS[i].label);
        xil_printf("         hw : %s\r\n", hw_hex);
        if (!ok_nist) {
            xil_printf("         ref: %s   <-- MISMATCH\r\n", VECTORS[i].digest);
            fails++;
        }
        if (!ok_sw) {
            xil_printf("         sw : %s   <-- HW/SW MISMATCH\r\n", sw_hex);
            fails++;
        }
        xil_printf("         cycles = %u\r\n",
                   (unsigned)sha256_hw_last_cycles());
    }
    return fails;
}

/*---------------------------------------------------------------------------
 *  Test 3 — hardware vs software benchmark
 *-------------------------------------------------------------------------*/
/*---------------------------------------------------------------------------
 *  TEST 4 : dual-stream -- Configs C and D only
 *
 *  Skipped, not failed, on a single-stream bitstream. The capability is read
 *  from the CAPS register rather than assumed, so one binary drives all four
 *  configurations.
 *-------------------------------------------------------------------------*/
static int test_dual_stream(void)
{
    static const char *M0 = "abc";
    static const char *M1 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    static const char *D0 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    static const char *D1 = "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1";

    uint8_t  dig0[32], dig1[32], swd[32];
    char     hex0[65], hex1[65], swhex[65];
    uint32_t pair_cycles;
    int      fails = 0;
    int      rc;

    banner("TEST 4 : dual-stream interleaving");

    if (!sha256_hw_is_dual()) {
        xil_printf("  CAPS.dual_stream = 0 -- single-stream core "
                   "(Config A or B).\r\n");
        xil_printf("  SKIPPED. This test needs a Config C or D bitstream.\r\n");
        return 0;
    }
    xil_printf("  CAPS.dual_stream = 1 -- interleaved core "
               "(Config C or D).\r\n\r\n");

    /* The two streams advance in lockstep, so the driver must refuse a pair
     * whose block counts differ. Prove it does before trusting a result. */
    rc = sha256_hw_hash_pair((const uint8_t*)"abc", 3,
                             (const uint8_t*)M1, 56, dig0, dig1);
    xil_printf("  mismatched block counts rejected : %s\r\n",
               rc == SHA256_ERR_LEN_MISMATCH ? "PASS" : "FAIL");
    if (rc != SHA256_ERR_LEN_MISMATCH) { fails++; }

    /* Two DIFFERENT messages of equal block count, hashed in one pass. */
    rc = sha256_hw_hash_pair((const uint8_t*)M0, 3,
                             (const uint8_t*)"xyz", 3, dig0, dig1);
    if (rc != SHA256_OK) {
        xil_printf("  [FAIL] hash_pair returned %d\r\n", rc);
        return fails + 1;
    }
    pair_cycles = sha256_hw_last_cycles();

    sha256_hex(dig0, hex0);
    sha256_hex(dig1, hex1);

    xil_printf("  stream 0 = \"abc\"\r\n");
    xil_printf("    hw  : %s\r\n", hex0);
    if (strcmp(hex0, D0) != 0) {
        xil_printf("    ref : %s   <-- MISMATCH\r\n", D0);
        fails++;
    } else {
        xil_printf("    [PASS] matches NIST\r\n");
    }

    sha256_sw((const uint8_t*)"xyz", 3, swd);
    sha256_hex(swd, swhex);
    xil_printf("  stream 1 = \"xyz\"\r\n");
    xil_printf("    hw  : %s\r\n", hex1);
    if (strcmp(hex1, swhex) != 0) {
        xil_printf("    sw  : %s   <-- HW/SW MISMATCH\r\n", swhex);
        fails++;
    } else {
        xil_printf("    [PASS] matches software reference\r\n");
    }

    /* Swap the slots: a result that depends on which stream a message went
     * into would mean the two contexts are not actually independent. */
    rc = sha256_hw_hash_pair((const uint8_t*)"xyz", 3,
                             (const uint8_t*)M0, 3, dig0, dig1);
    if (rc == SHA256_OK) {
        sha256_hex(dig1, hex1);
        xil_printf("  slots swapped, \"abc\" now on stream 1 : %s\r\n",
                   strcmp(hex1, D0) == 0 ? "PASS" : "FAIL");
        if (strcmp(hex1, D0) != 0) { fails++; }
    }

    /* Multi-block on both streams at once. */
    rc = sha256_hw_hash_pair((const uint8_t*)M1, 56,
                             (const uint8_t*)M1, 56, dig0, dig1);
    if (rc == SHA256_OK) {
        sha256_hex(dig0, hex0);
        sha256_hex(dig1, hex1);
        xil_printf("  two-block message on both streams   : %s\r\n",
                   (strcmp(hex0, D1) == 0 && strcmp(hex1, D1) == 0)
                   ? "PASS" : "FAIL");
        if (strcmp(hex0, D1) != 0 || strcmp(hex1, D1) != 0) { fails++; }
    }

    xil_printf("\r\n  cycles for the PAIR  : %u\r\n", (unsigned)pair_cycles);
    xil_printf("  per message          : %u  (two digests retired)\r\n",
               (unsigned)(pair_cycles / 2u));
    xil_printf("\r\n  NOTE: interleaving helps only when there are two\r\n");
    xil_printf("  INDEPENDENT messages. Single-message latency is\r\n");
    xil_printf("  unchanged, and a lone message wastes one slot.\r\n");

    return fails;
}

static void benchmark(void)
{
    uint8_t  dig[32];
    XTime    t0, t1;
    double   hw_sec, sw_sec;
    uint32_t i;
    uint64_t total_bits;
    uint32_t hw_cycles;

    banner("TEST 3 : hardware vs software throughput");

    for (i = 0; i < BENCH_BYTES; i++) {
        g_bench_msg[i] = (uint8_t)(i & 0xFF);
    }
    total_bits = (uint64_t)BENCH_BYTES * 8u * BENCH_ITERATIONS;

    /* ---- hardware ---- */
    XTime_GetTime(&t0);
    for (i = 0; i < BENCH_ITERATIONS; i++) {
        sha256_hw_hash(g_bench_msg, BENCH_BYTES, dig);
    }
    XTime_GetTime(&t1);
    hw_sec = (double)(t1 - t0) / (double)COUNTS_PER_SECOND;
    hw_cycles = sha256_hw_last_cycles();

    /* ---- software ---- */
    XTime_GetTime(&t0);
    for (i = 0; i < BENCH_ITERATIONS; i++) {
        sha256_sw(g_bench_msg, BENCH_BYTES, dig);
    }
    XTime_GetTime(&t1);
    sw_sec = (double)(t1 - t0) / (double)COUNTS_PER_SECOND;

    xil_printf("  message size        : %u bytes x %u iterations\r\n",
               (unsigned)BENCH_BYTES, (unsigned)BENCH_ITERATIONS);
    xil_printf("  blocks per message  : %u\r\n",
               (unsigned)(((BENCH_BYTES + 9 + 63) / 64)));
    xil_printf("  accelerator cycles  : %u  (last message)\r\n",
               (unsigned)hw_cycles);
    xil_printf("\r\n");
    printf("  hardware  : %.6f s   %.2f Mbit/s\r\n",
           hw_sec, (double)total_bits / hw_sec / 1e6);
    printf("  software  : %.6f s   %.2f Mbit/s\r\n",
           sw_sec, (double)total_bits / sw_sec / 1e6);
    printf("  speedup   : %.2fx\r\n", sw_sec / hw_sec);
    xil_printf("\r\n");
    xil_printf("  NOTE: a modest speedup is EXPECTED and correct.  SHA-256 is\r\n");
    xil_printf("  32-bit add, XOR and rotate -- exactly what an ALU does in\r\n");
    xil_printf("  one cycle each.  Unlike a block cipher there is no arithmetic\r\n");
    xil_printf("  the CPU must emulate.  The value here is offload and\r\n");
    xil_printf("  deterministic latency, not raw throughput multiplication.\r\n");
}

/*---------------------------------------------------------------------------
 *  Test 4 — interactive
 *-------------------------------------------------------------------------*/
static void interactive(void)
{
    static char line[512];
    uint8_t dig[32];
    char    hex[65];
    int     n;

    banner("INTERACTIVE : type a message, get its SHA-256");
    xil_printf("  Enter an empty line to quit.\r\n\r\n");

    for (;;) {
        xil_printf("  msg> ");
        n = uart_getline(line, sizeof line);
        if (n == 0) {
            xil_printf("  leaving interactive mode\r\n");
            return;
        }
        if (sha256_hw_hash((const uint8_t *)line, (size_t)n, dig) != SHA256_OK) {
            xil_printf("  driver error\r\n");
            continue;
        }
        sha256_hex(dig, hex);
        xil_printf("  hw  : %s\r\n", hex);
        sha256_sw((const uint8_t *)line, (size_t)n, dig);
        sha256_hex(dig, hex);
        xil_printf("  sw  : %s   [%s]\r\n\r\n", hex, "cross-check");
    }
}

/*---------------------------------------------------------------------------
 *  main
 *-------------------------------------------------------------------------*/
int main(void)
{
    int rc, fails = 0;

    init_platform_cache();

    banner("SHA-256 HARDWARE ACCELERATOR  -  ZedBoard XC7Z020");
    xil_printf(" Amritha S  -  23BEC1368\r\n");
    xil_printf(" PL clock : %u Hz\r\n", (unsigned)PL_CLK_HZ);

    rc = sha256_hw_init();
    if (rc != SHA256_OK) {
        xil_printf("\r\n FATAL: sha256_hw_init failed, code %d\r\n", rc);
        if (rc == SHA256_ERR_VERSION) {
            xil_printf(" The VERSION register did not read 0x53480001.\r\n");
            xil_printf(" Check the base address in xparameters.h and that the\r\n");
            xil_printf(" bitstream currently programmed matches this build.\r\n");
        }
        if (rc == SHA256_ERR_DMA) {
            xil_printf(" AXI DMA init failed. Check that scatter-gather is\r\n");
            xil_printf(" DISABLED and the MM2S channel is enabled in Vivado.\r\n");
        }
        return 1;
    }
    xil_printf(" Accelerator detected and initialised.\r\n");

    fails += test_registers();
    fails += test_vectors();
    fails += test_dual_stream();
    benchmark();

    banner("SUMMARY");
    if (fails == 0) {
        xil_printf("  ALL CONFORMANCE CHECKS PASSED\r\n");
    } else {
        xil_printf("  %d FAILURE(S) -- see above\r\n", fails);
    }

    interactive();

    banner("DONE");
    return 0;
}

/*---------------------------------------------------------------------------
 *  Cache setup.  Kept in one place so it is easy to find and easy to
 *  disable while debugging a suspected coherency problem.
 *-------------------------------------------------------------------------*/
void init_platform_cache(void)
{
    Xil_ICacheEnable();
    Xil_DCacheEnable();
}
