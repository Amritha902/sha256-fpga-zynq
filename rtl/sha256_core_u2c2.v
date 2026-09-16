//============================================================================
//  sha256_core_u2c2.v   —   CONFIGURATION D  (2x unrolled AND 2-message C-slow)
//----------------------------------------------------------------------------
//  The fourth corner of the design space.  Unroll depth U=2 combined with
//  interleave depth C=2.
//
//    Cycles per 512-bit block : 17 effective  (34 cycles, TWO blocks retired)
//    Combinational depth      : TWO rounds    (identical to Configuration B)
//    Round instances          : 4
//    DSP48                    : 0
//
//  WHY THIS CORE EXISTS
//  --------------------
//  Unroll depth and interleave depth are two INDEPENDENT axes, and the
//  literature has never measured them independently on one device from one
//  round module:
//
//                  U = 1                        U = 2
//      C = 1   A : 66 cyc, depth 1      B : 34 cyc, depth 2
//      C = 2   C : 33 cyc, depth 1      D : 17 cyc, depth 2   <-- this file
//
//  Read the table by column and the claim falls out.  Moving DOWN a column
//  halves the effective cycle count while leaving combinational depth
//  untouched.  Moving ACROSS a row halves it too, but doubles the depth and
//  therefore costs frequency by an amount only measurement can settle.
//
//      Unrolling  : a gamble on the device.  May pay, may not.  The 2022
//                   literature and the structural theory disagree on which.
//      Interleaving: a guaranteed linear area-for-throughput trade, and it
//                   holds AT ANY UNROLL DEPTH.
//
//  So D should run at Configuration B's frequency — same critical path, two
//  five-input adder chains in series — while retiring blocks twice as fast.
//  D/B throughput is therefore expected to be almost exactly 2.00x whatever
//  B's Fmax turns out to be.  If B wins its threshold, D wins by twice as
//  much; if B loses, D still doubles it.  The orthogonality claim is what
//  this core tests.
//
//  COST
//  ----
//  Four round instances plus two full context banks.  The largest area of
//  the four configurations by some margin.  Throughput-per-LUT is the only
//  honest metric across the grid and the report must lead with it.
//
//  CAVEAT, SAME AS CONFIG C
//  ------------------------
//  Interleaving helps only for INDEPENDENT messages.  Single-message
//  latency is 34 cycles, no better than Configuration B, and a lone message
//  wastes one of the two slots.
//
//  CONTROLLED-COMPARISON CONSTRAINT
//  --------------------------------
//  Four instantiations of the IDENTICAL sha256_round_comb.  A, B, C and D
//  differ only in how many instances there are and where the registers sit.
//  Forking the round module for any configuration voids the whole grid.
//
//  PING-PONG SCHEDULING
//  --------------------
//  As Configuration C, but each stage advances its context by TWO rounds
//  instead of one:
//
//      bank P -> round0 -> round1 -> bank Q     (rounds t, t+1)
//      bank Q -> round2 -> round3 -> bank P     (rounds t, t+1)
//
//  Both contexts sit at the same round index t, so stage 1 and stage 2
//  consume the same pair of round constants and two K ROMs serve all four
//  round instances.  32 cycles of two rounds each covers all 64; 32 is even,
//  so context 0 ends back in bank P and no phase tracking is needed.
//============================================================================
`timescale 1ns / 1ps

module sha256_core_u2c2 (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         block_valid,   // one-cycle pulse; loads BOTH streams
    input  wire         init_0,        // 1 = first block of message 0
    input  wire         init_1,        // 1 = first block of message 1
    input  wire [511:0] block_in_0,    // big-endian: word 0 is bits [511:480]
    input  wire [511:0] block_in_1,
    output wire         ready,

    output reg          digest_valid,  // pulses when BOTH digests are updated
    output wire [255:0] digest_0,
    output wire [255:0] digest_1
);

    // ---- initial hash values H(0), FIPS 180-4 section 5.3.3 ---------------
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

    // ---- chaining values, one set per message stream -----------------------
    reg [31:0] m0_h0, m0_h1, m0_h2, m0_h3, m0_h4, m0_h5, m0_h6, m0_h7;
    reg [31:0] m1_h0, m1_h1, m1_h2, m1_h3, m1_h4, m1_h5, m1_h6, m1_h7;

    // ---- the two context banks ---------------------------------------------
    reg [31:0] pa, pb, pc, pd, pe, pf, pg, ph;
    reg [31:0] pw [0:15];
    reg [31:0] qa, qb, qc, qd, qe, qf, qg, qh;
    reg [31:0] qw [0:15];

    //------------------------------------------------------------------------
    //  Message schedule, two new words per cycle per bank.
    //
    //      w_new1 = sigma1(w[14]) + w[9]  + sigma0(w[1]) + w[0]
    //      w_new2 = sigma1(w[15]) + w[10] + sigma0(w[2]) + w[1]
    //
    //  Both depend only on the CURRENT window, so the two adders run in
    //  parallel.  The schedule unrolls for free; only the compression rounds
    //  stack.  That asymmetry is the reason the grid has the shape it does.
    //------------------------------------------------------------------------
    wire [31:0] p_ss0_1, p_ss1_1, p_ss0_2, p_ss1_2;
    wire [31:0] q_ss0_1, q_ss1_1, q_ss0_2, q_ss1_2;

    sha256_small_sigma0 u_p_ss0_1 (.x(pw[1]),  .out(p_ss0_1));
    sha256_small_sigma1 u_p_ss1_1 (.x(pw[14]), .out(p_ss1_1));
    sha256_small_sigma0 u_p_ss0_2 (.x(pw[2]),  .out(p_ss0_2));
    sha256_small_sigma1 u_p_ss1_2 (.x(pw[15]), .out(p_ss1_2));

    sha256_small_sigma0 u_q_ss0_1 (.x(qw[1]),  .out(q_ss0_1));
    sha256_small_sigma1 u_q_ss1_1 (.x(qw[14]), .out(q_ss1_1));
    sha256_small_sigma0 u_q_ss0_2 (.x(qw[2]),  .out(q_ss0_2));
    sha256_small_sigma1 u_q_ss1_2 (.x(qw[15]), .out(q_ss1_2));

    wire [31:0] p_w_new1 = p_ss1_1 + pw[9]  + p_ss0_1 + pw[0];
    wire [31:0] p_w_new2 = p_ss1_2 + pw[10] + p_ss0_2 + pw[1];
    wire [31:0] q_w_new1 = q_ss1_1 + qw[9]  + q_ss0_1 + qw[0];
    wire [31:0] q_w_new2 = q_ss1_2 + qw[10] + q_ss0_2 + qw[1];

    //------------------------------------------------------------------------
    //  Two round constants, shared by both stages.  The contexts are in
    //  lockstep at round index t, so stage 1 and stage 2 want the same pair.
    //  Configuration B also needs two ROMs; D needs no more than B does.
    //------------------------------------------------------------------------
    wire [31:0] kt0, kt1;
    sha256_k_rom u_krom0 (.addr(t[5:0]),        .k(kt0));
    sha256_k_rom u_krom1 (.addr(t[5:0] | 6'd1), .k(kt1));

    //------------------------------------------------------------------------
    //  Stage 1 : bank P -> two chained rounds -> bank Q
    //------------------------------------------------------------------------
    wire [31:0] pm_a, pm_b, pm_c, pm_d, pm_e, pm_f, pm_g, pm_h;
    wire [31:0] p2q_a, p2q_b, p2q_c, p2q_d, p2q_e, p2q_f, p2q_g, p2q_h;

    sha256_round_comb u_round0 (
        .a_in(pa), .b_in(pb), .c_in(pc), .d_in(pd),
        .e_in(pe), .f_in(pf), .g_in(pg), .h_in(ph),
        .kt(kt0), .wt(pw[0]),
        .a_out(pm_a), .b_out(pm_b), .c_out(pm_c), .d_out(pm_d),
        .e_out(pm_e), .f_out(pm_f), .g_out(pm_g), .h_out(pm_h)
    );

    sha256_round_comb u_round1 (
        .a_in(pm_a), .b_in(pm_b), .c_in(pm_c), .d_in(pm_d),
        .e_in(pm_e), .f_in(pm_f), .g_in(pm_g), .h_in(pm_h),
        .kt(kt1), .wt(pw[1]),
        .a_out(p2q_a), .b_out(p2q_b), .c_out(p2q_c), .d_out(p2q_d),
        .e_out(p2q_e), .f_out(p2q_f), .g_out(p2q_g), .h_out(p2q_h)
    );

    //------------------------------------------------------------------------
    //  Stage 2 : bank Q -> two chained rounds -> bank P
    //------------------------------------------------------------------------
    wire [31:0] qm_a, qm_b, qm_c, qm_d, qm_e, qm_f, qm_g, qm_h;
    wire [31:0] q2p_a, q2p_b, q2p_c, q2p_d, q2p_e, q2p_f, q2p_g, q2p_h;

    sha256_round_comb u_round2 (
        .a_in(qa), .b_in(qb), .c_in(qc), .d_in(qd),
        .e_in(qe), .f_in(qf), .g_in(qg), .h_in(qh),
        .kt(kt0), .wt(qw[0]),
        .a_out(qm_a), .b_out(qm_b), .c_out(qm_c), .d_out(qm_d),
        .e_out(qm_e), .f_out(qm_f), .g_out(qm_g), .h_out(qm_h)
    );

    sha256_round_comb u_round3 (
        .a_in(qm_a), .b_in(qm_b), .c_in(qm_c), .d_in(qm_d),
        .e_in(qm_e), .f_in(qm_f), .g_in(qm_g), .h_in(qm_h),
        .kt(kt1), .wt(qw[1]),
        .a_out(q2p_a), .b_out(q2p_b), .c_out(q2p_c), .d_out(q2p_d),
        .e_out(q2p_e), .f_out(q2p_f), .g_out(q2p_g), .h_out(q2p_h)
    );

    assign ready    = (state == S_IDLE);
    assign digest_0 = {m0_h0, m0_h1, m0_h2, m0_h3, m0_h4, m0_h5, m0_h6, m0_h7};
    assign digest_1 = {m1_h0, m1_h1, m1_h2, m1_h3, m1_h4, m1_h5, m1_h6, m1_h7};

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            t            <= 7'd0;
            digest_valid <= 1'b0;

            {m0_h0,m0_h1,m0_h2,m0_h3,m0_h4,m0_h5,m0_h6,m0_h7} <=
                {H0_INIT,H1_INIT,H2_INIT,H3_INIT,H4_INIT,H5_INIT,H6_INIT,H7_INIT};
            {m1_h0,m1_h1,m1_h2,m1_h3,m1_h4,m1_h5,m1_h6,m1_h7} <=
                {H0_INIT,H1_INIT,H2_INIT,H3_INIT,H4_INIT,H5_INIT,H6_INIT,H7_INIT};

            {pa,pb,pc,pd,pe,pf,pg,ph} <= 256'h0;
            {qa,qb,qc,qd,qe,qf,qg,qh} <= 256'h0;
            for (i = 0; i < 16; i = i + 1) begin
                pw[i] <= 32'h0;
                qw[i] <= 32'h0;
            end
        end
        else begin
            digest_valid <= 1'b0;

            case (state)

                //--------------------------------------------------------------
                S_IDLE: begin
                    if (block_valid) begin
                        for (i = 0; i < 16; i = i + 1) begin
                            pw[i] <= block_in_0[32*(15-i) +: 32];
                            qw[i] <= block_in_1[32*(15-i) +: 32];
                        end

                        // stream 0 -> bank P
                        if (init_0) begin
                            pa <= H0_INIT; pb <= H1_INIT; pc <= H2_INIT; pd <= H3_INIT;
                            pe <= H4_INIT; pf <= H5_INIT; pg <= H6_INIT; ph <= H7_INIT;
                            m0_h0 <= H0_INIT; m0_h1 <= H1_INIT;
                            m0_h2 <= H2_INIT; m0_h3 <= H3_INIT;
                            m0_h4 <= H4_INIT; m0_h5 <= H5_INIT;
                            m0_h6 <= H6_INIT; m0_h7 <= H7_INIT;
                        end
                        else begin
                            pa <= m0_h0; pb <= m0_h1; pc <= m0_h2; pd <= m0_h3;
                            pe <= m0_h4; pf <= m0_h5; pg <= m0_h6; ph <= m0_h7;
                        end

                        // stream 1 -> bank Q
                        if (init_1) begin
                            qa <= H0_INIT; qb <= H1_INIT; qc <= H2_INIT; qd <= H3_INIT;
                            qe <= H4_INIT; qf <= H5_INIT; qg <= H6_INIT; qh <= H7_INIT;
                            m1_h0 <= H0_INIT; m1_h1 <= H1_INIT;
                            m1_h2 <= H2_INIT; m1_h3 <= H3_INIT;
                            m1_h4 <= H4_INIT; m1_h5 <= H5_INIT;
                            m1_h6 <= H6_INIT; m1_h7 <= H7_INIT;
                        end
                        else begin
                            qa <= m1_h0; qb <= m1_h1; qc <= m1_h2; qd <= m1_h3;
                            qe <= m1_h4; qf <= m1_h5; qg <= m1_h6; qh <= m1_h7;
                        end

                        t     <= 7'd0;
                        state <= S_ROUND;
                    end
                end

                //--------------------------------------------------------------
                //  32 cycles.  Each cycle both contexts advance TWO rounds and
                //  swap banks.  Combinational depth is two rounds in series —
                //  the same critical path as Configuration B.
                //--------------------------------------------------------------
                S_ROUND: begin
                    qa <= p2q_a; qb <= p2q_b; qc <= p2q_c; qd <= p2q_d;
                    qe <= p2q_e; qf <= p2q_f; qg <= p2q_g; qh <= p2q_h;

                    pa <= q2p_a; pb <= q2p_b; pc <= q2p_c; pd <= q2p_d;
                    pe <= q2p_e; pf <= q2p_f; pg <= q2p_g; ph <= q2p_h;

                    // each context's window follows it across banks, shifted by two
                    for (i = 0; i < 14; i = i + 1) begin
                        qw[i] <= pw[i+2];
                        pw[i] <= qw[i+2];
                    end
                    qw[14] <= p_w_new1;
                    qw[15] <= p_w_new2;
                    pw[14] <= q_w_new1;
                    pw[15] <= q_w_new2;

                    if (t == 7'd62)
                        state <= S_FINAL;
                    else
                        t <= t + 7'd2;
                end

                //--------------------------------------------------------------
                //  32 swaps is even, so context 0 is back in bank P.
                //--------------------------------------------------------------
                S_FINAL: begin
                    m0_h0 <= m0_h0 + pa;  m0_h1 <= m0_h1 + pb;
                    m0_h2 <= m0_h2 + pc;  m0_h3 <= m0_h3 + pd;
                    m0_h4 <= m0_h4 + pe;  m0_h5 <= m0_h5 + pf;
                    m0_h6 <= m0_h6 + pg;  m0_h7 <= m0_h7 + ph;

                    m1_h0 <= m1_h0 + qa;  m1_h1 <= m1_h1 + qb;
                    m1_h2 <= m1_h2 + qc;  m1_h3 <= m1_h3 + qd;
                    m1_h4 <= m1_h4 + qe;  m1_h5 <= m1_h5 + qf;
                    m1_h6 <= m1_h6 + qg;  m1_h7 <= m1_h7 + qh;

                    digest_valid <= 1'b1;
                    state        <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
