#!/usr/bin/env python3
"""
SHA-256 golden reference model  (FIPS 180-4).

Purpose
-------
1. Bit-accurate software reference for the Verilog implementation.
2. Emit the per-round working-variable trace, so the RTL can be checked at
   every one of the 64 rounds rather than only on the final digest.
3. Generate the K-constant memory file used by the Verilog ROM, and the
   padded test blocks the testbench consumes.

Run:  python3 sha256_golden.py
"""

M32 = 0xFFFFFFFF

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------

# Initial hash H(0): first 32 bits of the fractional parts of the square
# roots of the first 8 primes (2, 3, 5, 7, 11, 13, 17, 19)
H_INIT = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
]

# K: first 32 bits of the fractional parts of the cube roots of the
# first 64 primes
K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]


# --------------------------------------------------------------------------
# Primitive functions
# --------------------------------------------------------------------------

def rotr(x, n):
    return ((x >> n) | (x << (32 - n))) & M32


def shr(x, n):
    return (x >> n) & M32


def ch(x, y, z):
    """Choose: bit of y where x is 1, bit of z where x is 0."""
    return (x & y) ^ (~x & z) & M32


def maj(x, y, z):
    """Majority vote, bitwise."""
    return (x & y) ^ (x & z) ^ (y & z)


def big_sigma0(x):
    return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22)


def big_sigma1(x):
    return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25)


def small_sigma0(x):
    return rotr(x, 7) ^ rotr(x, 18) ^ shr(x, 3)


def small_sigma1(x):
    return rotr(x, 17) ^ rotr(x, 19) ^ shr(x, 10)


# --------------------------------------------------------------------------
# Padding and compression
# --------------------------------------------------------------------------

def pad(message: bytes) -> bytes:
    """FIPS 180-4 section 5.1.1 padding."""
    ml = len(message) * 8
    padded = message + b"\x80"
    while (len(padded) % 64) != 56:
        padded += b"\x00"
    padded += ml.to_bytes(8, "big")
    return padded


def message_schedule(block: bytes):
    """Return the full 64-word schedule for one 512-bit block."""
    w = [int.from_bytes(block[4 * i:4 * i + 4], "big") for i in range(16)]
    for t in range(16, 64):
        w.append((small_sigma1(w[t - 2]) + w[t - 7]
                  + small_sigma0(w[t - 15]) + w[t - 16]) & M32)
    return w


def compress(h, block, trace=None):
    """One 512-bit block through the compression function."""
    w = message_schedule(block)
    a, b, c, d, e, f, g, hh = h

    for t in range(64):
        if trace is not None:
            trace.append((t, w[t], [a, b, c, d, e, f, g, hh]))
        t1 = (hh + big_sigma1(e) + ch(e, f, g) + K[t] + w[t]) & M32
        t2 = (big_sigma0(a) + maj(a, b, c)) & M32
        hh = g
        g = f
        f = e
        e = (d + t1) & M32
        d = c
        c = b
        b = a
        a = (t1 + t2) & M32

    return [(x + y) & M32 for x, y in zip(h, [a, b, c, d, e, f, g, hh])]


def sha256(message: bytes, trace=None):
    h = list(H_INIT)
    data = pad(message)
    for i in range(0, len(data), 64):
        h = compress(h, data[i:i + 64], trace=trace)
    return b"".join(x.to_bytes(4, "big") for x in h)


def hx(b):
    return b.hex()


# --------------------------------------------------------------------------
# Self-test and file generation
# --------------------------------------------------------------------------

