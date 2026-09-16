//============================================================================
//  tb_sha256_cslow.v  —  verification for the INTERLEAVED cores, C and D
//----------------------------------------------------------------------------
//  Checks, in order:
//    1. Two DIFFERENT single-block messages hashed simultaneously
//    2. The streams swapped, proving the two slots are symmetric
//    3. Multi-block chaining on both streams at once
//    4. Asymmetric traffic: stream 0 on block 2 while stream 1 restarts
//    5. Cross-validation of Config C against Config A, digest for digest
//    6. Cycle count: 66 cycles retiring TWO blocks = 33 effective per block
//    7. Configuration D (U=2, C=2) on the same vectors
//    8. C vs D cross-validation and D's 34-cycle / 17-effective count
//
//  Run:  make cslow
//============================================================================
`timescale 1ns / 1ps

module tb_sha256_cslow;


    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;               // 100 MHz

    integer errors = 0;
    integer checks = 0;

    // ---- NIST reference data -------------------------------------------------
    localparam [511:0] BLK_ABC   = 512'h61626380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018;
    localparam [255:0] DIG_ABC   = 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;

    localparam [511:0] BLK_EMPTY = 512'h80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
    localparam [255:0] DIG_EMPTY = 256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855;

    // 56-byte message -> TWO blocks
    localparam [511:0] BLK_2A    = 512'h6162636462636465636465666465666765666768666768696768696a68696a6b696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f70718000000000000000;
    localparam [511:0] BLK_2B    = 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c0;
    localparam [255:0] DIG_2     = 256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1;

    //=========================================================================
    //  DUT : Configuration C
    //=========================================================================
    reg          c_bv = 1'b0, c_i0 = 1'b0, c_i1 = 1'b0;
    reg  [511:0] c_b0 = 512'h0, c_b1 = 512'h0;
    wire         c_ready, c_dv;
    wire [255:0] c_dig0, c_dig1;

    sha256_core_cslow2 u_cslow (
        .clk(clk), .rst_n(rst_n),
        .block_valid(c_bv), .init_0(c_i0), .init_1(c_i1),
        .block_in_0(c_b0), .block_in_1(c_b1),
        .ready(c_ready), .digest_valid(c_dv),
        .digest_0(c_dig0), .digest_1(c_dig1)
    );

    //=========================================================================
    //  DUT : Configuration D  (U=2, C=2)
    //=========================================================================
    reg          d_bv = 1'b0, d_i0 = 1'b0, d_i1 = 1'b0;
    reg  [511:0] d_b0 = 512'h0, d_b1 = 512'h0;
    wire         d_ready, d_dv;
    wire [255:0] d_dig0, d_dig1;

    sha256_core_u2c2 u_u2c2 (
        .clk(clk), .rst_n(rst_n),
        .block_valid(d_bv), .init_0(d_i0), .init_1(d_i1),
        .block_in_0(d_b0), .block_in_1(d_b1),
        .ready(d_ready), .digest_valid(d_dv),
        .digest_0(d_dig0), .digest_1(d_dig1)
    );

    //=========================================================================
    //  Reference : Configuration A, for cross-validation
    //=========================================================================
    reg          a_bv = 1'b0, a_init = 1'b0;
    reg  [511:0] a_blk = 512'h0;
    wire         a_ready, a_dv;
    wire [255:0] a_dig;

    sha256_core_iter u_iter (
        .clk(clk), .rst_n(rst_n),
        .block_valid(a_bv), .init(a_init), .block_in(a_blk),
        .ready(a_ready), .digest_valid(a_dv), .digest(a_dig)
    );

    //=========================================================================
    //  Helpers
    //=========================================================================
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

    task chk_int;
        input integer got;
        input integer exp;
        input [511:0] label;
        begin
            checks = checks + 1;
            if (got === exp)
                $display("  [PASS]  %0s = %0d", label, got);
            else begin
                $display("  [FAIL]  %0s = %0d, expected %0d", label, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    integer cyc_count;
    reg     counting;

    // free-running cycle counter used for the 66-cycle measurement
    always @(posedge clk) if (counting) cyc_count = cyc_count + 1;

    // ---- drive one block pair through Config C ------------------------------
    task cslow_block;
        input [511:0] b0;
        input [511:0] b1;
        input         i0;
        input         i1;
        begin
            @(negedge clk);
            c_b0 = b0;  c_b1 = b1;
            c_i0 = i0;  c_i1 = i1;
            c_bv = 1'b1;
            @(negedge clk);
            c_bv = 1'b0;
            wait (c_dv === 1'b1);
            @(negedge clk);
        end
    endtask

    // ---- drive one block pair through Config D ------------------------------
    task d_block;
        input [511:0] b0;
        input [511:0] b1;
        input         i0;
        input         i1;
        begin
            @(negedge clk);
            d_b0 = b0;  d_b1 = b1;
            d_i0 = i0;  d_i1 = i1;
            d_bv = 1'b1;
            @(negedge clk);
            d_bv = 1'b0;
            wait (d_dv === 1'b1);
            @(negedge clk);
        end
    endtask

    // ---- drive one block through Config A -----------------------------------
    task iter_block;
        input [511:0] blk;
        input         ini;
        begin
            @(negedge clk);
            a_blk  = blk;
            a_init = ini;
            a_bv   = 1'b1;
            @(negedge clk);
            a_bv = 1'b0;
            wait (a_dv === 1'b1);
            @(negedge clk);
        end
    endtask

    //=========================================================================
    //  Test sequence
    //=========================================================================
    initial begin
        $dumpfile("sim/tb_sha256_cslow.vcd");
        $dumpvars(0, tb_sha256_cslow);

        $display("");
        $display("==========================================================================");
        $display(" SHA-256 INTERLEAVED CORE VERIFICATION   (Config C and Config D)");
        $display("==========================================================================");

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        //------------------------------------------------------------------
        $display("");
        $display("LEVEL 1 : two different messages hashed simultaneously");
        cslow_block(BLK_ABC, BLK_EMPTY, 1'b1, 1'b1);
        chk256(c_dig0, DIG_ABC,   "stream 0 = SHA-256(\"abc\")           ");
        chk256(c_dig1, DIG_EMPTY, "stream 1 = SHA-256(\"\")              ");

        //------------------------------------------------------------------
        $display("");
        $display("LEVEL 2 : streams swapped — the two slots must be symmetric");
        cslow_block(BLK_EMPTY, BLK_ABC, 1'b1, 1'b1);
        chk256(c_dig0, DIG_EMPTY, "stream 0 = SHA-256(\"\")              ");
        chk256(c_dig1, DIG_ABC,   "stream 1 = SHA-256(\"abc\")           ");

        //------------------------------------------------------------------
        $display("");
        $display("LEVEL 3 : multi-block chaining on BOTH streams at once");
        cslow_block(BLK_2A, BLK_2A, 1'b1, 1'b1);   // first block, both streams
        cslow_block(BLK_2B, BLK_2B, 1'b0, 1'b0);   // second block, chained
        chk256(c_dig0, DIG_2, "stream 0 = 56-byte two-block message ");
        chk256(c_dig1, DIG_2, "stream 1 = 56-byte two-block message ");

        //------------------------------------------------------------------
        $display("");
        $display("LEVEL 4 : asymmetric traffic — stream 0 continues a message");
        $display("          while stream 1 starts a fresh one");
        cslow_block(BLK_2A,    BLK_ABC,   1'b1, 1'b1);  // s0 block 1 of 2, s1 done
        cslow_block(BLK_2B,    BLK_EMPTY, 1'b0, 1'b1);  // s0 block 2, s1 restarts
        chk256(c_dig0, DIG_2,     "stream 0 chained across the pair     ");
        chk256(c_dig1, DIG_EMPTY, "stream 1 restarted independently     ");

        //------------------------------------------------------------------
        $display("");
        $display("LEVEL 5 : cross-validation against Configuration A");
        iter_block(BLK_ABC, 1'b1);
        cslow_block(BLK_ABC, BLK_ABC, 1'b1, 1'b1);
        chk256(c_dig0, a_dig, "Config C stream 0 == Config A        ");
        chk256(c_dig1, a_dig, "Config C stream 1 == Config A        ");

        //------------------------------------------------------------------
        $display("");
        $display("LEVEL 6 : cycle count per block pair");

        @(negedge clk);
        cyc_count = 0;
        counting  = 1'b1;
        c_b0 = BLK_ABC;  c_b1 = BLK_EMPTY;
        c_i0 = 1'b1;     c_i1 = 1'b1;
        c_bv = 1'b1;
        @(negedge clk);
        c_bv = 1'b0;
        wait (c_dv === 1'b1);
        counting = 1'b0;

        $display("          66 cycles retire TWO blocks -> 33 effective per block");
        $display("          Config A : 66 per block   Config B : 34 per block");
        chk_int(cyc_count, 66, "cycles for a two-block pair          ");
        chk_int(cyc_count / 2, 33, "effective cycles per block           ");

        //------------------------------------------------------------------
        $display("");
        $display("LEVEL 7 : Configuration D  (U=2, C=2)  — 4 round instances");
        d_block(BLK_ABC, BLK_EMPTY, 1'b1, 1'b1);
        chk256(d_dig0, DIG_ABC,   "D stream 0 = SHA-256(\"abc\")         ");
        chk256(d_dig1, DIG_EMPTY, "D stream 1 = SHA-256(\"\")            ");

        d_block(BLK_EMPTY, BLK_ABC, 1'b1, 1'b1);
        chk256(d_dig0, DIG_EMPTY, "D streams swapped, slot 0            ");
        chk256(d_dig1, DIG_ABC,   "D streams swapped, slot 1            ");

        d_block(BLK_2A, BLK_2A, 1'b1, 1'b1);
        d_block(BLK_2B, BLK_2B, 1'b0, 1'b0);
        chk256(d_dig0, DIG_2, "D stream 0 two-block chained         ");
        chk256(d_dig1, DIG_2, "D stream 1 two-block chained         ");

        d_block(BLK_2A, BLK_ABC,   1'b1, 1'b1);
        d_block(BLK_2B, BLK_EMPTY, 1'b0, 1'b1);
        chk256(d_dig0, DIG_2,     "D asymmetric: s0 chained             ");
        chk256(d_dig1, DIG_EMPTY, "D asymmetric: s1 restarted           ");

        //------------------------------------------------------------------
        $display("");
        $display("LEVEL 8 : four-way agreement  A == C == D");
        iter_block(BLK_2A, 1'b1);
        iter_block(BLK_2B, 1'b0);
        cslow_block(BLK_2A, BLK_2A, 1'b1, 1'b1);
        cslow_block(BLK_2B, BLK_2B, 1'b0, 1'b0);
        d_block(BLK_2A, BLK_2A, 1'b1, 1'b1);
        d_block(BLK_2B, BLK_2B, 1'b0, 1'b0);
        chk256(c_dig0, a_dig, "Config C == Config A                 ");
        chk256(d_dig0, a_dig, "Config D == Config A                 ");
        chk256(d_dig1, c_dig1, "Config D == Config C                 ");

        //------------------------------------------------------------------
        $display("");
        $display("LEVEL 9 : Configuration D cycle count");

        @(negedge clk);
        cyc_count = 0;
        counting  = 1'b1;
        d_b0 = BLK_ABC;  d_b1 = BLK_EMPTY;
        d_i0 = 1'b1;     d_i1 = 1'b1;
        d_bv = 1'b1;
        @(negedge clk);
        d_bv = 1'b0;
        wait (d_dv === 1'b1);
        counting = 1'b0;

        $display("          34 cycles retire TWO blocks -> 17 effective per block");
        $display("          A: 66   B: 34   C: 33   D: 17   (effective, per block)");
        chk_int(cyc_count, 34, "D cycles for a two-block pair        ");
        chk_int(cyc_count / 2, 17, "D effective cycles per block         ");

        //------------------------------------------------------------------
        $display("");
        $display("==========================================================================");
        $display(" CHECKS RUN : %0d      FAILURES : %0d", checks, errors);
        if (errors == 0)
            $display(" RESULT     : ALL INTERLEAVED-CORE CHECKS PASSED");
        else
            $display(" RESULT     : FAILURES PRESENT");
        $display("==========================================================================");
        $display("");

        $finish;
    end

    // watchdog
    initial begin
        #500000;
        $display("  [FAIL]  timeout — core did not complete");
        $finish;
    end

endmodule
