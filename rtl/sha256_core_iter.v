//============================================================================
//  sha256_core_iter.v   —   CONFIGURATION A  (iterative, 1 round / cycle)
//----------------------------------------------------------------------------
//  One compression round per clock cycle.  66 cycles per 512-bit block:
//  1 load + 64 rounds + 1 hash update.
//
//    Cycles per block : 66
//    Throughput       : 512 bits / 66 cycles = ~776 Mbps @ 100 MHz
//    DSP48            : 0
//
//  MESSAGE SCHEDULE — the rolling 16-word window
//  ---------------------------------------------
//  The full schedule is 64 words, but W[t] only ever depends on
//  W[t-2], W[t-7], W[t-15] and W[t-16].  A 16-deep shift register is
//  therefore sufficient; storing all 64 words would waste 1536 bits for
//  no benefit.
//
//  Register w[0..15] holds W[t .. t+15]:
//      round t consumes w[0]
//      w_new = sigma1(w[14]) + w[9] + sigma0(w[1]) + w[0]      ( = W[t+16] )
//      then shift down by one and load w_new into w[15]
//
//  USAGE
//  -----
//  Assert init=1 with the FIRST block of a message (loads H(0)); assert
//  init=0 for subsequent blocks so the chaining value carries forward.
//  Padding is performed by the PS-side software, not here — see the
//  scope note in the project synopsis.
//============================================================================
`timescale 1ns / 1ps

module sha256_core_iter (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         block_valid,   // one-cycle pulse with block_in
    input  wire         init,          // 1 = first block of a new message
    input  wire [511:0] block_in,      // big-endian: word 0 is bits [511:480]
    output wire         ready,         // core is idle and can accept a block

    output reg          digest_valid,  // pulses when digest is updated
    output wire [255:0] digest
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

    // ---- FSM ---------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                     S_ROUND = 2'd1,
                     S_FINAL = 2'd2;

    reg [1:0] state;
    reg [6:0] t;                        // round counter 0..63

    // ---- chaining value ----------------------------------------------------
    reg [31:0] h0, h1, h2, h3, h4, h5, h6, h7;

    // ---- working variables -------------------------------------------------
    reg [31:0] a, b, c, d, e, f, g, hh;

    // ---- message schedule window -------------------------------------------
    reg [31:0] w [0:15];

    wire [31:0] sig0_out, sig1_out;
    sha256_small_sigma0 u_ss0 (.x(w[1]),  .out(sig0_out));
    sha256_small_sigma1 u_ss1 (.x(w[14]), .out(sig1_out));

    wire [31:0] w_new = sig1_out + w[9] + sig0_out + w[0];

    // ---- round constant ----------------------------------------------------
    wire [31:0] kt;
    sha256_k_rom u_krom (.addr(t[5:0]), .k(kt));

    // ---- the single combinational round ------------------------------------
    wire [31:0] na, nb, nc, nd, ne, nf, ng, nh;
    sha256_round_comb u_round (
        .a_in(a), .b_in(b), .c_in(c), .d_in(d),
        .e_in(e), .f_in(f), .g_in(g), .h_in(hh),
        .kt(kt), .wt(w[0]),
        .a_out(na), .b_out(nb), .c_out(nc), .d_out(nd),
        .e_out(ne), .f_out(nf), .g_out(ng), .h_out(nh)
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

                //--------------------------------------------------------------
                S_IDLE: begin
                    if (block_valid) begin
                        // load the 16 message words, big-endian
                        for (i = 0; i < 16; i = i + 1)
                            w[i] <= block_in[32*(15-i) +: 32];

                        // working variables start from the chaining value
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

                //--------------------------------------------------------------
                S_ROUND: begin
                    // advance the working variables
                    a <= na; b <= nb; c <= nc; d  <= nd;
                    e <= ne; f <= nf; g <= ng; hh <= nh;

                    // advance the message-schedule window
                    for (i = 0; i < 15; i = i + 1)
                        w[i] <= w[i+1];
                    w[15] <= w_new;

                    if (t == 7'd63)
                        state <= S_FINAL;
                    else
                        t <= t + 7'd1;
                end

                //--------------------------------------------------------------
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
