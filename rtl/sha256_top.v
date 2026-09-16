//============================================================================
//  sha256_top.v
//----------------------------------------------------------------------------
//  Top-level SHA-256 accelerator IP for Vivado IP Integrator.
//
//    AXI4-Lite slave   control, status, digest readback, cycle counter
//    AXI4-Stream slave 32-bit message stream from the AXI DMA MM2S channel
//
//  The CORE_SELECT parameter picks which compression core is instantiated,
//  and with it the matching stream front end:
//
//      CORE_SELECT = 0   Config A  U=1 C=1  iterative        66 cyc/block
//      CORE_SELECT = 1   Config B  U=2 C=1  2x unrolled      34 cyc/block
//      CORE_SELECT = 2   Config C  U=1 C=2  interleaved      33 cyc/block eff.
//      CORE_SELECT = 3   Config D  U=2 C=2  both levers      17 cyc/block eff.
//
//  All four present the same AXI interface, so the Vivado builds differ by
//  ONE parameter.
//
//  SINGLE VS DUAL STREAM
//  ---------------------
//  Configs A and B hash one message and expose one digest, and keep the
//  original verified stream wrapper untouched.
//
//  Configs C and D hash TWO independent messages simultaneously. They use
//  sha256_axis_wrapper_dual, which packs alternating 16-beat blocks from the
//  one AXI-Stream port into the core's two block inputs, and they expose a
//  second digest at 0x38..0x54 with the CAPS bit at 0x58 set.
//
//  Software can therefore discover the mode at run time: read CAPS, and if
//  bit 0 is set, interleave two messages and read back two digests. Software
//  written for A and B runs unchanged against a C or D bitstream, hashing
//  one message and simply ignoring the second slot.
//
//  THE HONEST CAVEAT
//  -----------------
//  Interleaving only helps when there are two INDEPENDENT messages to hash.
//  Single-message latency is unchanged -- 66 cycles for C, 34 for D, no
//  better than A and B respectively -- and a lone message wastes one of the
//  two slots. BLOCK_CNT is per stream, and both streams must have the same
//  block count because they advance through the core in lockstep.
//============================================================================
`timescale 1ns / 1ps

module sha256_top #(
    parameter integer CORE_SELECT       = 0,
    parameter integer C_S_AXI_ADDR_WIDTH = 8
)(
    // ---- common clock and reset (from the Zynq PS) --------------------------
    input  wire                             s_axi_aclk,
    input  wire                             s_axi_aresetn,

    // ---- AXI4-Lite slave ----------------------------------------------------
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [2:0]                       s_axi_awprot,
    input  wire                             s_axi_awvalid,
    output wire                             s_axi_awready,
    input  wire [31:0]                      s_axi_wdata,
    input  wire [3:0]                       s_axi_wstrb,
    input  wire                             s_axi_wvalid,
    output wire                             s_axi_wready,
    output wire [1:0]                       s_axi_bresp,
    output wire                             s_axi_bvalid,
    input  wire                             s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [2:0]                       s_axi_arprot,
    input  wire                             s_axi_arvalid,
    output wire                             s_axi_arready,
    output wire [31:0]                      s_axi_rdata,
    output wire [1:0]                       s_axi_rresp,
    output wire                             s_axi_rvalid,
    input  wire                             s_axi_rready,

    // ---- AXI4-Stream slave (from AXI DMA MM2S) ------------------------------
    input  wire [31:0]                      s_axis_tdata,
    input  wire [3:0]                       s_axis_tkeep,
    input  wire                             s_axis_tvalid,
    output wire                             s_axis_tready,
    input  wire                             s_axis_tlast,

    // ---- optional interrupt to the PS ---------------------------------------
    output wire                             irq
);

    localparam DUAL = (CORE_SELECT >= 2);

    // ---- register block <-> stream wrapper ---------------------------------
    wire         ctrl_start, ctrl_init, ctrl_soft_reset;
    wire [15:0]  block_count;
    wire         stat_busy, stat_digest_valid, stat_axis_active;
    wire [15:0]  blocks_done;
    wire [31:0]  cycle_count;

    // ---- stream wrapper <-> core -------------------------------------------
    wire         core_ready, core_digest_valid;
    wire [255:0] core_digest_0, core_digest_1;

    assign irq = stat_digest_valid;

    //-------------------------------------------------------------------------
    sha256_axi_lite_regs #(
        .C_ADDR_WIDTH (C_S_AXI_ADDR_WIDTH)
    ) u_regs (
        .s_axi_aclk        (s_axi_aclk),
        .s_axi_aresetn     (s_axi_aresetn),
        .s_axi_awaddr      (s_axi_awaddr),
        .s_axi_awprot      (s_axi_awprot),
        .s_axi_awvalid     (s_axi_awvalid),
        .s_axi_awready     (s_axi_awready),
        .s_axi_wdata       (s_axi_wdata),
        .s_axi_wstrb       (s_axi_wstrb),
        .s_axi_wvalid      (s_axi_wvalid),
        .s_axi_wready      (s_axi_wready),
        .s_axi_bresp       (s_axi_bresp),
        .s_axi_bvalid      (s_axi_bvalid),
        .s_axi_bready      (s_axi_bready),
        .s_axi_araddr      (s_axi_araddr),
        .s_axi_arprot      (s_axi_arprot),
        .s_axi_arvalid     (s_axi_arvalid),
        .s_axi_arready     (s_axi_arready),
        .s_axi_rdata       (s_axi_rdata),
        .s_axi_rresp       (s_axi_rresp),
        .s_axi_rvalid      (s_axi_rvalid),
        .s_axi_rready      (s_axi_rready),

        .ctrl_start        (ctrl_start),
        .ctrl_init         (ctrl_init),
        .ctrl_soft_reset   (ctrl_soft_reset),
        .block_count       (block_count),
        .stat_busy         (stat_busy),
        .stat_digest_valid (stat_digest_valid),
        .stat_core_ready   (core_ready),
        .stat_axis_active  (stat_axis_active),
        .blocks_done       (blocks_done),
        .digest            (core_digest_0),
        .digest_b          (core_digest_1),
        .dual_stream       (DUAL[0]),
        .cycle_count       (cycle_count)
    );

    //-------------------------------------------------------------------------
    //  Stream front end and compression core, selected together at
    //  elaboration time.
    //-------------------------------------------------------------------------
    generate
        //---------------------------------------------------------------------
        //  SINGLE-STREAM PATH -- Configs A and B
        //---------------------------------------------------------------------
        if (CORE_SELECT < 2) begin : g_single

            wire         w_block_valid, w_init;
            wire [511:0] w_block;

            sha256_axis_wrapper u_axis (
                .clk               (s_axi_aclk),
                .rst_n             (s_axi_aresetn),
                .s_axis_tdata      (s_axis_tdata),
                .s_axis_tvalid     (s_axis_tvalid),
                .s_axis_tready     (s_axis_tready),
                .s_axis_tlast      (s_axis_tlast),
                .ctrl_start        (ctrl_start),
                .ctrl_init         (ctrl_init),
                .ctrl_soft_reset   (ctrl_soft_reset),
                .block_count       (block_count),
                .stat_busy         (stat_busy),
                .stat_digest_valid (stat_digest_valid),
                .stat_axis_active  (stat_axis_active),
                .blocks_done       (blocks_done),
                .cycle_count       (cycle_count),
                .core_block_valid  (w_block_valid),
                .core_init         (w_init),
                .core_block        (w_block),
                .core_ready        (core_ready),
                .core_digest_valid (core_digest_valid)
            );

            // stream 1's digest does not exist here; reads back as zero
            assign core_digest_1 = 256'h0;

            if (CORE_SELECT == 0) begin : g_config_a
                sha256_core_iter u_core (
                    .clk          (s_axi_aclk),
                    .rst_n        (s_axi_aresetn),
                    .block_valid  (w_block_valid),
                    .init         (w_init),
                    .block_in     (w_block),
                    .ready        (core_ready),
                    .digest_valid (core_digest_valid),
                    .digest       (core_digest_0)
                );
            end
            else begin : g_config_b
                sha256_core_unroll2 u_core (
                    .clk          (s_axi_aclk),
                    .rst_n        (s_axi_aresetn),
                    .block_valid  (w_block_valid),
                    .init         (w_init),
                    .block_in     (w_block),
                    .ready        (core_ready),
                    .digest_valid (core_digest_valid),
                    .digest       (core_digest_0)
                );
            end

        end
        //---------------------------------------------------------------------
        //  DUAL-STREAM PATH -- Configs C and D
        //---------------------------------------------------------------------
        else begin : g_dual

            wire         w_block_valid, w_init_0, w_init_1;
            wire [511:0] w_block_0, w_block_1;

            sha256_axis_wrapper_dual u_axis (
                .clk               (s_axi_aclk),
                .rst_n             (s_axi_aresetn),
                .s_axis_tdata      (s_axis_tdata),
                .s_axis_tvalid     (s_axis_tvalid),
                .s_axis_tready     (s_axis_tready),
                .s_axis_tlast      (s_axis_tlast),
                .ctrl_start        (ctrl_start),
                .ctrl_init         (ctrl_init),
                .ctrl_soft_reset   (ctrl_soft_reset),
                .block_count       (block_count),
                .stat_busy         (stat_busy),
                .stat_digest_valid (stat_digest_valid),
                .stat_axis_active  (stat_axis_active),
                .blocks_done       (blocks_done),
                .cycle_count       (cycle_count),
                .core_block_valid  (w_block_valid),
                .core_init_0       (w_init_0),
                .core_init_1       (w_init_1),
                .core_block_0      (w_block_0),
                .core_block_1      (w_block_1),
                .core_ready        (core_ready),
                .core_digest_valid (core_digest_valid)
            );

            if (CORE_SELECT == 2) begin : g_config_c
                sha256_core_cslow2 u_core (
                    .clk          (s_axi_aclk),
                    .rst_n        (s_axi_aresetn),
                    .block_valid  (w_block_valid),
                    .init_0       (w_init_0),
                    .init_1       (w_init_1),
                    .block_in_0   (w_block_0),
                    .block_in_1   (w_block_1),
                    .ready        (core_ready),
                    .digest_valid (core_digest_valid),
                    .digest_0     (core_digest_0),
                    .digest_1     (core_digest_1)
                );
            end
            else begin : g_config_d
                sha256_core_u2c2 u_core (
                    .clk          (s_axi_aclk),
                    .rst_n        (s_axi_aresetn),
                    .block_valid  (w_block_valid),
                    .init_0       (w_init_0),
                    .init_1       (w_init_1),
                    .block_in_0   (w_block_0),
                    .block_in_1   (w_block_1),
                    .ready        (core_ready),
                    .digest_valid (core_digest_valid),
                    .digest_0     (core_digest_0),
                    .digest_1     (core_digest_1)
                );
            end

        end
    endgenerate

endmodule
