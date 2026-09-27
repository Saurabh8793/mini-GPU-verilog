`timescale 1ns/1ps

module alu_tb;

    reg  [7:0] a, b;
    reg  [3:0] opcode;
    reg        use_cla;
    wire [7:0] result;
    wire       zero_flag, carry_flag, negative_flag, overflow_flag;

    alu uut(
        .a(a), .b(b), .opcode(opcode), .use_cla(use_cla),
        .result(result), .zero_flag(zero_flag),
        .carry_flag(carry_flag), .negative_flag(negative_flag),
        .overflow_flag(overflow_flag)
    );

    task test_both;
        input [7:0]  in_a, in_b;
        input [3:0]  op;
        input [8*20-1:0] op_name;
        reg   [7:0]  rca_res, cla_res;
        begin
            // Test with RCA
            a = in_a; b = in_b; opcode = op; use_cla = 0; #10;
            rca_res = result;

            // Test with CLA
            use_cla = 1; #10;
            cla_res = result;

            if (rca_res === cla_res)
                $display("MATCH | %-15s | RCA=%0d CLA=%0d zero=%0b carry=%0b",
                          op_name, rca_res, cla_res, zero_flag, carry_flag);
            else
                $display("MISMATCH | %-15s | RCA=%0d CLA=%0d",
                          op_name, rca_res, cla_res);
        end
    endtask

    initial begin
        $dumpfile("alu.vcd");
        $dumpvars(0, alu_tb);

        $display("=== Testing RCA vs CLA — all results must MATCH ===");

        test_both(10,  20,  4'b0000, "ADD 10+20");
        test_both(255, 1,   4'b0000, "ADD 255+1 overflow");
        test_both(20,  10,  4'b0001, "SUB 20-10");
        test_both(5,   5,   4'b0001, "SUB 5-5 zero");
        test_both(7,   0,   4'b0010, "INC 7");
        test_both(255, 0,   4'b0010, "INC 255 wrap");
        test_both(5,   0,   4'b0011, "DEC 5");
        test_both(0,   5,   4'b0100, "NEG 5");
        test_both(10,  10,  4'b1100, "CMP 10==10");
        test_both(15,  9,   4'b1100, "CMP 15>9");
        test_both(3,   8,   4'b1100, "CMP 3<8");
        test_both(5,   5,   4'b1011, "MUL 5x5");
        test_both(4,   3,   4'b1011, "MUL 4x3");

        $display("=== ALU complete ===");
        $finish;
    end
endmodule