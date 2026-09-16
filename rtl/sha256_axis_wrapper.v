//============================================================================
//  sha256_axis_wrapper.v
//----------------------------------------------------------------------------
//  AXI4-Stream slave front end for the SHA-256 core.
//
//  The AXI DMA delivers the padded message as a stream of 32-bit beats.
//  This module packs sixteen consecutive beats into one 512-bit block and
//  hands it to the compression core, then back-pressures the stream while
//  the core is busy (66 cycles for Config A, 34 for Config B).
//
//  BYTE / WORD ORDER — the classic hash bug lives here
//  ---------------------------------------------------
//  SHA-256 treats the message as BIG-ENDIAN 32-bit words.  The first beat
//  of a block is W[0] and must land in the MOST significant position of the
//  512-bit block vector.  The shift register below shifts LEFT on each beat,
//  so after sixteen beats beat 0 has been shifted up to bits [511:480].
//
//  The PS-side software is responsible for byte-swapping each word into
//  big-endian order before handing the buffer to the DMA.  See
//  sha256_hw_swap32() in the Vitis application.
//
//  FLOW
//  ----
//    IDLE      wait for ctrl_start from the AXI-Lite register block
//    COLLECT   tready = 1, accept beats, pack them
//    SUBMIT    tready = 0, pulse block_valid at the core
//    BUSY      tready = 0 until the core reports ready again
//              -> COLLECT if more blocks remain, else DONE
//    DONE      assert digest_valid to the status register, stop the counter
//============================================================================
`timescale 1ns / 1ps

module sha256_axis_wrapper (
    input  wire         clk,
    input  wire         rst_n,

    // ---- AXI4-Stream slave (from AXI DMA MM2S) -----------------------------
    input  wire [31:0]  s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire         s_axis_tlast,

    // ---- control / status ---------------------------------------------------
    input  wire         ctrl_start,        // one-cycle pulse
    input  wire         ctrl_init,         // 1 = new message
    input  wire         ctrl_soft_reset,   // one-cycle pulse
    input  wire [15:0]  block_count,

    output wire         stat_busy,
    output reg          stat_digest_valid,
    output wire         stat_axis_active,
    output reg  [15:0]  blocks_done,
    output reg  [31:0]  cycle_count,

    // ---- to / from the compression core --------------------------------------
    output reg          core_block_valid,
    output reg          core_init,
    output reg  [511:0] core_block,
    input  wire         core_ready,
    input  wire         core_digest_valid
);

    localparam [2:0] S_IDLE    = 3'd0,
                     S_COLLECT = 3'd1,
                     S_SUBMIT  = 3'd2,
                     S_BUSY    = 3'd3,
                     S_DONE    = 3'd4;

    reg [2:0]  state;
    reg [4:0]  beat_cnt;          // 0..15
    reg [15:0] blocks_left;
    reg        first_block;

    assign s_axis_tready    = (state == S_COLLECT);
    assign stat_busy        = (state != S_IDLE) && (state != S_DONE);
    assign stat_axis_active = (state == S_COLLECT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            beat_cnt          <= 5'd0;
            blocks_left       <= 16'd0;
            blocks_done       <= 16'd0;
            first_block       <= 1'b1;
            core_block_valid  <= 1'b0;
            core_init         <= 1'b0;
            core_block        <= 512'h0;
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

            // free-running cycle counter while a message is in flight
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
                        state             <= S_COLLECT;
                    end
                end

                //------------------------------------------------------------
                S_COLLECT: begin
                    if (s_axis_tvalid) begin
                        // shift left: beat 0 ends up in bits [511:480]
                        core_block <= {core_block[479:0], s_axis_tdata};
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
                        core_init        <= first_block;
                        first_block      <= 1'b0;
                        state            <= S_BUSY;
                    end
                end

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
                            state       <= S_COLLECT;
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
                        state             <= S_COLLECT;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
