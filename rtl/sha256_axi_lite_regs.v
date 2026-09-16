//============================================================================
//  sha256_axi_lite_regs.v
//----------------------------------------------------------------------------
//  AXI4-Lite slave providing control, status, digest readback and a cycle
//  counter for the SHA-256 accelerator.
//
//  REGISTER MAP  (byte offsets from the base address)
//  ---------------------------------------------------------------------
//    0x00  CTRL       W  [0] start      write 1 to begin a message
//                        [1] init       1 = new message (load H(0))
//                                       0 = continue an existing one
//                        [2] soft_reset write 1 to clear the datapath
//    0x04  STATUS     R  [0] busy
//                        [1] digest_valid   set when the last block is done
//                        [2] core_ready
//                        [3] axis_active
//    0x08  BLOCK_CNT  W  number of 512-bit blocks in this message
//    0x0C  BLOCKS_DONE R how many blocks have been consumed so far
//    0x10  DIGEST_0   R  H0   (most significant word of the digest)
//    0x14  DIGEST_1   R  H1
//    0x18  DIGEST_2   R  H2
//    0x1C  DIGEST_3   R  H3
//    0x20  DIGEST_4   R  H4
//    0x24  DIGEST_5   R  H5
//    0x28  DIGEST_6   R  H6
//    0x2C  DIGEST_7   R  H7   (least significant word)
//    0x30  CYCLE_CNT  R  clock cycles from start to final digest_valid
//    0x34  VERSION    R  32'h5348_0001  ("SH" + version 1)
//
//  DUAL-STREAM EXTENSION -- Configs C and D only
//    0x38  DIGEST_B_0 R  stream 1's H0   (reads 0 on single-stream cores)
//    0x3C  DIGEST_B_1 R  stream 1's H1
//    0x40  DIGEST_B_2 R  stream 1's H2
//    0x44  DIGEST_B_3 R  stream 1's H3
//    0x48  DIGEST_B_4 R  stream 1's H4
//    0x4C  DIGEST_B_5 R  stream 1's H5
//    0x50  DIGEST_B_6 R  stream 1's H6
//    0x54  DIGEST_B_7 R  stream 1's H7
//    0x58  CAPS       R  [0] dual_stream  1 = two digests available,
//                                             BLOCK_CNT is per stream
//  ---------------------------------------------------------------------
//
//  The map is backward compatible.  On Configs A and B the CAPS bit reads 0
//  and DIGEST_B reads all zeros, so software written for the single-stream
//  build keeps working unchanged against a dual-stream bitstream and can
//  discover the extra capability at run time rather than being told.
//
//  The digest is read back over AXI4-Lite rather than returned through a
//  second DMA channel.  It is only 256 bits, so eight register reads are far
//  simpler than an S2MM DMA path — and it means the design needs only a
//  one-directional (MM2S) DMA, which is significantly easier to bring up.
//============================================================================
`timescale 1ns / 1ps

module sha256_axi_lite_regs #(
    parameter integer C_ADDR_WIDTH = 8
)(
    // ---- AXI4-Lite slave ---------------------------------------------------
    input  wire                      s_axi_aclk,
    input  wire                      s_axi_aresetn,

    input  wire [C_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]                s_axi_awprot,
    input  wire                      s_axi_awvalid,
    output reg                       s_axi_awready,

    input  wire [31:0]               s_axi_wdata,
    input  wire [3:0]                s_axi_wstrb,
    input  wire                      s_axi_wvalid,
    output reg                       s_axi_wready,

    output reg  [1:0]                s_axi_bresp,
    output reg                       s_axi_bvalid,
    input  wire                      s_axi_bready,

    input  wire [C_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]                s_axi_arprot,
    input  wire                      s_axi_arvalid,
    output reg                       s_axi_arready,

    output reg  [31:0]               s_axi_rdata,
    output reg  [1:0]                s_axi_rresp,
    output reg                       s_axi_rvalid,
    input  wire                      s_axi_rready,

    // ---- to / from the accelerator ------------------------------------------
    output reg                       ctrl_start,      // one-cycle pulse
    output reg                       ctrl_init,
    output reg                       ctrl_soft_reset, // one-cycle pulse
    output reg  [15:0]               block_count,

    input  wire                      stat_busy,
    input  wire                      stat_digest_valid,
    input  wire                      stat_core_ready,
    input  wire                      stat_axis_active,
    input  wire [15:0]               blocks_done,
    input  wire [255:0]              digest,
    input  wire [255:0]              digest_b,      // stream 1; 0 if unused
    input  wire                      dual_stream,   // 1 = Config C or D
    input  wire [31:0]               cycle_count
);

    localparam [31:0] VERSION_ID = 32'h5348_0001;

    // ---- write channel -------------------------------------------------------
    reg [C_ADDR_WIDTH-1:0] awaddr_q;
    reg                    aw_done, w_done;

    wire write_fire = aw_done & w_done;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            aw_done         <= 1'b0;
            w_done          <= 1'b0;
            awaddr_q        <= {C_ADDR_WIDTH{1'b0}};
            ctrl_start      <= 1'b0;
            ctrl_init       <= 1'b0;
            ctrl_soft_reset <= 1'b0;
            block_count     <= 16'd0;
        end
        else begin
            // start and soft_reset are single-cycle pulses
            ctrl_start      <= 1'b0;
            ctrl_soft_reset <= 1'b0;

            // address phase
            if (s_axi_awvalid && !aw_done) begin
                s_axi_awready <= 1'b1;
                awaddr_q      <= s_axi_awaddr;
                aw_done       <= 1'b1;
            end
            else begin
                s_axi_awready <= 1'b0;
            end

            // data phase
            if (s_axi_wvalid && !w_done) begin
                s_axi_wready <= 1'b1;
                w_done       <= 1'b1;
            end
            else begin
                s_axi_wready <= 1'b0;
            end

            // commit
            if (write_fire && !s_axi_bvalid) begin
                case (awaddr_q[7:2])
                    6'h00: begin                     // 0x00 CTRL
                        ctrl_start      <= s_axi_wdata[0];
                        ctrl_init       <= s_axi_wdata[1];
                        ctrl_soft_reset <= s_axi_wdata[2];
                    end
                    6'h02: block_count <= s_axi_wdata[15:0];   // 0x08
                    default: ;                       // read-only or reserved
                endcase
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;               // OKAY
                aw_done      <= 1'b0;
                w_done       <= 1'b0;
            end
            else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // ---- read channel --------------------------------------------------------
    reg [C_ADDR_WIDTH-1:0] araddr_q;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'h0;
            araddr_q      <= {C_ADDR_WIDTH{1'b0}};
        end
        else begin
            if (s_axi_arvalid && !s_axi_arready && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                araddr_q      <= s_axi_araddr;
            end
            else begin
                s_axi_arready <= 1'b0;
            end

            if (s_axi_arready && s_axi_arvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                case (s_axi_araddr[7:2])
                    6'h00: s_axi_rdata <= {29'd0, ctrl_soft_reset,
                                                  ctrl_init, 1'b0};
                    6'h01: s_axi_rdata <= {28'd0, stat_axis_active,
                                                  stat_core_ready,
                                                  stat_digest_valid,
                                                  stat_busy};
                    6'h02: s_axi_rdata <= {16'd0, block_count};
                    6'h03: s_axi_rdata <= {16'd0, blocks_done};
                    6'h04: s_axi_rdata <= digest[255:224];
                    6'h05: s_axi_rdata <= digest[223:192];
                    6'h06: s_axi_rdata <= digest[191:160];
                    6'h07: s_axi_rdata <= digest[159:128];
                    6'h08: s_axi_rdata <= digest[127: 96];
                    6'h09: s_axi_rdata <= digest[ 95: 64];
                    6'h0A: s_axi_rdata <= digest[ 63: 32];
                    6'h0B: s_axi_rdata <= digest[ 31:  0];
                    6'h0C: s_axi_rdata <= cycle_count;
                    6'h0D: s_axi_rdata <= VERSION_ID;
                    6'h0E: s_axi_rdata <= digest_b[255:224];
                    6'h0F: s_axi_rdata <= digest_b[223:192];
                    6'h10: s_axi_rdata <= digest_b[191:160];
                    6'h11: s_axi_rdata <= digest_b[159:128];
                    6'h12: s_axi_rdata <= digest_b[127: 96];
                    6'h13: s_axi_rdata <= digest_b[ 95: 64];
                    6'h14: s_axi_rdata <= digest_b[ 63: 32];
                    6'h15: s_axi_rdata <= digest_b[ 31:  0];
                    6'h16: s_axi_rdata <= {31'd0, dual_stream};
                    default: s_axi_rdata <= 32'hDEAD_BEEF;
                endcase
            end
            else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
