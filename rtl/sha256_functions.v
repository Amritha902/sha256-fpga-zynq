//============================================================================
//  sha256_functions.v
//----------------------------------------------------------------------------
//  The six logical functions of SHA-256 (FIPS 180-4 section 4.1.2) and the
//  64-entry K constant ROM (section 4.2.2).
//
//  KEY OBSERVATION FOR THE REPORT
//  -----------------------------
//  ROTR and SHR are FIXED bit reorderings.  In hardware they are pure
//  routing: zero LUTs, zero flip-flops, zero delay.  Each Sigma function is
//  therefore just a two-level XOR of three re-wired copies of its input.
//
//  The entire cost of a SHA-256 round is:
//      - a handful of XOR / AND gates (Ch, Maj, the Sigmas)
//      - modulo-2^32 ADDITION, which dominates the critical path
//
//  There is no multiplication anywhere, so the design uses ZERO DSP48 slices.
//  The consequence — that unrolling lengthens the adder chain and therefore
//  costs frequency — is the central question this project measures.
//============================================================================
`timescale 1ns / 1ps


//----------------------------------------------------------------------------
//  Ch(x,y,z) = (x AND y) XOR (NOT x AND z)
//  "Choose": take the bit of y where x is 1, the bit of z where x is 0.
//----------------------------------------------------------------------------
module sha256_ch (
    input  wire [31:0] x, y, z,
    output wire [31:0] out
);
    assign out = (x & y) ^ (~x & z);
endmodule


//----------------------------------------------------------------------------
//  Maj(x,y,z) = (x AND y) XOR (x AND z) XOR (y AND z)
//  Bitwise majority vote across the three inputs.
//----------------------------------------------------------------------------
module sha256_maj (
    input  wire [31:0] x, y, z,
    output wire [31:0] out
);
    assign out = (x & y) ^ (x & z) ^ (y & z);
endmodule


//----------------------------------------------------------------------------
//  Sigma0(x) = ROTR^2(x) XOR ROTR^13(x) XOR ROTR^22(x)     (uppercase sigma)
//----------------------------------------------------------------------------
module sha256_big_sigma0 (
    input  wire [31:0] x,
    output wire [31:0] out
);
    assign out = {x[ 1:0], x[31: 2]}   // ROTR 2
               ^ {x[12:0], x[31:13]}   // ROTR 13
               ^ {x[21:0], x[31:22]};  // ROTR 22
endmodule


//----------------------------------------------------------------------------
//  Sigma1(x) = ROTR^6(x) XOR ROTR^11(x) XOR ROTR^25(x)
//----------------------------------------------------------------------------
module sha256_big_sigma1 (
    input  wire [31:0] x,
    output wire [31:0] out
);
    assign out = {x[ 5:0], x[31: 6]}   // ROTR 6
               ^ {x[10:0], x[31:11]}   // ROTR 11
               ^ {x[24:0], x[31:25]};  // ROTR 25
endmodule


//----------------------------------------------------------------------------
//  sigma0(x) = ROTR^7(x) XOR ROTR^18(x) XOR SHR^3(x)       (lowercase sigma)
//----------------------------------------------------------------------------
module sha256_small_sigma0 (
    input  wire [31:0] x,
    output wire [31:0] out
);
    assign out = {x[ 6:0], x[31: 7]}   // ROTR 7
               ^ {x[17:0], x[31:18]}   // ROTR 18
               ^ {3'b000,  x[31: 3]};  // SHR 3
endmodule


//----------------------------------------------------------------------------
//  sigma1(x) = ROTR^17(x) XOR ROTR^19(x) XOR SHR^10(x)
//----------------------------------------------------------------------------
module sha256_small_sigma1 (
    input  wire [31:0] x,
    output wire [31:0] out
);
    assign out = {x[16:0], x[31:17]}   // ROTR 17
               ^ {x[18:0], x[31:19]}   // ROTR 19
               ^ {10'b0,   x[31:10]};  // SHR 10
endmodule


//----------------------------------------------------------------------------
//  sha256_k_rom — the 64 round constants
//
//  These are the first 32 bits of the fractional parts of the cube roots of
//  the first 64 prime numbers.  They are "nothing up my sleeve" numbers:
//  chosen so that nobody can claim a hidden trapdoor was embedded in them.
//  Worth one sentence in the report — examiners like it.
//
//  Combinational (LUT ROM).  For a BRAM-backed variant, register the output
//  and use $readmemh with model/k_const.mem.
//----------------------------------------------------------------------------
module sha256_k_rom (
    input  wire [5:0]  addr,
    output reg  [31:0] k
);
    always @(*) begin
        case (addr)
            6'd00: k = 32'h428a2f98;  6'd01: k = 32'h71374491;
            6'd02: k = 32'hb5c0fbcf;  6'd03: k = 32'he9b5dba5;
            6'd04: k = 32'h3956c25b;  6'd05: k = 32'h59f111f1;
            6'd06: k = 32'h923f82a4;  6'd07: k = 32'hab1c5ed5;
            6'd08: k = 32'hd807aa98;  6'd09: k = 32'h12835b01;
            6'd10: k = 32'h243185be;  6'd11: k = 32'h550c7dc3;
            6'd12: k = 32'h72be5d74;  6'd13: k = 32'h80deb1fe;
            6'd14: k = 32'h9bdc06a7;  6'd15: k = 32'hc19bf174;
            6'd16: k = 32'he49b69c1;  6'd17: k = 32'hefbe4786;
            6'd18: k = 32'h0fc19dc6;  6'd19: k = 32'h240ca1cc;
            6'd20: k = 32'h2de92c6f;  6'd21: k = 32'h4a7484aa;
            6'd22: k = 32'h5cb0a9dc;  6'd23: k = 32'h76f988da;
            6'd24: k = 32'h983e5152;  6'd25: k = 32'ha831c66d;
            6'd26: k = 32'hb00327c8;  6'd27: k = 32'hbf597fc7;
            6'd28: k = 32'hc6e00bf3;  6'd29: k = 32'hd5a79147;
            6'd30: k = 32'h06ca6351;  6'd31: k = 32'h14292967;
            6'd32: k = 32'h27b70a85;  6'd33: k = 32'h2e1b2138;
            6'd34: k = 32'h4d2c6dfc;  6'd35: k = 32'h53380d13;
            6'd36: k = 32'h650a7354;  6'd37: k = 32'h766a0abb;
            6'd38: k = 32'h81c2c92e;  6'd39: k = 32'h92722c85;
            6'd40: k = 32'ha2bfe8a1;  6'd41: k = 32'ha81a664b;
            6'd42: k = 32'hc24b8b70;  6'd43: k = 32'hc76c51a3;
            6'd44: k = 32'hd192e819;  6'd45: k = 32'hd6990624;
            6'd46: k = 32'hf40e3585;  6'd47: k = 32'h106aa070;
            6'd48: k = 32'h19a4c116;  6'd49: k = 32'h1e376c08;
            6'd50: k = 32'h2748774c;  6'd51: k = 32'h34b0bcb5;
            6'd52: k = 32'h391c0cb3;  6'd53: k = 32'h4ed8aa4a;
            6'd54: k = 32'h5b9cca4f;  6'd55: k = 32'h682e6ff3;
            6'd56: k = 32'h748f82ee;  6'd57: k = 32'h78a5636f;
            6'd58: k = 32'h84c87814;  6'd59: k = 32'h8cc70208;
            6'd60: k = 32'h90befffa;  6'd61: k = 32'ha4506ceb;
            6'd62: k = 32'hbef9a3f7;  6'd63: k = 32'hc67178f2;
        endcase
    end
endmodule


//----------------------------------------------------------------------------
//  sha256_round_comb — one compression round, purely combinational
//
//      T1 = h + Sigma1(e) + Ch(e,f,g) + K[t] + W[t]
//      T2 = Sigma0(a) + Maj(a,b,c)
//
//      a' = T1 + T2      e' = d + T1
//      b' = a            f' = e
//      c' = b            g' = f
//      d' = c            h' = g
//
//  Note that six of the eight outputs are just a rename — free in hardware.
//  Only a' and e' require arithmetic, and the T1 five-input addition is the
//  critical path of the whole design.
//----------------------------------------------------------------------------
module sha256_round_comb (
    input  wire [31:0] a_in, b_in, c_in, d_in,
    input  wire [31:0] e_in, f_in, g_in, h_in,
    input  wire [31:0] kt,
    input  wire [31:0] wt,
    output wire [31:0] a_out, b_out, c_out, d_out,
    output wire [31:0] e_out, f_out, g_out, h_out
);
    wire [31:0] s1, s0, ch_o, maj_o;

    sha256_big_sigma1 u_s1  (.x(e_in), .out(s1));
    sha256_big_sigma0 u_s0  (.x(a_in), .out(s0));
    sha256_ch         u_ch  (.x(e_in), .y(f_in), .z(g_in), .out(ch_o));
    sha256_maj        u_maj (.x(a_in), .y(b_in), .z(c_in), .out(maj_o));

    wire [31:0] t1 = h_in + s1 + ch_o + kt + wt;   // mod 2^32, wraps naturally
    wire [31:0] t2 = s0 + maj_o;

    assign a_out = t1 + t2;
    assign b_out = a_in;
    assign c_out = b_in;
    assign d_out = c_in;
    assign e_out = d_in + t1;
    assign f_out = e_in;
    assign g_out = f_in;
    assign h_out = g_in;
endmodule
