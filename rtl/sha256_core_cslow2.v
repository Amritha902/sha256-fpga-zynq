//============================================================================
//  sha256_core_cslow2.v   —   CONFIGURATION C  (2-message C-slow interleaved)
//----------------------------------------------------------------------------
//  Two INDEPENDENT messages hashed simultaneously through two instances of
//  the identical round module separated by a PIPELINE REGISTER.
//
//    Cycles per 512-bit block : 33 effective  (66 cycles, TWO blocks retired)
//    Combinational depth      : ONE round     (same as Configuration A)
//    DSP48                    : 0
//
//  WHY THIS CONFIGURATION CANNOT LOSE
//  ----------------------------------
//  Configuration B chains two rounds COMBINATIONALLY.  Its critical path is
//  two five-input adder chains in series, so its Fmax must fall, and whether
//  the cycle saving outweighs that loss is an open question.
//
//  Configuration C chains the same two rounds THROUGH A REGISTER.  Round
//  t+1 of message 0 and round t of message 1 have NO data dependency, so
//  the register is legal.  The longest combinational path is therefore ONE
//  round instance — identical to Configuration A — while two messages
//  advance one round each per cycle.
//
//      Config A :  reg -> round -> reg                    66 cyc / 1 block
//      Config B :  reg -> round -> round -> reg           34 cyc / 1 block
//      Config C :  reg -> round -> reg -> round -> reg    66 cyc / 2 blocks
//
//  So C retires a block every 33 cycles at A's combinational depth.  The
//  cycle saving is structural and the frequency is not traded away.  Unlike
//  B, C does not depend on a measurement going a particular way.
//
//  WHAT IT COSTS, STATED HONESTLY
//  ------------------------------
//  Two working-variable banks, two chaining-value sets and two message
//  schedule windows.  Area is higher than B.  Throughput-per-LUT is
//  therefore the only fair three-way metric, and the report must use it.
//
//  WHAT IT DOES NOT DO
//  -------------------
//  C-slow helps only for INDEPENDENT messages.  Single-message latency is
//  unchanged at 66 cycles — in fact a lone message wastes one of the two
//  slots.  This must be stated, not buried.  The deployment case that makes
//  it worthwhile is batch hashing: TLS termination, Merkle trees, and
//  FIPS 205 SLH-DSA signing, which is thousands of independent SHA-256
//  evaluations per signature.
//
//  CONTROLLED-COMPARISON CONSTRAINT
//  --------------------------------
//  This core instantiates sha256_round_comb TWICE, exactly as Configuration
//  B does.  A, B and C therefore differ ONLY in how many round instances
//  there are and whether a register sits between them.  Forking or
//  specialising the round module for any configuration voids the entire
//  three-way experiment.
//
//  PING-PONG SCHEDULING
//  --------------------
//  Bank P and bank Q each hold one complete message context: working
//  variables a..h plus that context's 16-word schedule window.
//
//      round instance 0 :  reads P, result lands in Q next cycle
//      round instance 1 :  reads Q, result lands in P next cycle
//
//  So the two contexts swap banks every cycle, each advancing exactly one
//  round per cycle.  After 64 rounds — an even number — context 0 is back
//  in bank P and context 1 in bank Q, so the final accumulation needs no
//  phase tracking.
//
//  Both instances execute round index t in the same cycle, so a SINGLE K
//  ROM feeds both.  Configuration B needs two ROMs because it consumes
//  K[t] and K[t+1] in one cycle; C consumes K[t] twice.  A small but real
//  area advantage, worth one line in the results discussion.
//============================================================================
`timescale 1ns / 1ps

module sha256_core_cslow2 (
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
    reg [6:0] t;                        // round counter 0..63, shared

    // ---- chaining values, one set per message stream -----------------------
    reg [31:0] m0_h0, m0_h1, m0_h2, m0_h3, m0_h4, m0_h5, m0_h6, m0_h7;
    reg [31:0] m1_h0, m1_h1, m1_h2, m1_h3, m1_h4, m1_h5, m1_h6, m1_h7;

    // ---- bank P : working variables + schedule window ----------------------
    reg [31:0] pa, pb, pc, pd, pe, pf, pg, ph;
    reg [31:0] pw [0:15];

    // ---- bank Q : working variables + schedule window ----------------------
    reg [31:0] qa, qb, qc, qd, qe, qf, qg, qh;
    reg [31:0] qw [0:15];

    //------------------------------------------------------------------------
    //  Message schedule, one adder set per bank.
    //
    //      w_new = sigma1(w[14]) + w[9] + sigma0(w[1]) + w[0]
    //
    //  A four-input add, strictly shorter than the round's five-input T1
    //  chain followed by a' = T1 + T2, so the schedule is never the
    //  critical path.
    //------------------------------------------------------------------------
    wire [31:0] p_ss0, p_ss1, q_ss0, q_ss1;

    sha256_small_sigma0 u_p_ss0 (.x(pw[1]),  .out(p_ss0));
    sha256_small_sigma1 u_p_ss1 (.x(pw[14]), .out(p_ss1));
    sha256_small_sigma0 u_q_ss0 (.x(qw[1]),  .out(q_ss0));
    sha256_small_sigma1 u_q_ss1 (.x(qw[14]), .out(q_ss1));

    wire [31:0] p_w_new = p_ss1 + pw[9] + p_ss0 + pw[0];
    wire [31:0] q_w_new = q_ss1 + qw[9] + q_ss0 + qw[0];

    // ---- one round constant, consumed by both instances --------------------
    wire [31:0] kt;
    sha256_k_rom u_krom (.addr(t[5:0]), .k(kt));

    //------------------------------------------------------------------------
    //  Two instances of the IDENTICAL round module.
    //  Instance 0 : bank P -> bank Q.   Instance 1 : bank Q -> bank P.
    //  The register between them is what keeps the combinational depth at
    //  one round and makes this configuration a guaranteed win over A.
    //------------------------------------------------------------------------
    wire [31:0] p2q_a, p2q_b, p2q_c, p2q_d, p2q_e, p2q_f, p2q_g, p2q_h;
    wire [31:0] q2p_a, q2p_b, q2p_c, q2p_d, q2p_e, q2p_f, q2p_g, q2p_h;

    sha256_round_comb u_round0 (
        .a_in(pa), .b_in(pb), .c_in(pc), .d_in(pd),
        .e_in(pe), .f_in(pf), .g_in(pg), .h_in(ph),
        .kt(kt), .wt(pw[0]),
        .a_out(p2q_a), .b_out(p2q_b), .c_out(p2q_c), .d_out(p2q_d),
        .e_out(p2q_e), .f_out(p2q_f), .g_out(p2q_g), .h_out(p2q_h)
    );

    sha256_round_comb u_round1 (
        .a_in(qa), .b_in(qb), .c_in(qc), .d_in(qd),
        .e_in(qe), .f_in(qf), .g_in(qg), .h_in(qh),
        .kt(kt), .wt(qw[0]),
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
                //  Load both streams.  Message 0 starts in bank P, message 1
                //  in bank Q.
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
                //  64 cycles.  Each cycle both contexts advance one round and
                //  swap banks.  The whole point: the longest combinational
                //  path here is ONE sha256_round_comb.
                //--------------------------------------------------------------
                S_ROUND: begin
                    // P -> Q  (context that was in P moves to Q, one round on)
                    qa <= p2q_a; qb <= p2q_b; qc <= p2q_c; qd <= p2q_d;
                    qe <= p2q_e; qf <= p2q_f; qg <= p2q_g; qh <= p2q_h;

                    // Q -> P
                    pa <= q2p_a; pb <= q2p_b; pc <= q2p_c; pd <= q2p_d;
                    pe <= q2p_e; pf <= q2p_f; pg <= q2p_g; ph <= q2p_h;

                    // each context's schedule window follows it across banks
                    for (i = 0; i < 15; i = i + 1) begin
                        qw[i] <= pw[i+1];
                        pw[i] <= qw[i+1];
                    end
                    qw[15] <= p_w_new;
                    pw[15] <= q_w_new;

                    if (t == 7'd63)
                        state <= S_FINAL;
                    else
                        t <= t + 7'd1;
                end

                //--------------------------------------------------------------
                //  64 is even, so context 0 has returned to bank P and
                //  context 1 to bank Q.  No phase tracking needed.
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
