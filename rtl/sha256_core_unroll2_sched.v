//============================================================================
//  sha256_core_unroll2_sched.v  —  CONFIGURATION B' (2x unrolled, operands
//                                   scheduled inside the pair)
//----------------------------------------------------------------------------
//  Identical to sha256_core_unroll2.v (Config B) in every respect but one:
//  the second round's T1 is summed in arrival order.
//
//  In round t+1 of the pair, three of T1's five operands do not depend on
//  round t at all:
//      h(t+1) = g(t)        a register output, available at the clock edge
//      K[t+1]               a constant from the K ROM
//      W[t+1]               the schedule window, also a register
//  So  hkw = g + K[t+1] + W[t+1]  is computed IN PARALLEL with round t, and
//  round t+1 only adds the two late operands, Sigma1(e) and Ch(e,f,g), to it.
//  The late path drops from five adds to two plus the T1 + T2 / d + T1 add.
//
//  This is Chaves et al.'s operation rescheduling (CHES 2006) applied inside
//  the unrolled pair. The technique is theirs; this file exists to MEASURE
//  what it does to the unrolling verdict, B vs B' on the same device, same
//  flow, same constraint. ngspice predicts Fmax(B)/Fmax(A) of 0.500 naive
//  and 0.680 scheduled (BASE_PAPER_COMPARISON.md).
//
//  (* keep *) on hkw stops synthesis re-merging it into one five-operand
//  adder, which would undo the schedule.
//============================================================================
`timescale 1ns / 1ps

module sha256_core_unroll2_sched (
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

    // round t+1's early operands, summed while round t is still evaluating
    (* keep *) wire [31:0] hkw1 = g + kt1 + w[1];      // h(t+1) = g(t)

    sha256_round_comb_hkw u_round1 (
        .a_in(m_a), .b_in(m_b), .c_in(m_c), .d_in(m_d),
        .e_in(m_e), .f_in(m_f), .g_in(m_g),
        .hkw(hkw1),
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
