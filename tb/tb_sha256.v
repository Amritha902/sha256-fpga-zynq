//============================================================================
//  tb_sha256.v  —  self-checking testbench for both SHA-256 configurations
//----------------------------------------------------------------------------
//  Checks, in order:
//    1. Sigma / sigma / Ch / Maj primitives against known values
//    2. K ROM boundary entries
//    3. Config A  (iterative)   on NIST single-block and multi-block vectors
//    4. Config B  (2x unrolled) on the same vectors
//    5. A vs B    bit-identical digests
//    6. Cycle counts, confirming 66 vs 34 cycles per block
//
//  Run:  make
//============================================================================
`timescale 1ns / 1ps

module tb_sha256;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;               // 100 MHz

    integer errors = 0;
    integer checks = 0;

    // ---- NIST reference data -------------------------------------------------
    // "abc" padded to one 512-bit block
    localparam [511:0] BLK_ABC   = 512'h61626380000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000018;
    localparam [255:0] DIG_ABC   = 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;

    // empty message, one block
    localparam [511:0] BLK_EMPTY = 512'h80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
    localparam [255:0] DIG_EMPTY = 256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855;

    // 56-byte message "abcdbcde...nopq" -> TWO blocks
    localparam [511:0] BLK_2A    = 512'h6162636462636465636465666465666765666768666768696768696a68696a6b696a6b6c6a6b6c6d6b6c6d6e6c6d6e6f6d6e6f706e6f70718000000000000000;
    localparam [511:0] BLK_2B    = 512'h000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c0;
    localparam [255:0] DIG_2     = 256'h248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1;

    //=========================================================================
    //  1.  Primitive checks
    //=========================================================================
    reg  [31:0] px, py, pz;
    wire [31:0] o_bs0, o_bs1, o_ss0, o_ss1, o_ch, o_maj;

    sha256_big_sigma0   u_bs0 (.x(px), .out(o_bs0));
    sha256_big_sigma1   u_bs1 (.x(px), .out(o_bs1));
    sha256_small_sigma0 u_ss0 (.x(px), .out(o_ss0));
    sha256_small_sigma1 u_ss1 (.x(px), .out(o_ss1));
    sha256_ch           u_ch  (.x(px), .y(py), .z(pz), .out(o_ch));
    sha256_maj          u_maj (.x(px), .y(py), .z(pz), .out(o_maj));

    task chk32;
        input [31:0] got;
        input [31:0] exp;
        input [255:0] label;
        begin
            checks = checks + 1;
            if (got === exp)
                $display("  [PASS]  %0s = %08h", label, got);
            else begin
                $display("  [FAIL]  %0s = %08h, expected %08h", label, got, exp);
                errors = errors + 1;
            end
        end
    endtask

    task check_primitives;
        begin
            // values cross-checked against the Python golden model
            px = 32'h6a09e667; #1;
            chk32(o_bs0, 32'hce20b47e, "Sigma0(6a09e667)");
            chk32(o_bs1, 32'h55b65510, "Sigma1(6a09e667)");
            chk32(o_ss0, 32'hba0cf582, "sigma0(6a09e667)");
            chk32(o_ss1, 32'hcfe5da3c, "sigma1(6a09e667)");

            // Ch: all-ones selector picks y, all-zeros picks z
            px = 32'hffffffff; py = 32'haaaaaaaa; pz = 32'h55555555; #1;
            chk32(o_ch, 32'haaaaaaaa, "Ch(all1,y,z) -> y");
            px = 32'h00000000; #1;
            chk32(o_ch, 32'h55555555, "Ch(all0,y,z) -> z");

            // Maj: two of three
            px = 32'hffffffff; py = 32'hffffffff; pz = 32'h00000000; #1;
            chk32(o_maj, 32'hffffffff, "Maj(1,1,0)      ");
            px = 32'hffffffff; py = 32'h00000000; pz = 32'h00000000; #1;
            chk32(o_maj, 32'h00000000, "Maj(1,0,0)      ");

            // ROTR is pure rewiring: rotating 1 right by 2 gives bit 30 set
            px = 32'h00000001; #1;
            chk32(o_bs0, 32'h40000000 ^ 32'h00080000 ^ 32'h00000400,
                  "Sigma0(00000001)");
        end
    endtask

    //=========================================================================
    //  2.  K ROM
    //=========================================================================
    reg  [5:0]  k_addr;
    wire [31:0] k_data;
    sha256_k_rom u_krom (.addr(k_addr), .k(k_data));

    task check_krom;
        begin
            k_addr = 6'd0;  #1; chk32(k_data, 32'h428a2f98, "K[ 0]           ");
            k_addr = 6'd15; #1; chk32(k_data, 32'hc19bf174, "K[15]           ");
            k_addr = 6'd32; #1; chk32(k_data, 32'h27b70a85, "K[32]           ");
            k_addr = 6'd63; #1; chk32(k_data, 32'hc67178f2, "K[63]           ");
        end
    endtask

    //=========================================================================
    //  3/4.  The two cores
    //=========================================================================
    reg          a_bv = 1'b0, a_init = 1'b0;
    reg  [511:0] a_blk = 512'h0;
    wire         a_ready, a_dv;
    wire [255:0] a_dig;

    sha256_core_iter u_iter (
        .clk(clk), .rst_n(rst_n),
        .block_valid(a_bv), .init(a_init), .block_in(a_blk), .ready(a_ready),
        .digest_valid(a_dv), .digest(a_dig)
    );

    reg          b_bv = 1'b0, b_init = 1'b0;
    reg  [511:0] b_blk = 512'h0;
    wire         b_ready, b_dv;
    wire [255:0] b_dig;

    sha256_core_unroll2 u_unroll (
        .clk(clk), .rst_n(rst_n),
        .block_valid(b_bv), .init(b_init), .block_in(b_blk), .ready(b_ready),
        .digest_valid(b_dv), .digest(b_dig)
    );

    integer a_cycles, b_cycles;

    // ---- push one block through Config A, counting cycles -------------------
    task push_a;
        input        first;
        input [511:0] blk;
        integer n;
        begin
            wait (a_ready);
            @(posedge clk);
            a_blk  = blk;
            a_init = first;
            a_bv   = 1'b1;
            @(posedge clk);
            a_bv   = 1'b0;
            n = 1;
            while (!a_dv) begin
                @(posedge clk);
                n = n + 1;
            end
            a_cycles = n;
            @(posedge clk);
        end
    endtask

    // ---- push one block through Config B ------------------------------------
    task push_b;
        input        first;
        input [511:0] blk;
        integer n;
        begin
            wait (b_ready);
            @(posedge clk);
            b_blk  = blk;
            b_init = first;
            b_bv   = 1'b1;
            @(posedge clk);
            b_bv   = 1'b0;
            n = 1;
            while (!b_dv) begin
                @(posedge clk);
                n = n + 1;
            end
            b_cycles = n;
            @(posedge clk);
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
    //  Main
    //=========================================================================
    initial begin
        $display("");
        $display("==========================================================================");
        $display(" SHA-256 RTL VERIFICATION  —  FIPS 180-4 conformance");
        $display("==========================================================================");

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("");
        $display("LEVEL 1 : logical functions");
        check_primitives();

        $display("");
        $display("LEVEL 2 : K constant ROM");
        check_krom();

        $display("");
        $display("LEVEL 3 : Configuration A  (iterative, 1 round/cycle)");
        push_a(1'b1, BLK_ABC);
        chk256(a_dig, DIG_ABC, "SHA-256(\"abc\") single block");
        push_a(1'b1, BLK_EMPTY);
        chk256(a_dig, DIG_EMPTY, "SHA-256(\"\")    empty message");
        push_a(1'b1, BLK_2A);
        push_a(1'b0, BLK_2B);
        chk256(a_dig, DIG_2, "SHA-256(56-byte msg) two blocks, chained");

        $display("");
        $display("LEVEL 4 : Configuration B  (2x unrolled, 2 rounds/cycle)");
        push_b(1'b1, BLK_ABC);
        chk256(b_dig, DIG_ABC, "SHA-256(\"abc\") single block");
        push_b(1'b1, BLK_EMPTY);
        chk256(b_dig, DIG_EMPTY, "SHA-256(\"\")    empty message");
        push_b(1'b1, BLK_2A);
        push_b(1'b0, BLK_2B);
        chk256(b_dig, DIG_2, "SHA-256(56-byte msg) two blocks, chained");

        $display("");
        $display("LEVEL 5 : cross-validation");
        push_a(1'b1, BLK_ABC);
        push_b(1'b1, BLK_ABC);
        checks = checks + 1;
        if (a_dig === b_dig)
            $display("  [PASS]  Config A and Config B produce identical digests");
        else begin
            $display("  [FAIL]  A = %064h", a_dig);
            $display("          B = %064h", b_dig);
            errors = errors + 1;
        end

        $display("");
        $display("LEVEL 6 : cycle counts per 512-bit block");
        checks = checks + 1;
        $display("          Config A : %0d cycles", a_cycles);
        $display("          Config B : %0d cycles", b_cycles);
        if (a_cycles == 66 && b_cycles == 34)
            $display("  [PASS]  66 vs 34 cycles as designed (1.94x fewer cycles)");
        else begin
            $display("  [FAIL]  expected 66 and 34");
            errors = errors + 1;
        end

        $display("");
        $display("==========================================================================");
        $display(" CHECKS RUN : %0d      FAILURES : %0d", checks, errors);
        if (errors == 0)
            $display(" RESULT     : ALL CHECKS PASSED");
        else
            $display(" RESULT     : FAILURES PRESENT");
        $display("==========================================================================");
        $display("");
        $finish;
    end

    initial begin
        $dumpfile("sim/tb_sha256.vcd");
        $dumpvars(0, tb_sha256);
    end

    initial begin
        #500000;
        $display("  [FAIL]  TIMEOUT");
        $finish;
    end

endmodule
