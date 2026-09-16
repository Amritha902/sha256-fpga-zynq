//============================================================================
//  tb_sha256_soak.v  —  per-round trace comparison and multi-message soak
//----------------------------------------------------------------------------
//  Closes the two verification gaps left open in the README:
//
//    LEVEL A : compare the working variables a..h against the golden model
//              at EVERY one of the 64 rounds, not just at the digest.
//              A wrong Sigma constant or a schedule off-by-one shows up at
//              the exact round it occurs, instead of as a mystery digest.
//
//    LEVEL B : soak test across 12 messages of varying length, including the
//              55/56/63/64/65-byte cases that sit either side of the padding
//              boundary -- historically where hash implementations break.
//
//  Both configurations are exercised.
//
//  Run:  make soak
//============================================================================
`timescale 1ns / 1ps

module tb_sha256_soak;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    //=========================================================================
    //  Golden data loaded from the Python model
    //=========================================================================
    reg [31:0]  gold_w    [0:63];    // W[t] for the "abc" block
    reg [255:0] gold_vars [0:63];    // {a,b,c,d,e,f,g,h} BEFORE round t

    reg [511:0] soak_blk  [0:25];    // concatenated blocks for all messages
    reg [7:0]   soak_n    [0:11];    // block count per message
    reg [255:0] soak_dig  [0:11];    // expected digest per message

    localparam NUM_MSGS = 12;

    initial begin
        $readmemh("model/trace_w.mem",      gold_w);
        $readmemh("model/trace_vars.mem",   gold_vars);
        $readmemh("model/soak_blocks.mem",  soak_blk);
        $readmemh("model/soak_nblocks.mem", soak_n);
        $readmemh("model/soak_digests.mem", soak_dig);
    end

    //=========================================================================
    //  Devices under test
    //=========================================================================
    reg          a_bv = 0, a_init = 0;
    reg  [511:0] a_blk = 0;
    wire         a_ready, a_dv;
    wire [255:0] a_dig;

    sha256_core_iter u_A (
        .clk(clk), .rst_n(rst_n),
        .block_valid(a_bv), .init(a_init), .block_in(a_blk), .ready(a_ready),
        .digest_valid(a_dv), .digest(a_dig)
    );

    reg          b_bv = 0, b_init = 0;
    reg  [511:0] b_blk = 0;
    wire         b_ready, b_dv;
    wire [255:0] b_dig;

    sha256_core_unroll2 u_B (
        .clk(clk), .rst_n(rst_n),
        .block_valid(b_bv), .init(b_init), .block_in(b_blk), .ready(b_ready),
        .digest_valid(b_dv), .digest(b_dig)
    );

    //=========================================================================
    //  LEVEL A — per-round trace comparison against the golden model
    //
    //  Config A executes exactly one round per cycle while in S_ROUND, so
    //  sampling {a..hh} at each S_ROUND clock edge gives the state at the
    //  top of round t.  That is precisely what trace_vars.mem records.
    //=========================================================================
    integer round_mismatches;
    integer w_mismatches;

    //  Sampling phase matters here.  The registers update ON the positive
    //  edge, so the value held DURING round t (i.e. before that round's
    //  update) is what is stable at the NEGATIVE edge of the same cycle.
    //  Keying off the core's own round counter u_A.t removes any need to
    //  guess how many cycles the load phase took.
    task check_round_trace;
        integer seen;
        integer idx;
        reg [255:0] got;
        begin
            round_mismatches = 0;
            w_mismatches     = 0;
            seen             = 0;

            //  Drive on the NEGATIVE edge.  Driving on the positive edge
            //  races with the DUT's own always @(posedge clk) block, and the
            //  core can latch block_valid a cycle early -- which silently
            //  shifts the whole trace by one round.
            wait (a_ready);
            @(negedge clk);
            a_blk  = soak_blk[1];        // message 1 = "abc", its only block
            a_init = 1'b1;
            a_bv   = 1'b1;
            @(posedge clk);              // core loads W and a..h here
            @(negedge clk);
            a_bv   = 1'b0;               // state = S_ROUND, t = 0, w[0] = W[0]

            while (seen < 64) begin
                if (u_A.state == 2'd1) begin          // S_ROUND
                    idx = u_A.t;
                    got = {u_A.a, u_A.b, u_A.c, u_A.d,
                           u_A.e, u_A.f, u_A.g, u_A.hh};

                    if (got !== gold_vars[idx]) begin
                        if (round_mismatches < 3) begin
                            $display("  [FAIL]  round %0d working variables differ", idx);
                            $display("            got      %064h", got);
                            $display("            expected %064h", gold_vars[idx]);
                        end
                        round_mismatches = round_mismatches + 1;
                    end

                    if (u_A.w[0] !== gold_w[idx]) begin
                        if (w_mismatches < 3)
                            $display("  [FAIL]  round %0d W = %08h, expected %08h",
                                     idx, u_A.w[0], gold_w[idx]);
                        w_mismatches = w_mismatches + 1;
                    end

                    seen = seen + 1;
                end
                @(negedge clk);
            end

            wait (a_dv);
            @(posedge clk);

            checks = checks + 1;
            if (round_mismatches == 0)
                $display("  [PASS]  working variables a..h match at all 64 rounds");
            else begin
                $display("  [FAIL]  %0d of 64 rounds mismatched", round_mismatches);
                errors = errors + 1;
            end

            checks = checks + 1;
            if (w_mismatches == 0)
                $display("  [PASS]  message schedule W[t] matches at all 64 rounds");
            else begin
                $display("  [FAIL]  %0d of 64 schedule words mismatched", w_mismatches);
                errors = errors + 1;
            end
        end
    endtask

    //=========================================================================
    //  LEVEL B — soak across messages of varying length
    //=========================================================================
    task run_msg_A;
        input integer first_blk;
        input integer nblk;
        integer i;
        begin
            for (i = 0; i < nblk; i = i + 1) begin
                wait (a_ready);
                @(negedge clk);
                a_blk  = soak_blk[first_blk + i];
                a_init = (i == 0);
                a_bv   = 1'b1;
                @(posedge clk);
                @(negedge clk);
                a_bv   = 1'b0;
                wait (a_dv);
                @(negedge clk);
            end
        end
    endtask

    task run_msg_B;
        input integer first_blk;
        input integer nblk;
        integer i;
        begin
            for (i = 0; i < nblk; i = i + 1) begin
                wait (b_ready);
                @(negedge clk);
                b_blk  = soak_blk[first_blk + i];
                b_init = (i == 0);
                b_bv   = 1'b1;
                @(posedge clk);
                @(negedge clk);
                b_bv   = 1'b0;
                wait (b_dv);
                @(negedge clk);
            end
        end
    endtask

    task soak;
        integer m, base, nb, bad_a, bad_b, bad_x;
        begin
            base  = 0;
            bad_a = 0;  bad_b = 0;  bad_x = 0;

            for (m = 0; m < NUM_MSGS; m = m + 1) begin
                nb = soak_n[m];

                run_msg_A(base, nb);
                run_msg_B(base, nb);

                if (a_dig !== soak_dig[m]) begin
                    $display("  [FAIL]  msg %0d (%0d blk) Config A digest wrong", m, nb);
                    $display("            got      %064h", a_dig);
                    $display("            expected %064h", soak_dig[m]);
                    bad_a = bad_a + 1;
                end
                if (b_dig !== soak_dig[m]) begin
                    $display("  [FAIL]  msg %0d (%0d blk) Config B digest wrong", m, nb);
                    bad_b = bad_b + 1;
                end
                if (a_dig !== b_dig) bad_x = bad_x + 1;

                base = base + nb;
            end

            checks = checks + 1;
            if (bad_a == 0)
                $display("  [PASS]  Config A correct on all %0d messages", NUM_MSGS);
            else begin
                $display("  [FAIL]  Config A wrong on %0d messages", bad_a);
                errors = errors + 1;
            end

            checks = checks + 1;
            if (bad_b == 0)
                $display("  [PASS]  Config B correct on all %0d messages", NUM_MSGS);
            else begin
                $display("  [FAIL]  Config B wrong on %0d messages", bad_b);
                errors = errors + 1;
            end

            checks = checks + 1;
            if (bad_x == 0)
                $display("  [PASS]  A and B agree on every message");
            else begin
                $display("  [FAIL]  A and B disagreed on %0d messages", bad_x);
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
        $display(" SHA-256 TRACE AND SOAK VERIFICATION");
        $display("==========================================================================");

        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("");
        $display("LEVEL A : per-round comparison against the golden model");
        check_round_trace();

        $display("");
        $display("LEVEL B : soak across %0d messages", NUM_MSGS);
        $display("          lengths include 55, 56, 63, 64 and 65 bytes --");
        $display("          the padding-boundary cases that break most designs");
        soak();

        $display("");
        $display("==========================================================================");
        $display(" CHECKS RUN : %0d      FAILURES : %0d", checks, errors);
        if (errors == 0)
            $display(" RESULT     : ALL TRACE AND SOAK CHECKS PASSED");
        else
            $display(" RESULT     : FAILURES PRESENT");
        $display("==========================================================================");
        $display("");
        $finish;
    end

    initial begin
        #3000000;
        $display("  [FAIL]  TIMEOUT");
        $finish;
    end

endmodule