# NIST / FIPS 180-4 published vectors
VECTORS = [
    (b"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    (b"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    (b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
     "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
    (b"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn"
     b"hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
     "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
    (b"a" * 1000000,
     "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"),
]


def main():
    print("=" * 78)
    print("SHA-256 GOLDEN MODEL  —  self-check against FIPS 180-4 vectors")
    print("=" * 78)

    ok_all = True

    # ---- primitive sanity ------------------------------------------------
    print("\n[1] Primitive spot checks")
    assert rotr(0x00000001, 1) == 0x80000000
    assert shr(0x80000000, 31) == 0x00000001
    assert ch(0xFFFFFFFF, 0xAAAAAAAA, 0x55555555) == 0xAAAAAAAA
    assert ch(0x00000000, 0xAAAAAAAA, 0x55555555) == 0x55555555
    assert maj(0xFFFFFFFF, 0xFFFFFFFF, 0x00000000) == 0xFFFFFFFF
    assert maj(0xFFFFFFFF, 0x00000000, 0x00000000) == 0x00000000
    print("      rotr / shr / Ch / Maj                            : PASS")

    # Sigma functions on a known input, cross-checked by definition
    x = 0x6a09e667
    print(f"      Sigma0(0x{x:08x}) = 0x{big_sigma0(x):08x}")
    print(f"      Sigma1(0x{x:08x}) = 0x{big_sigma1(x):08x}")
    print(f"      sigma0(0x{x:08x}) = 0x{small_sigma0(x):08x}")
    print(f"      sigma1(0x{x:08x}) = 0x{small_sigma1(x):08x}")

    # ---- NIST vectors -----------------------------------------------------
    print("\n[2] FIPS 180-4 / NIST test vectors")
    for msg, expect in VECTORS:
        got = hx(sha256(msg))
        ok = (got == expect)
        ok_all &= ok
        label = (repr(msg[:24]) + ("..." if len(msg) > 24 else "")).ljust(30)
        print(f"      {label} {'PASS' if ok else 'FAIL'}")
        if not ok:
            print(f"        got      {got}")
            print(f"        expected {expect}")

    # ---- number of blocks per vector -------------------------------------
    print("\n[3] Block counts after padding")
    for msg, _ in VECTORS[:4]:
        nblk = len(pad(msg)) // 64
        label = (repr(msg[:20]) + ("..." if len(msg) > 20 else "")).ljust(26)
        print(f"      {label} {len(msg):>7} bytes -> {nblk} block(s)")

    # ---- write K constants for $readmemh ----------------------------------
    with open("k_const.mem", "w") as fh:
        fh.write("// SHA-256 K constants, 64 x 32-bit, hex, one per line\n")
        fh.write("// FIPS 180-4 section 4.2.2\n")
        for k in K:
            fh.write(f"{k:08x}\n")

    # ---- write padded blocks for the testbench ----------------------------
    with open("blocks.txt", "w") as fh:
        fh.write("# One line per test case:\n")
        fh.write("#   <nblocks> <512-bit block hex> ... <expected 256-bit digest hex>\n")
        for msg, expect in VECTORS[:4]:
            data = pad(msg)
            n = len(data) // 64
            blocks = " ".join(data[i * 64:(i + 1) * 64].hex() for i in range(n))
            fh.write(f"{n} {blocks} {expect}\n")

    # ---- write the per-round trace for "abc" ------------------------------
    trace = []
    digest = sha256(b"abc", trace=trace)
    with open("abc_round_trace.txt", "w") as fh:
        fh.write("SHA-256 per-round trace for message \"abc\" (single block)\n")
        fh.write("t   W[t]      a        b        c        d        "
                 "e        f        g        h\n")
        for t, wt, v in trace:
            fh.write(f"{t:2d}  {wt:08x}  " + " ".join(f"{x:08x}" for x in v) + "\n")
        fh.write(f"\nDIGEST: {hx(digest)}\n")

    # ---- write the message schedule for "abc" -----------------------------
    blk = pad(b"abc")[:64]
    w = message_schedule(blk)
    with open("abc_schedule.txt", "w") as fh:
        fh.write("Message schedule W[0..63] for \"abc\"\n")
        for t in range(64):
            fh.write(f"W[{t:2d}] = {w[t]:08x}\n")

    print("\n[4] Files written")
    print("      k_const.mem          64 K constants for $readmemh")
    print("      blocks.txt           padded blocks + expected digests")
    print("      abc_round_trace.txt  a..h after every one of the 64 rounds")
    print("      abc_schedule.txt     W[0..63] for the \"abc\" block")

    print("\n" + "=" * 78)
    print("RESULT: " + ("ALL CHECKS PASSED" if ok_all else "FAILURES PRESENT"))
    print("=" * 78)
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(main())
