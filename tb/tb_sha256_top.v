//============================================================================
//  tb_sha256_top.v  —  SYSTEM-LEVEL integration testbench
//----------------------------------------------------------------------------
//  Exercises sha256_top exactly the way the hardware will be driven:
//
//    1. AXI4-Lite writes to configure block count and start the engine
//    2. AXI4-Stream beats delivering the padded message (as the DMA would)
//    3. AXI4-Lite reads polling STATUS, then reading the digest back
//
//  This is the test that catches integration bugs the core-level testbench
//  cannot see: byte ordering across the stream, back-pressure handling,
//  register map errors, and multi-block sequencing.
//
//  Run:  make sys
//============================================================================
`timescale 1ns / 1ps

module tb_sha256_top;

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

    // ---- AXI4-Lite master signals -------------------------------------------
    reg  [7:0]  awaddr = 0;   reg awvalid = 0;   wire awready;
    reg  [31:0] wdata  = 0;   reg wvalid  = 0;   wire wready;
    wire [1:0]  bresp;        wire bvalid;       reg  bready = 0;
    reg  [7:0]  araddr = 0;   reg arvalid = 0;   wire arready;
    wire [31:0] rdata;        wire [1:0] rresp;  wire rvalid;  reg rready = 0;

    // ---- AXI4-Stream master signals -----------------------------------------
    reg  [31:0] tdata  = 0;   reg tvalid = 0;    wire tready;   reg tlast = 0;

    wire irq;

    sha256_top #(
`ifdef CORE_B
        .CORE_SELECT        (1),            // Configuration B - 2x unrolled
