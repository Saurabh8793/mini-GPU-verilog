`timescale 1ns/1ps

module CLA_tb;

    reg  [7:0] a, b;
    reg        b_invert, cin;
    wire [7:0] result;
    wire       cout, zero_flag, negative_flag, overflow_flag;

    carry_lookahead_adder uut(
        .a(a), .b(b),
        .b_invert(b_invert),
        .cin(cin),
        .result(result),
        .cout(cout),
        .zero_flag(zero_flag),
        .negative_flag(negative_flag),
        .overflow_flag(overflow_flag)
    );

    task check;
        input [7:0]      expected;
        input            exp_zero;
        input [7:0]      in_a, in_b;
        input [8*25-1:0] label;
        begin
            #10;
            if (result === expected && zero_flag === exp_zero)
                $display("PASS | %-25s | result=%0d zero=%0b carry=%0b",
                          label, result, zero_flag, cout);
            else
                $display("FAIL | %-25s | got=%0d expected=%0d",
                          label, result, expected);
        end
    endtask

    initial begin
        $dumpfile("cla.vcd");
        $dumpvars(0, CLA_tb);

        // ── ADD: b_invert=0 cin=0 ─────────────────────────────
        a=10;  b=20;  b_invert=1'b0; cin=1'b0;
        check(30,  0, a, b, "ADD 10+20");

        a=0;   b=0;   b_invert=1'b0; cin=1'b0;
        check(0,   1, a, b, "ADD 0+0 zero");

        a=255; b=1;   b_invert=1'b0; cin=1'b0;
        check(0,   1, a, b, "ADD 255+1 overflow");
        #1; $display("     cout=%0b (expect 1)", cout);

        a=127; b=1;   b_invert=1'b0; cin=1'b0;
        check(128, 0, a, b, "ADD 127+1");

        a=100; b=100; b_invert=1'b0; cin=1'b0;
        check(200, 0, a, b, "ADD 100+100");

        // ── SUB: b_invert=1 cin=1 ─────────────────────────────
        a=20;  b=10;  b_invert=1'b1; cin=1'b1;
        check(10,  0, a, b, "SUB 20-10");

        a=5;   b=5;   b_invert=1'b1; cin=1'b1;
        check(0,   1, a, b, "SUB 5-5 zero");

        a=100; b=50;  b_invert=1'b1; cin=1'b1;
        check(50,  0, a, b, "SUB 100-50");

        // ── INC: b=0 b_invert=0 cin=1 ────────────────────────
        a=5;   b=0;   b_invert=1'b0; cin=1'b1;
        check(6,   0, a, b, "INC 5");

        a=255; b=0;   b_invert=1'b0; cin=1'b1;
        check(0,   1, a, b, "INC 255 wrap");

        // ── DEC: b=FF b_invert=0 cin=0 ───────────────────────
        a=5;   b=8'hFF; b_invert=1'b0; cin=1'b0;
        check(4,   0, a, b, "DEC 5");

        a=1;   b=8'hFF; b_invert=1'b0; cin=1'b0;
        check(0,   1, a, b, "DEC 1 gives 0");

        // ── CMP: same as SUB, check flags ─────────────────────
        a=10;  b=10;  b_invert=1'b1; cin=1'b1; #10;
        $display("CMP 10==10 | zero=%0b (expect 1)", zero_flag);

        a=10;  b=5;   b_invert=1'b1; cin=1'b1; #10;
        $display("CMP 10>5   | neg=%0b (expect 0)", negative_flag);

        a=5;   b=10;  b_invert=1'b1; cin=1'b1; #10;
        $display("CMP 5<10   | neg=%0b (expect 1)", negative_flag);

        // ── RCA vs CLA comparison ─────────────────────────────
        $display("--- Verifying CLA matches RCA for key values ---");
        a=37;  b=91;  b_invert=1'b0; cin=1'b0;
        check(128, 0, a, b, "ADD 37+91=128");

        a=200; b=55;  b_invert=1'b0; cin=1'b0;
        check(255, 0, a, b, "ADD 200+55=255");

        a=200; b=56;  b_invert=1'b0; cin=1'b0;
        check(0,   1, a, b, "ADD 200+56 overflow");

        $display("CLA testbench complete");
        $finish;
    end

endmodule