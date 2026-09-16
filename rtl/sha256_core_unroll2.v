//============================================================================
//  sha256_core_unroll2.v   —   CONFIGURATION B  (2x unrolled, 2 rounds / cycle)
//----------------------------------------------------------------------------
//  Two compression rounds chained combinationally per clock cycle.
//  34 cycles per 512-bit block: 1 load + 32 double-rounds + 1 hash update.
//
//    Cycles per block : 34   (vs 66 for Configuration A)
//    Area             : roughly 2x the round logic
//    Fmax             : EXPECTED TO FALL — this is the point of the experiment
//
//  WHY THIS IS THE INTERESTING CONFIGURATION
//  -----------------------------------------
//  In AES-ECB, blocks are INDEPENDENT, so unrolling can be pipelined:
//  registers between stages keep the combinational depth per stage constant
//  and Fmax is preserved.  Throughput scales linearly with area.
//
//  SHA-256 is different.  Round t+1 consumes the output of round t, so two
//  unrolled rounds CANNOT be separated by a register without losing the
//  cycle-count saving.  The critical path is therefore two five-input
//  32-bit adder chains in series, and Fmax must fall.
//
//  Net throughput = (cycles saved) x (frequency lost).
//
//  The prediction is that these roughly cancel and 2x unrolling is close to
//  break-even on this device.  MEASURING THAT is the project's contribution.
//  If the measurement shows a net loss, that is a valid and reportable
//  finding, not a failure — it quantifies exactly why hash functions
//  parallelise badly within a single message.
//
//  MESSAGE SCHEDULE — advancing two words per cycle
//  ------------------------------------------------
//      w_new1 = sigma1(w[14]) + w[9]  + sigma0(w[1]) + w[0]    ( = W[t+16] )
//      w_new2 = sigma1(w[15]) + w[10] + sigma0(w[2]) + w[1]    ( = W[t+17] )
//
//  Both depend only on the CURRENT window contents, so the two schedule
//  adders run in parallel.  Unlike the compression rounds, the message
//  schedule unrolls for free — a useful contrast to point out.
//============================================================================
`timescale 1ns / 1ps

module sha256_core_unroll2 (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         block_valid,
    input  wire         init,
    input  wire [511:0] block_in,
    output wire         ready,

    output reg          digest_valid,
    output wire [255:0] digest
);

    localparam [31:0] H0_INIT = 32'h6a09e667;
    localparam [31:0] H1_INIT = 32'hbb67ae85;
    localparam [31:0] H2_INIT = 32'h3c6ef372;
    localparam [31:0] H3_INIT = 32'ha54ff53a;
    localparam [31:0] H4_INIT = 32'h510e527f;
    localparam [31:0] H5_INIT = 32'h9b05688c;
    localparam [31:0] H6_INIT = 32'h1f83d9ab;
    localparam [31:0] H7_INIT = 32'h5be0cd19;

    localparam [1:0] S_IDLE  = 2'd0,
                     S_ROUND = 2'd1,
                     S_FINAL = 2'd2;

    reg [1:0] state;
    reg [6:0] t;                        // even round index: 0,2,4,...,62

    reg [31:0] h0, h1, h2, h3, h4, h5, h6, h7;
    reg [31:0] a, b, c, d, e, f, g, hh;
    reg [31:0] w [0:15];

    // ---- message schedule : two new words per cycle -------------------------
    wire [31:0] ss0_1, ss1_1, ss0_2, ss1_2;
    sha256_small_sigma0 u_ss0_1 (.x(w[1]),  .out(ss0_1));
    sha256_small_sigma1 u_ss1_1 (.x(w[14]), .out(ss1_1));
    sha256_small_sigma0 u_ss0_2 (.x(w[2]),  .out(ss0_2));
    sha256_small_sigma1 u_ss1_2 (.x(w[15]), .out(ss1_2));

    wire [31:0] w_new1 = ss1_1 + w[9]  + ss0_1 + w[0];
    wire [31:0] w_new2 = ss1_2 + w[10] + ss0_2 + w[1];

    // ---- two round constants ------------------------------------------------
    wire [31:0] kt0, kt1;
    sha256_k_rom u_krom0 (.addr(t[5:0]),          .k(kt0));
    sha256_k_rom u_krom1 (.addr(t[5:0] | 6'd1),   .k(kt1));

    // ---- two rounds chained combinationally ---------------------------------
    wire [31:0] m_a, m_b, m_c, m_d, m_e, m_f, m_g, m_h;   // mid-round
    wire [31:0] n_a, n_b, n_c, n_d, n_e, n_f, n_g, n_h;   // after both

    sha256_round_comb u_round0 (
        .a_in(a), .b_in(b), .c_in(c), .d_in(d),
        .e_in(e), .f_in(f), .g_in(g), .h_in(hh),
        .kt(kt0), .wt(w[0]),
        .a_out(m_a), .b_out(m_b), .c_out(m_c), .d_out(m_d),
        .e_out(m_e), .f_out(m_f), .g_out(m_g), .h_out(m_h)
    );

    sha256_round_comb u_round1 (
        .a_in(m_a), .b_in(m_b), .c_in(m_c), .d_in(m_d),
        .e_in(m_e), .f_in(m_f), .g_in(m_g), .h_in(m_h),
        .kt(kt1), .wt(w[1]),
        .a_out(n_a), .b_out(n_b), .c_out(n_c), .d_out(n_d),
        .e_out(n_e), .f_out(n_f), .g_out(n_g), .h_out(n_h)
    );

    assign ready  = (state == S_IDLE);
    assign digest = {h0, h1, h2, h3, h4, h5, h6, h7};

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            t            <= 7'd0;
            digest_valid <= 1'b0;
            {h0,h1,h2,h3,h4,h5,h6,h7} <= {H0_INIT,H1_INIT,H2_INIT,H3_INIT,
                                          H4_INIT,H5_INIT,H6_INIT,H7_INIT};
            {a,b,c,d,e,f,g,hh} <= 256'h0;
            for (i = 0; i < 16; i = i + 1) w[i] <= 32'h0;
        end
        else begin
            digest_valid <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (block_valid) begin
                        for (i = 0; i < 16; i = i + 1)
                            w[i] <= block_in[32*(15-i) +: 32];

                        if (init) begin
                            a <= H0_INIT;  b <= H1_INIT;  c <= H2_INIT;  d  <= H3_INIT;
                            e <= H4_INIT;  f <= H5_INIT;  g <= H6_INIT;  hh <= H7_INIT;
                            h0 <= H0_INIT; h1 <= H1_INIT; h2 <= H2_INIT; h3 <= H3_INIT;
                            h4 <= H4_INIT; h5 <= H5_INIT; h6 <= H6_INIT; h7 <= H7_INIT;
                        end
                        else begin
                            a <= h0; b <= h1; c <= h2; d  <= h3;
                            e <= h4; f <= h5; g <= h6; hh <= h7;
                        end

                        t     <= 7'd0;
                        state <= S_ROUND;
                    end
                end

                S_ROUND: begin
                    a <= n_a; b <= n_b; c <= n_c; d  <= n_d;
                    e <= n_e; f <= n_f; g <= n_g; hh <= n_h;

                    // shift the window down by TWO
                    for (i = 0; i < 14; i = i + 1)
                        w[i] <= w[i+2];
                    w[14] <= w_new1;
                    w[15] <= w_new2;

                    if (t == 7'd62)
                        state <= S_FINAL;
                    else
                        t <= t + 7'd2;
                end

                S_FINAL: begin
                    h0 <= h0 + a;   h1 <= h1 + b;   h2 <= h2 + c;   h3 <= h3 + d;
                    h4 <= h4 + e;   h5 <= h5 + f;   h6 <= h6 + g;   h7 <= h7 + hh;
                    digest_valid <= 1'b1;
                    state        <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
