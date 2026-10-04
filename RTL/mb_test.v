`timescale 1ns/1ps
// ============================================================
// Smoke test for signed_multiplier_16x16
// Verifies key cases: positive, negative, mixed, zero
// ============================================================
module mul16_test;
    reg signed [15:0] a, b;
    wire signed [31:0] product;

    signed_multiplier_16x16 dut (.a(a), .b(b), .product(product));

    // Expected: behavioral reference
    wire signed [31:0] expected = a * b;
    wire pass = (product === expected);

    integer fails = 0;
    integer tests = 0;

    task check;
        input signed [15:0] ta, tb;
        input signed [31:0] exp;
        begin
            a = ta; b = tb;
            #10; // let combinational settle
            tests = tests + 1;
            if (product !== exp) begin
                $display("FAIL: %0d * %0d = %0d (got %0d)", ta, tb, exp, product);
                fails = fails + 1;
            end else begin
                $display("PASS: %0d * %0d = %0d", ta, tb, product);
            end
        end
    endtask

    initial begin
        // ── Basic positive ─────────────────────────────────
        check( 16'sd256,   16'sd256,   32'sd65536);  //  1.0 *  1.0 =  1.0 (Q16.16: 65536)
        check( 16'sd512,   16'sd256,   32'sd131072); //  2.0 *  1.0 =  2.0
        check( 16'sd128,   16'sd256,   32'sd32768);  //  0.5 *  1.0 =  0.5
        check( 16'sd256,   16'sd128,   32'sd32768);  //  1.0 *  0.5 =  0.5

        // ── Negative inputs ────────────────────────────────
        check(-16'sd256,   16'sd256,  -32'sd65536);  // -1.0 *  1.0 = -1.0
        check( 16'sd256,  -16'sd256,  -32'sd65536);  //  1.0 * -1.0 = -1.0
        check(-16'sd256,  -16'sd256,   32'sd65536);  // -1.0 * -1.0 =  1.0
        check(-16'sd512,   16'sd256,  -32'sd131072); // -2.0 *  1.0 = -2.0

        // ── Zero ──────────────────────────────────────────
        check( 16'sd0,     16'sd256,   32'sd0);
        check( 16'sd256,   16'sd0,     32'sd0);
        check( 16'sd0,     16'sd0,     32'sd0);

        // ── Q8.8 Mandelbrot-realistic values ─────────────
        // c_real = -512 (-2.0), z_real = 256 (1.0)
        check(-16'sd512,   16'sd256,  -32'sd131072);
        // z_real = 320 (1.25)
        check( 16'sd320,   16'sd320,   32'sd102400); // 1.25^2 * 65536
        // z_real = -320, z_imag = 256
        check(-16'sd320,   16'sd256,  -32'sd81920);

        $display("--------------------------------------------");
        $display("Results: %0d / %0d passed", tests-fails, tests);
        if (fails == 0)
            $display("ALL TESTS PASSED - structural multiplier is correct");
        else
            $display("FAILURES: %0d", fails);
        $finish;
    end
endmodule
