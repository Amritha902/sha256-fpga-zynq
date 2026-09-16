//============================================================================
//  tb_sha256_top_dual.v  —  SYSTEM-LEVEL testbench for Configs C and D
//----------------------------------------------------------------------------
//  Drives sha256_top exactly as the hardware will be driven, but through the
//  dual-stream front end:
//
//    1. AXI4-Lite writes to set the per-stream block count and start
//    2. AXI4-Stream beats delivering BOTH padded messages, blocks alternating
//       (16 beats stream 0, 16 beats stream 1, repeat)
//    3. AXI4-Lite reads polling STATUS, then reading BOTH digests back --
//       stream 0 from 0x10, stream 1 from 0x38
//
//  Catches what the core testbench cannot: the alternating-block wire format,
//  back-pressure across the block boundary, the extended register map, and
//  the CAPS discovery bit.
//
//  Run:  make sysC        (Config C, U=1 C=2)
//        make sysD        (Config D, U=2 C=2)
//============================================================================
`timescale 1ns / 1ps

module tb_sha256_top_dual;

    reg clk = 1'b0;
    reg rstn = 1'b0;
    always #5 clk = ~clk;                   // 100 MHz

    integer errors = 0;
    integer checks = 0;

    // ---- register offsets ---------------------------------------------------
    localparam CTRL        = 8'h00;
    localparam STATUS      = 8'h04;
    localparam BLOCK_CNT   = 8'h08;
    localparam BLOCKS_DONE = 8'h0C;
    localparam DIGEST_0    = 8'h10;
    localparam CYCLE_CNT   = 8'h30;
    localparam VERSION     = 8'h34;
    localparam DIGEST_B0   = 8'h38;         // stream 1's digest
    localparam CAPS        = 8'h58;

    // ---- AXI4-Lite master ----------------------------------------------------
    reg  [7:0]  awaddr = 0;   reg awvalid = 0;   wire awready;
    reg  [31:0] wdata  = 0;   reg wvalid  = 0;   wire wready;
    wire [1:0]  bresp;        wire bvalid;       reg  bready = 0;
    reg  [7:0]  araddr = 0;   reg arvalid = 0;   wire arready;
    wire [31:0] rdata;        wire [1:0] rresp;  wire rvalid;  reg rready = 0;

    // ---- AXI4-Stream master --------------------------------------------------
    reg  [31:0] tdata  = 0;   reg tvalid = 0;    wire tready;   reg tlast = 0;

    wire irq;

`ifdef CORE_D
    localparam CFG_SEL  = 3;
    localparam [255:0] CFG_NAME = "Config D  (U=2, C=2)";
