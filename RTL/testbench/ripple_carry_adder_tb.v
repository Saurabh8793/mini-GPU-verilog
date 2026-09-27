`timescale 1ns/1ps

module ripple_carry_adder_tb;

    reg  [7:0] a, b;
    reg  b_invert, cin;
    wire [7:0] result;
    wire cout, zero_flag, negative_flag, overflow_flag;

    ripple_carry_adder uut(
        .a(a), .b(b),
        .b_invert(b_invert),
        .cin(cin),
        .result(result),
        .cout(cout),
        .zero_flag(zero_flag),
        .negative_flag(negative_flag),
        .overflow_flag(overflow_flag)
    );

    // Simple test helper: sample after signals settle, then check against expected output
    task check;
        input [7:0] expected_result;
        input expected_zero;
        input [63:0] test_name;
        begin
            #5;
            if (result === expected_result && zero_flag === expected_zero)
                $display("PASS | %s | result=%0d", test_name, result);
            else
                $display("FAIL | %s | got=%0d expected=%0d",
                          test_name, result, expected_result);
        end
    endtask

    initial begin
        $dumpfile("rca.vcd");
        $dumpvars(0, ripple_carry_adder_tb);

        // Standard addition (A + B): pass B straight through without an extra carry-in
        a=10;  b=20;  b_invert=0; cin=0; #10;
        check(30,  0, "ADD 10+20");

        a=0;   b=0;   b_invert=0; cin=0; #10;
        check(0,   1, "ADD 0+0 zero flag");

        // 8-bit wrap-around: 255 + 1 wraps to 0 with a carry-out bit set
        a=255; b=1;   b_invert=0; cin=0; #10;
        check(0,   1, "ADD 255+1 overflow");
        #1; $display("carry_out=%0b (expect 1)", cout);

        // Subtraction (A - B): invert B and assert cin to form two's complement (~B + 1)
        a=20;  b=10;  b_invert=1; cin=1; #10;
        check(10,  0, "SUB 20-10");

        a=5;   b=5;   b_invert=1; cin=1; #10;
        check(0,   1, "SUB 5-5 zero flag");

        a=100; b=50;  b_invert=1; cin=1; #10;
        check(50,  0, "SUB 100-50");

        // Increment: leave B at zero and inject a +1 carry directly via cin
        a=5;   b=0;   b_invert=0; cin=1; #10;
        check(6,   0, "INC 5");

        a=255; b=0;   b_invert=0; cin=1; #10;
        check(0,   1, "INC 255 wraps to 0");

        // Decrement: adding 0xFF (-1 in 2's complement) naturally drops the value by 1
        a=5;   b=8'hFF; b_invert=0; cin=0; #10;
        check(4,   0, "DEC 5");

        a=1;   b=8'hFF; b_invert=0; cin=0; #10;
        check(0,   1, "DEC 1 gives 0");

        // Negate: evaluate 0 - B by taking two's complement of B
        a=0;   b=5;   b_invert=1; cin=1; #10;
        check(251, 0, "NEG 5 = 251 (which is -5 in 8-bit)");

        a=0;   b=1;   b_invert=1; cin=1; #10;
        check(255, 0, "NEG 1 = 255 (which is -1 in 8-bit)");
        #1; $display("      negative_flag=%0b (expect 1)", negative_flag);

        // Magnitude compare (A vs B): runs a subtraction under the hood to evaluate condition flags
        a=10;  b=10;  b_invert=1; cin=1; #10;
        #1; $display("CMP 10==10 | zero=%0b (expect 1)", zero_flag);

        a=10;  b=5;   b_invert=1; cin=1; #10;
        #1; $display("CMP 10>5   | zero=%0b neg=%0b (expect 0,0)",
                      zero_flag, negative_flag);

        a=5;   b=10;  b_invert=1; cin=1; #10;
        #1; $display("CMP 5<10   | neg=%0b (expect 1)", negative_flag);

        // Left shift / Multiply by 2: add the register to itself (A + A)
        a=5;   b=5;   b_invert=0; cin=0; #10;
        check(10,  0, "MUL2 5x2=10");

        a=64;  b=64;  b_invert=0; cin=0; #10;
        check(128, 0, "MUL2 64x2=128");

        a=200; b=200; b_invert=0; cin=0; #10;
        #1; $display("MUL2 200x2=400 | result=%0d cout=%0b (overflow)",
                      result, cout);

        // Constant arithmetic tests
        a=10;  b=8'd7; b_invert=0; cin=0; #10;
        check(17,  0, "ADD_CONST 10+7");

        a=20;  b=8'd3; b_invert=1; cin=1; #10;
        check(17,  0, "SUB_CONST 20-3");

        
        $finish;
    end

endmodule