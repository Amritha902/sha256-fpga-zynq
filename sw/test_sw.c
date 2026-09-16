#include <stdio.h>
#include <string.h>
#include "sha256_sw.h"

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
    printf("\nRESULT: %s\n\n", ok ? "ALL SOFTWARE CHECKS PASSED" : "FAILURES PRESENT");
    return ok ? 0 : 1;
}