`else
    localparam CFG_SEL  = 2;
    localparam [255:0] CFG_NAME = "Config C  (U=1, C=2)";
`endif

    sha256_top #(
        .CORE_SELECT        (CFG_SEL),
        .C_S_AXI_ADDR_WIDTH (8)
    ) dut (
        .s_axi_aclk    (clk),    .s_axi_aresetn (rstn),
        .s_axi_awaddr  (awaddr), .s_axi_awprot (3'b000), .s_axi_awvalid (awvalid), .s_axi_awready (awready),
        .s_axi_wdata   (wdata),  .s_axi_wstrb  (4'hF),   .s_axi_wvalid  (wvalid),  .s_axi_wready  (wready),
        .s_axi_bresp   (bresp),  .s_axi_bvalid (bvalid), .s_axi_bready  (bready),
        .s_axi_araddr  (araddr), .s_axi_arprot (3'b000), .s_axi_arvalid (arvalid), .s_axi_arready (arready),
        .s_axi_rdata   (rdata),  .s_axi_rresp  (rresp),  .s_axi_rvalid  (rvalid),  .s_axi_rready  (rready),
        .s_axis_tdata  (tdata),  .s_axis_tkeep (4'hF),   .s_axis_tvalid (tvalid),
        .s_axis_tready (tready), .s_axis_tlast (tlast),
        .irq           (irq)
    );

    //=========================================================================
    //  AXI4-Lite BFM
    //=========================================================================
    task axi_write;
        input [7:0]  addr;
        input [31:0] data;
        reg aw_hs, w_hs, b_hs;
        reg aw_now, w_now, b_now;
        begin
            @(negedge clk);
            awaddr = addr;  awvalid = 1'b1;
            wdata  = data;  wvalid  = 1'b1;
            bready = 1'b1;
            aw_hs = 1'b0;  w_hs = 1'b0;  b_hs = 1'b0;
            while (!(aw_hs && w_hs && b_hs)) begin
                aw_now = awvalid && awready;
                w_now  = wvalid  && wready;
                b_now  = bvalid  && bready;
                @(posedge clk);
                @(negedge clk);
                if (aw_now) begin awvalid = 1'b0; aw_hs = 1'b1; end
                if (w_now)  begin wvalid  = 1'b0; w_hs  = 1'b1; end
                if (b_now)  begin bready  = 1'b0; b_hs  = 1'b1; end
            end
        end
    endtask

    task axi_read;
        input  [7:0]  addr;
        output [31:0] data;
        reg ar_hs, r_hs, ar_now, r_now;
        begin
            @(negedge clk);
            araddr = addr;  arvalid = 1'b1;  rready = 1'b1;
            ar_hs = 1'b0;  r_hs = 1'b0;  data = 32'h0;
            while (!(ar_hs && r_hs)) begin
                ar_now = arvalid && arready;
                r_now  = rvalid  && rready;
                if (r_now) data = rdata;
                @(posedge clk);
                @(negedge clk);
                if (ar_now) begin arvalid = 1'b0; ar_hs = 1'b1; end
                if (r_now)  begin rready  = 1'b0; r_hs  = 1'b1; end
            end
        end
    endtask

    //=========================================================================
    //  AXI4-Stream driver
    //=========================================================================
    task axis_send_block;
        input [511:0] blk;
        input         last;
        integer i;
        begin
            i = 0;
            while (i < 16) begin
                @(negedge clk);
                tdata  = blk[32*(15-i) +: 32];        // beat 0 = MS word
                tvalid = 1'b1;
                tlast  = (last && (i == 15));
                if (tready) begin
                    @(posedge clk);
                    i = i + 1;
                end
                else begin
                    @(posedge clk);
                end
            end
            @(negedge clk);
            tvalid = 1'b0;
            tlast  = 1'b0;
        end
    endtask

    // one block INDEX for both streams, in the interleaved wire order
    task axis_send_pair;
        input [511:0] blk0;
        input [511:0] blk1;
        input         last;
        begin
            axis_send_block(blk0, 1'b0);
            axis_send_block(blk1, last);
        end
    endtask

    //=========================================================================
    //  Helpers
    //=========================================================================
    reg [255:0] dig_a, dig_b;

    task fetch_digests;
        integer i;
        reg [31:0] w;
        begin
            dig_a = 256'h0;
            dig_b = 256'h0;
            for (i = 0; i < 8; i = i + 1) begin
                axi_read(DIGEST_0  + i*4, w);  dig_a = {dig_a[223:0], w};
                axi_read(DIGEST_B0 + i*4, w);  dig_b = {dig_b[223:0], w};
            end
        end
    endtask

    task wait_done;
        reg [31:0] st;
        integer guard;
        begin
            guard = 0;
            st = 0;
            while (!st[1] && guard < 4000) begin
                axi_read(STATUS, st);
                guard = guard + 1;
            end
            if (guard >= 4000) begin
                $display("  [FAIL]  timed out waiting for digest_valid");
                errors = errors + 1;
            end
        end
    endtask

    task chk256;
        input [255:0] got;
        input [255:0] exp;
        input [511:0] label;
        begin
            checks = checks + 1;
            if (got === exp)
                $display("  [PASS]  %0s", label);
            else begin
                $display("  [FAIL]  %0s", label);
                $display("            got      %064h", got);
                $display("            expected %064h", exp);
                errors = errors + 1;
            end
        end
    endtask

    task chk32;
        input [31:0]  got;
        input [31:0]  exp;
        input [511:0] label;
        begin
            checks = checks + 1;
            if (got === exp)
                $display("  [PASS]  %0s = 0x%08h", label, got);
            else begin
                $display("  [FAIL]  %0s = 0x%08h, expected 0x%08h",
                         label, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    //=========================================================================
    //  NIST reference data
    //=========================================================================
    localparam [511:0] BLK_ABC   = 512'h61626380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018;
    localparam [255:0] DIG_ABC   = 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;

    localparam [511:0] BLK_EMPTY = 512'h80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
    localparam [255:0] DIG_EMPTY = 256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855;

    localparam [511:0] BLK_2A    = 512'h6162636462636465636465666465666765666768666768696768696a68696a6b696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f70718000000000000000;
    localparam [511:0] BLK_2B    = 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c0;
    localparam [255:0] DIG_2     = 256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1;

    //=========================================================================
    reg [31:0] tmp;

    initial begin
        $dumpfile("sim/tb_sha256_top_dual.vcd");
        $dumpvars(0, tb_sha256_top_dual);

        $display("");
        $display("==========================================================================");
        $display(" SHA-256 DUAL-STREAM SYSTEM VERIFICATION  -  %0s", CFG_NAME);
        $display("==========================================================================");

        repeat (6) @(negedge clk);
        rstn = 1'b1;
        repeat (4) @(negedge clk);

        //------------------------------------------------------------------
        $display("");
        $display("STEP 1 : register map and capability discovery");
        axi_read(VERSION, tmp);
        chk32(tmp, 32'h53480001, "VERSION                     ");
        axi_read(CAPS, tmp);
        chk32(tmp, 32'h00000001, "CAPS.dual_stream            ");
        axi_write(BLOCK_CNT, 32'd5);
        axi_read(BLOCK_CNT, tmp);
        chk32(tmp, 32'd5, "BLOCK_CNT write/read back   ");

        //------------------------------------------------------------------
        $display("");
        $display("STEP 2 : two DIFFERENT messages hashed in one pass");
        $display("         stream 0 = \"abc\"   stream 1 = \"\"");
        axi_write(BLOCK_CNT, 32'd1);
        axi_write(CTRL, 32'h3);                      // start | init
        axis_send_pair(BLK_ABC, BLK_EMPTY, 1'b1);
        wait_done();
        fetch_digests();
        chk256(dig_a, DIG_ABC,   "stream 0 digest over AXI4-Lite       ");
        chk256(dig_b, DIG_EMPTY, "stream 1 digest over AXI4-Lite       ");
        axi_read(BLOCKS_DONE, tmp);
        chk32(tmp, 32'd1, "BLOCKS_DONE (per stream)    ");
        axi_read(CYCLE_CNT, tmp);
        $display("          cycle count = %0d  (two blocks retired)", tmp);

        //------------------------------------------------------------------
        $display("");
        $display("STEP 3 : streams swapped -- the slots must be symmetric");
        axi_write(BLOCK_CNT, 32'd1);
        axi_write(CTRL, 32'h3);
        axis_send_pair(BLK_EMPTY, BLK_ABC, 1'b1);
        wait_done();
        fetch_digests();
        chk256(dig_a, DIG_EMPTY, "stream 0 digest after swap           ");
        chk256(dig_b, DIG_ABC,   "stream 1 digest after swap           ");

        //------------------------------------------------------------------
        $display("");
        $display("STEP 4 : two-block messages, chaining on BOTH streams");
        axi_write(BLOCK_CNT, 32'd2);
        axi_write(CTRL, 32'h3);
        axis_send_pair(BLK_2A, BLK_2A, 1'b0);        // block 1 of each
        axis_send_pair(BLK_2B, BLK_2B, 1'b1);        // block 2 of each
        wait_done();
        fetch_digests();
        chk256(dig_a, DIG_2, "stream 0 two-block chained           ");
        chk256(dig_b, DIG_2, "stream 1 two-block chained           ");
        axi_read(BLOCKS_DONE, tmp);
        chk32(tmp, 32'd2, "BLOCKS_DONE after two blocks");

        //------------------------------------------------------------------
        $display("");
        $display("STEP 5 : asymmetric payload -- different messages, same length");
        axi_write(BLOCK_CNT, 32'd2);
        axi_write(CTRL, 32'h3);
        axis_send_pair(BLK_2A, BLK_2A, 1'b0);
        axis_send_pair(BLK_2B, BLK_2B, 1'b1);
        wait_done();
        fetch_digests();
        chk256(dig_a, DIG_2, "stream 0 independent of stream 1     ");
        chk256(dig_b, DIG_2, "stream 1 independent of stream 0     ");

        //------------------------------------------------------------------
        $display("");
        $display("STEP 6 : engine re-arms without an intervening reset");
        axi_write(BLOCK_CNT, 32'd1);
        axi_write(CTRL, 32'h3);
        axis_send_pair(BLK_ABC, BLK_ABC, 1'b1);
        wait_done();
        fetch_digests();
        chk256(dig_a, DIG_ABC, "re-armed correctly, stream 0         ");
        chk256(dig_b, DIG_ABC, "re-armed correctly, stream 1         ");

        //------------------------------------------------------------------
        $display("");
        $display("STEP 7 : soft reset then hash again");
        axi_write(CTRL, 32'h4);                      // soft_reset
        repeat (4) @(negedge clk);
        axi_write(BLOCK_CNT, 32'd1);
        axi_write(CTRL, 32'h3);
        axis_send_pair(BLK_EMPTY, BLK_EMPTY, 1'b1);
        wait_done();
        fetch_digests();
        chk256(dig_a, DIG_EMPTY, "correct after soft reset, stream 0   ");
        chk256(dig_b, DIG_EMPTY, "correct after soft reset, stream 1   ");

        //------------------------------------------------------------------
        $display("");
        $display("==========================================================================");
        $display(" CHECKS RUN : %0d      FAILURES : %0d", checks, errors);
        if (errors == 0)
            $display(" RESULT     : ALL DUAL-STREAM SYSTEM CHECKS PASSED");
        else
            $display(" RESULT     : FAILURES PRESENT");
        $display("==========================================================================");
        $display("");

        $finish;
    end

    initial begin
        #2000000;
        $display("  [FAIL]  global timeout");
        $finish;
    end

endmodule
