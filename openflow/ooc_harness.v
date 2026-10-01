//=============================================================================
//  ooc_harness.v  —  pin-limited harness for the open-source 2x2 run
//
//  The cores have 512- or 1024-bit block inputs and 256- or 512-bit digests,
//  more than the XC7Z020's user I/O. Vivado's out-of-context mode leaves
//  those ports unplaced; nextpnr cannot, so this harness puts registers on
//  both sides of the core:
//
//      din[31:0] --> 1024-bit shift register --> core --> digest regs
//                                                  |
//      dout[31:0] <-- registered 32-bit word mux <-+
//
//  Every core input comes from a flip-flop and every digest bit reaches an
//  output, so nothing is optimised away and every timing path the core owns
//  is register to register. The harness is identical for all four configs
//  (only CFG changes), so it cannot bias the comparison. Its own paths are
//  one shift register and one 16:1 word mux, far shorter than a round.
//=============================================================================
module ooc_harness #(
    parameter CFG = 0                 // 0 = A, 1 = B, 2 = C, 3 = D, 4 = B'
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] din,
    input  wire        shift,         // shift din into the block register
    input  wire        go,            // block_valid to the core
    input  wire        init_0,
    input  wire        init_1,
    input  wire [3:0]  sel,           // which digest word to read out
    output reg  [31:0] dout,
    output reg         ready_q,
    output reg         dvalid_q
);
    reg [1023:0] blk;
    reg          go_q, i0_q, i1_q;
    reg  [3:0]   sel_q;
    always @(posedge clk) begin
        if (shift) blk <= {blk[991:0], din};
        go_q  <= go;
        i0_q  <= init_0;
        i1_q  <= init_1;
        sel_q <= sel;
    end

    wire         ready, dvalid;
    wire [511:0] dig;                 // {digest_1, digest_0}; upper half 0 for A/B

    generate
        if (CFG == 0) begin : g_a
            sha256_core_iter u (.clk(clk), .rst_n(rst_n), .block_valid(go_q), .init(i0_q),
                .block_in(blk[511:0]), .ready(ready), .digest_valid(dvalid), .digest(dig[255:0]));
            assign dig[511:256] = 256'd0;
        end else if (CFG == 1) begin : g_b
            sha256_core_unroll2 u (.clk(clk), .rst_n(rst_n), .block_valid(go_q), .init(i0_q),
                .block_in(blk[511:0]), .ready(ready), .digest_valid(dvalid), .digest(dig[255:0]));
            assign dig[511:256] = 256'd0;
        end else if (CFG == 2) begin : g_c
            sha256_core_cslow2 u (.clk(clk), .rst_n(rst_n), .block_valid(go_q),
                .init_0(i0_q), .init_1(i1_q), .block_in_0(blk[511:0]), .block_in_1(blk[1023:512]),
                .ready(ready), .digest_valid(dvalid), .digest_0(dig[255:0]), .digest_1(dig[511:256]));
        end else if (CFG == 4) begin : g_bs
            sha256_core_unroll2_sched u (.clk(clk), .rst_n(rst_n), .block_valid(go_q), .init(i0_q),
                .block_in(blk[511:0]), .ready(ready), .digest_valid(dvalid), .digest(dig[255:0]));
            assign dig[511:256] = 256'd0;
        end else begin : g_d
            sha256_core_u2c2 u (.clk(clk), .rst_n(rst_n), .block_valid(go_q),
                .init_0(i0_q), .init_1(i1_q), .block_in_0(blk[511:0]), .block_in_1(blk[1023:512]),
                .ready(ready), .digest_valid(dvalid), .digest_0(dig[255:0]), .digest_1(dig[511:256]));
        end
    endgenerate

    always @(posedge clk) begin
        dout     <= dig[sel_q*32 +: 32];
        ready_q  <= ready;
        dvalid_q <= dvalid;
    end
endmodule