`else
        .CORE_SELECT        (0),            // Configuration A - iterative
`endif
        .C_S_AXI_ADDR_WIDTH (8)
    ) dut (
        .s_axi_aclk    (clk),    .s_axi_aresetn (rstn),
        .s_axi_awaddr  (awaddr), .s_axi_awprot (3'b000), .s_axi_awvalid (awvalid), .s_axi_awready (awready),
        .s_axi_wdata   (wdata),  .s_axi_wstrb  (4'hF),   .s_axi_wvalid  (wvalid),  .s_axi_wready  (wready),
        .s_axi_bresp   (bresp),  .s_axi_bvalid (bvalid), .s_axi_bready  (bready),
        .s_axi_araddr  (araddr), .s_axi_arprot (3'b000), .s_axi_arvalid (arvalid), .s_axi_arready (arready),
        .s_axi_rdata   (rdata),  .s_axi_rresp  (rresp),  .s_axi_rvalid  (rvalid),  .s_axi_rready  (rready),
        .s_axis_tdata  (tdata),  .s_axis_tkeep (4'hF),   .s_axis_tvalid (tvalid),  .s_axis_tready (tready),
        .s_axis_tlast  (tlast),
        .irq           (irq)
    );

    //=========================================================================
    //  AXI4-Lite bus functional model
    //=========================================================================
    //  AXI4-Lite BFM.
    //
    //  Discipline: OBSERVE the handshake at the negative edge, let the
    //  transfer complete at the following positive edge, then deassert at the
    //  negative edge after that.  A transfer occurs on the rising edge where
    //  VALID and READY are both high, so VALID must be held THROUGH that edge
    //  -- deasserting as soon as READY is seen drops the transfer entirely.
    //
    //  The three write channels (AW, W, B) are tracked independently; a
    //  sequential "wait(awready); wait(wready)" deadlocks whenever both
    //  readys assert in the same cycle.

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
                @(posedge clk);          // transfers complete here
                @(negedge clk);          // safely past the edge
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
    //  AXI4-Stream driver — sends one 512-bit block as sixteen 32-bit beats
    //=========================================================================
    //  Drives on the negative edge and samples tready there too.  Because
    //  tready is combinational from a state register that only changes on the
    //  positive edge, its value at the negedge is exactly the value the DUT
    //  will see at the coming posedge -- so this handshake is race-free.
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
                    @(posedge clk);                   // beat accepted here
                    i = i + 1;
                end
                else begin
                    @(posedge clk);                   // back-pressured, retry
                end
            end
            @(negedge clk);
            tvalid = 1'b0;
            tlast  = 1'b0;
        end
    endtask

    //=========================================================================
    //  Helpers
    //=========================================================================
    reg [255:0] read_digest;

    task fetch_digest;
        integer i;
        reg [31:0] w;
        begin
            read_digest = 256'h0;
            for (i = 0; i < 8; i = i + 1) begin
                axi_read(DIGEST_0 + i*4, w);
                read_digest = {read_digest[223:0], w};
            end
        end
    endtask

    task wait_done;
        reg [31:0] st;
        integer guard;
        begin
            guard = 0;
            st = 0;
            while (!st[1] && guard < 2000) begin
                axi_read(STATUS, st);
                guard = guard + 1;
            end
            if (guard >= 2000) begin
                $display("  [FAIL]  timed out waiting for digest_valid");
                errors = errors + 1;
            end
        end
    endtask

    task chk256;
        input [255:0] got;
        input [255:0] exp;
        input [255:0] label;
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

    //=========================================================================
    //  NIST reference data (generated by model/sha256_golden.py)
    //=========================================================================
    localparam [511:0] BLK_ABC   = 512'h61626380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018;
    localparam [255:0] DIG_ABC   = 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;

    localparam [511:0] BLK_EMPTY = 512'h80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
    localparam [255:0] DIG_EMPTY = 256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855;

    localparam [511:0] BLK_2A    = 512'h6162636462636465636465666465666765666768666768696768696a68696a6b696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f70718000000000000000;
    localparam [511:0] BLK_2B    = 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c0;
    localparam [255:0] DIG_2     = 256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1;

    //=========================================================================
    //  Main
    //=========================================================================
    reg [31:0] tmp;

    initial begin
        $display("");
        $display("==========================================================================");
        $display(" SHA-256 SYSTEM-LEVEL VERIFICATION  (AXI4-Lite + AXI4-Stream)");
        $display("==========================================================================");

        rstn = 1'b0;
        repeat (10) @(posedge clk);
        rstn = 1'b1;
        repeat (5) @(posedge clk);

        // ---- 1. register map sanity ----------------------------------------
        $display("");
        $display("STEP 1 : register map");
        axi_read(VERSION, tmp);
        checks = checks + 1;
        if (tmp === 32'h5348_0001)
            $display("  [PASS]  VERSION reads 0x%08h", tmp);
        else begin
            $display("  [FAIL]  VERSION reads 0x%08h, expected 0x53480001", tmp);
            errors = errors + 1;
        end

        axi_write(BLOCK_CNT, 32'd7);
        axi_read(BLOCK_CNT, tmp);
        checks = checks + 1;
        if (tmp[15:0] === 16'd7)
            $display("  [PASS]  BLOCK_CNT write/read back = %0d", tmp[15:0]);
        else begin
            $display("  [FAIL]  BLOCK_CNT read %0d, expected 7", tmp[15:0]);
            errors = errors + 1;
        end

        // ---- 2. single block, "abc" -----------------------------------------
        $display("");
        $display("STEP 2 : single-block message  SHA-256(\"abc\")");
        axi_write(BLOCK_CNT, 32'd1);
        axi_write(CTRL, 32'h3);                 // start=1, init=1
        axis_send_block(BLK_ABC, 1'b1);
        wait_done();
        fetch_digest();
        chk256(read_digest, DIG_ABC, "digest read back over AXI4-Lite");

        axi_read(CYCLE_CNT, tmp);
        $display("          cycle count = %0d  (expect ~66 + stream overhead)", tmp);
        axi_read(BLOCKS_DONE, tmp);
        checks = checks + 1;
        if (tmp[15:0] === 16'd1)
            $display("  [PASS]  BLOCKS_DONE = 1");
        else begin
            $display("  [FAIL]  BLOCKS_DONE = %0d, expected 1", tmp[15:0]);
            errors = errors + 1;
        end

        // ---- 3. empty message ------------------------------------------------
        $display("");
        $display("STEP 3 : empty message  SHA-256(\"\")");
        axi_write(BLOCK_CNT, 32'd1);
        axi_write(CTRL, 32'h3);
        axis_send_block(BLK_EMPTY, 1'b1);
        wait_done();
        fetch_digest();
        chk256(read_digest, DIG_EMPTY, "digest read back over AXI4-Lite");

        // ---- 4. two-block message --------------------------------------------
        $display("");
        $display("STEP 4 : two-block message, chaining across blocks");
        axi_write(BLOCK_CNT, 32'd2);
        axi_write(CTRL, 32'h3);                 // start, init
        axis_send_block(BLK_2A, 1'b0);
        axis_send_block(BLK_2B, 1'b1);
        wait_done();
        fetch_digest();
        chk256(read_digest, DIG_2, "digest read back over AXI4-Lite");

        axi_read(BLOCKS_DONE, tmp);
        checks = checks + 1;
        if (tmp[15:0] === 16'd2)
            $display("  [PASS]  BLOCKS_DONE = 2");
        else begin
            $display("  [FAIL]  BLOCKS_DONE = %0d, expected 2", tmp[15:0]);
            errors = errors + 1;
        end

        // ---- 5. back-to-back messages (re-arm without reset) -----------------
        $display("");
        $display("STEP 5 : second message without an intervening reset");
        axi_write(BLOCK_CNT, 32'd1);
        axi_write(CTRL, 32'h3);
        axis_send_block(BLK_ABC, 1'b1);
        wait_done();
        fetch_digest();
        chk256(read_digest, DIG_ABC, "engine re-arms correctly");

        // ---- 6. soft reset ----------------------------------------------------
        $display("");
        $display("STEP 6 : soft reset then hash again");
        axi_write(CTRL, 32'h4);                 // soft_reset
        repeat (5) @(posedge clk);
        axi_write(BLOCK_CNT, 32'd1);
        axi_write(CTRL, 32'h3);
        axis_send_block(BLK_EMPTY, 1'b1);
        wait_done();
        fetch_digest();
        chk256(read_digest, DIG_EMPTY, "correct digest after soft reset");

        $display("");
        $display("==========================================================================");
        $display(" CHECKS RUN : %0d      FAILURES : %0d", checks, errors);
        if (errors == 0)
            $display(" RESULT     : ALL SYSTEM-LEVEL CHECKS PASSED");
        else
            $display(" RESULT     : FAILURES PRESENT");
        $display("==========================================================================");
        $display("");
        $finish;
    end

    initial begin
        $dumpfile("sim/tb_sha256_top.vcd");
        $dumpvars(0, tb_sha256_top);
    end

    initial begin
        #2000000;
        $display("  [FAIL]  TIMEOUT");
        $finish;
    end

endmodule
