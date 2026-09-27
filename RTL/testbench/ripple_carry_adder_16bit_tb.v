`timescale 1ns/1ps

module ripple_carry_adder_16bit_tb;

    reg  [15:0] a, b;
    reg         b_invert, cin;
    wire [15:0] result;
    wire        cout, zero_flag, negative_flag, overflow_flag;

    ripple_carry_adder_16bit uut(
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
        input [15:0] expected;
        input [15:0] in_a, in_b;
        input [8*20-1:0] label;
        begin
            #10;
            if (result === expected)
                $display("PASS | %-20s | %0d", label, result);
            else
                $display("FAIL | %-20s | got=%0d expected=%0d",
                          label, result, expected);
        end
    endtask

    initial begin
        $dumpfile("rca16.vcd");
        $dumpvars(0, ripple_carry_adder_16bit_tb);

        // ADD tests
        a=100;   b=200;   b_invert=0; cin=0;
        check(300,   100,  200,  "ADD 100+200");

        a=1000;  b=2000;  b_invert=0; cin=0;
        check(3000,  1000, 2000, "ADD 1000+2000");

        a=65535; b=1;     b_invert=0; cin=0;
        check(0, 65535, 1, "ADD 65535+1 overflow");
        #1; $display("     cout=%0b (expect 1)", cout);

        a=0;     b=0;     b_invert=0; cin=0;
        check(0, 0, 0, "ADD 0+0 zero flag");
        #1; $display("     zero=%0b (expect 1)", zero_flag);

        // SUB tests
        a=5000;  b=2000;  b_invert=1; cin=1;
        check(3000, 5000, 2000, "SUB 5000-2000");

        a=1000;  b=1000;  b_invert=1; cin=1;
        check(0, 1000, 1000, "SUB 1000-1000 zero");
        #1; $display("     zero=%0b (expect 1)", zero_flag);

        // Large values — critical for multiplier
        a=16'hFF00; b=16'h00FF; b_invert=0; cin=0;
        check(16'hFFFF, 16'hFF00, 16'h00FF, "ADD FF00+00FF");

        a=16'hAAAA; b=16'h5555; b_invert=0; cin=0;
        check(16'hFFFF, 16'hAAAA, 16'h5555, "ADD AAAA+5555");

        $display("16-bit RCA tests complete");
        $finish;
    end
endmodule