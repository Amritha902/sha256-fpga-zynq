//============================================================================
//  sha256_axis_wrapper_dual.v
//----------------------------------------------------------------------------
//  AXI4-Stream slave front end for the INTERLEAVED cores, Config C and D.
//
//  Those cores hash TWO independent messages simultaneously, so they take two
//  512-bit blocks per submission and produce two digests. This wrapper packs
//  the single 32-bit AXI-Stream into that shape.
//
//  WHY A SEPARATE MODULE RATHER THAN A PARAMETER ON THE ORIGINAL
//  ------------------------------------------------------------
//  sha256_axis_wrapper.v is verified and carries 18 passing system-level
//  checks for Configs A and B. Adding a mode parameter to it would put those
//  checks at risk for no benefit: the wrapper is not part of the controlled
//  core comparison, which is measured out of context by build_core_ooc.tcl.
//  Configs A and B keep their proven path untouched.
//
//  WIRE FORMAT — how two streams share one AXI-Stream port
//  -------------------------------------------------------
//  Blocks alternate, stream 0 first:
//
//      beats  0..15   stream 0, block i
//      beats 16..31   stream 1, block i
//      beats 32..47   stream 0, block i+1
//      beats 48..63   stream 1, block i+1      ... and so on
//
//  One DMA channel, one descriptor, no second stream port. The PS-side
//  software interleaves the two padded messages block by block before
//  handing the buffer to the DMA.
//
//  CONSTRAINT, AND IT IS A REAL ONE
//  --------------------------------
//  Both streams must have the SAME block count, because they advance in
//  lockstep through the core. BLOCK_CNT means "blocks per stream". Hashing
//  two messages of different lengths together requires padding the shorter
//  one out to the longer one's block count, which wastes the difference.
//  For the batch workloads that motivate interleaving at all — Merkle trees,
//  TLS records, SLH-DSA signing — messages are usually uniform, so this is
//  rarely binding. It must still be stated, not buried.
//
//  BYTE / WORD ORDER
//  -----------------
//  Unchanged from the single-stream wrapper: SHA-256 is big-endian, the
//  first beat of a block is W[0] and lands in bits [511:480], and the shift
//  register shifts LEFT. The PS byte-swaps each word before the DMA sees it.
//
//  FLOW
//  ----
//    IDLE       wait for ctrl_start
//    COLLECT_A  tready = 1, pack 16 beats into stream 0's block
//    COLLECT_B  tready = 1, pack 16 beats into stream 1's block
//    SUBMIT     tready = 0, pulse block_valid with BOTH blocks
//    BUSY       tready = 0 until the core reports both digests
//               -> COLLECT_A if more blocks remain, else DONE
//    DONE       assert digest_valid, stop the counter
//============================================================================
`timescale 1ns / 1ps

module sha256_axis_wrapper_dual (
    input  wire         clk,
    input  wire         rst_n,

    // ---- AXI4-Stream slave (from AXI DMA MM2S) -----------------------------
    input  wire [31:0]  s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire         s_axis_tlast,

    // ---- control / status ---------------------------------------------------
    input  wire         ctrl_start,        // one-cycle pulse
    input  wire         ctrl_init,         // 1 = new message pair
    input  wire         ctrl_soft_reset,   // one-cycle pulse
    input  wire [15:0]  block_count,       // blocks PER STREAM

    output wire         stat_busy,
    output reg          stat_digest_valid,
    output wire         stat_axis_active,
    output reg  [15:0]  blocks_done,       // per stream
    output reg  [31:0]  cycle_count,

    // ---- to / from the interleaved compression core --------------------------
    output reg          core_block_valid,
    output reg          core_init_0,
    output reg          core_init_1,
    output reg  [511:0] core_block_0,
    output reg  [511:0] core_block_1,
    input  wire         core_ready,
    input  wire         core_digest_valid
);

    localparam [2:0] S_IDLE      = 3'd0,
                     S_COLLECT_A = 3'd1,
                     S_COLLECT_B = 3'd2,
                     S_SUBMIT    = 3'd3,
                     S_BUSY      = 3'd4,
                     S_DONE      = 3'd5;

    reg [2:0]  state;
    reg [4:0]  beat_cnt;          // 0..15 within the current block
    reg [15:0] blocks_left;
    reg        first_block;

    assign s_axis_tready    = (state == S_COLLECT_A) || (state == S_COLLECT_B);
    assign stat_busy        = (state != S_IDLE) && (state != S_DONE);
    assign stat_axis_active = s_axis_tready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            beat_cnt          <= 5'd0;
            blocks_left       <= 16'd0;
            blocks_done       <= 16'd0;
            first_block       <= 1'b1;
            core_block_valid  <= 1'b0;
            core_init_0       <= 1'b0;
            core_init_1       <= 1'b0;
            core_block_0      <= 512'h0;
            core_block_1      <= 512'h0;
            stat_digest_valid <= 1'b0;
            cycle_count       <= 32'd0;
        end
        else if (ctrl_soft_reset) begin
            state             <= S_IDLE;
            beat_cnt          <= 5'd0;
            blocks_left       <= 16'd0;
            blocks_done       <= 16'd0;
            first_block       <= 1'b1;
            core_block_valid  <= 1'b0;
            stat_digest_valid <= 1'b0;
            cycle_count       <= 32'd0;
        end
        else begin
            core_block_valid <= 1'b0;              // default: single-cycle pulse

            if (state != S_IDLE && state != S_DONE)
                cycle_count <= cycle_count + 32'd1;

            case (state)

                //------------------------------------------------------------
                S_IDLE: begin
                    if (ctrl_start) begin
                        blocks_left       <= block_count;
                        blocks_done       <= 16'd0;
                        beat_cnt          <= 5'd0;
                        first_block       <= ctrl_init;
                        stat_digest_valid <= 1'b0;
                        cycle_count       <= 32'd0;
                        state             <= S_COLLECT_A;
                    end
                end

                //------------------------------------------------------------
                //  Stream 0's block: beats 0..15
                //------------------------------------------------------------
                S_COLLECT_A: begin
                    if (s_axis_tvalid) begin
                        core_block_0 <= {core_block_0[479:0], s_axis_tdata};
                        if (beat_cnt == 5'd15) begin
                            beat_cnt <= 5'd0;
                            state    <= S_COLLECT_B;
                        end
                        else begin
                            beat_cnt <= beat_cnt + 5'd1;
                        end
                    end
                end

                //------------------------------------------------------------
                //  Stream 1's block: beats 16..31
                //------------------------------------------------------------
                S_COLLECT_B: begin
                    if (s_axis_tvalid) begin
                        core_block_1 <= {core_block_1[479:0], s_axis_tdata};
                        if (beat_cnt == 5'd15) begin
                            beat_cnt <= 5'd0;
                            state    <= S_SUBMIT;
                        end
                        else begin
                            beat_cnt <= beat_cnt + 5'd1;
                        end
                    end
                end

                //------------------------------------------------------------
                S_SUBMIT: begin
                    if (core_ready) begin
                        core_block_valid <= 1'b1;
                        core_init_0      <= first_block;
                        core_init_1      <= first_block;
                        first_block      <= 1'b0;
                        state            <= S_BUSY;
                    end
                end

                //------------------------------------------------------------
                //  One digest_valid covers both streams -- they finish
                //  together by construction.
                //------------------------------------------------------------
                S_BUSY: begin
                    if (core_digest_valid) begin
                        blocks_done <= blocks_done + 16'd1;
                        if (blocks_left <= 16'd1) begin
                            blocks_left       <= 16'd0;
                            stat_digest_valid <= 1'b1;
                            state             <= S_DONE;
                        end
                        else begin
                            blocks_left <= blocks_left - 16'd1;
                            state       <= S_COLLECT_A;
                        end
                    end
                end

                //------------------------------------------------------------
                S_DONE: begin
                    if (ctrl_start) begin
                        blocks_left       <= block_count;
                        blocks_done       <= 16'd0;
                        beat_cnt          <= 5'd0;
                        first_block       <= ctrl_init;
                        stat_digest_valid <= 1'b0;
                        cycle_count       <= 32'd0;
                        state             <= S_COLLECT_A;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
