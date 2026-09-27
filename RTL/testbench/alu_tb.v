`timescale 1ns/1ps

module alu_tb;

    reg clk, reset;
    reg [3:0] opcode;
    reg use_cla;
    reg [7:0] a, b;
    reg start;
    
    wire [7:0] result;
    wire [7:0] mul_result_high;
    wire [7:0] div_remainder;
    wire zero_flag, carry_flag;
    wire negative_flag, overflow_flag;
    wire done, div_by_zero;

    alu uut(
        .clk(clk), .reset(reset),
        .opcode(opcode), .use_cla(use_cla),
        .a(a), .b(b),
        .start(start), .done(done),
        .div_by_zero(div_by_zero),
        .result(result),
        .mul_result_high(mul_result_high),
        .div_remainder(div_remainder),
        .zero_flag(zero_flag),
        .carry_flag(carry_flag),
        .negative_flag(negative_flag),
        .overflow_flag(overflow_flag)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Task for combinational operations
    task test_op;
        input [3:0] op;
        input cla;
        input [7:0] in_a, in_b;
        input [7:0] expected;
        input [8*25-1:0] label;
        begin
            use_cla = cla;
            a = in_a;
            b = in_b;
            start = 1'b0;
            #10;
            if (result === expected)
                $display("PASS | %-25s | %0d op %0d = %0d | zero=%0b carry=%0b neg=%0b",
                          label, in_a, in_b, result,
                          zero_flag, carry_flag, negative_flag);
            else
                $display("FAIL | %-25s | got=%0d expected=%0d",
                          label, result, expected);
        end
    endtask

    // Task for division
    task test_div;
        input [7:0] in_a, in_b;
        input [7:0] exp_q;
        input [7:0] exp_r;
        begin
            opcode  = 4'b1100;
            use_cla = 1'b0;
            a = in_a;
            b = in_b;
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            wait(done == 1'b1);
            @(posedge clk);
          if (div_by_zero) begin
            $display("DIV_BY_ZERO | %0d / %0d", in_a, in_b);
          end else if (result === exp_q && div_remainder === exp_r) begin
            $display("PASS | DIV %0d/%0d = q:%0d rem:%0d",
                in_a, in_b, result, div_remainder);
        end else begin
            $display("FAIL | DIV %0d/%0d = q:%0d rem:%0d | expected q:%0d rem:%0d",
                in_a, in_b, result, div_remainder, exp_q, exp_r);
end
     end
endtask


    initial begin
        $dumpfile("alu.vcd");
        $dumpvars(0, alu_tb);

        reset = 1; start = 0;
        a = 0; b = 0; opcode = 0; use_cla = 0;
        repeat(3) @(posedge clk);
        reset = 0;
        @(posedge clk);

        $display("=== ADD (RCA) ===");
        test_op(4'b0000, 0, 10,  20,  30,  "ADD 10+20 RCA");
        test_op(4'b0000, 0, 255, 1,   0,   "ADD 255+1 overflow RCA");
        test_op(4'b0000, 0, 0,   0,   0,   "ADD 0+0 zero RCA");

        $display("=== ADD (CLA) ===");
        test_op(4'b0000, 1, 10,  20,  30,  "ADD 10+20 CLA");
        test_op(4'b0000, 1, 255, 1,   0,   "ADD 255+1 overflow CLA");
        test_op(4'b0000, 1, 0,   0,   0,   "ADD 0+0 zero CLA");

        $display("=== SUB ===");
        test_op(4'b0001, 0, 20,  10,  10,  "SUB 20-10 RCA");
        test_op(4'b0001, 1, 20,  10,  10,  "SUB 20-10 CLA");
        test_op(4'b0001, 0, 5,   5,   0,   "SUB 5-5 zero");

        $display("=== INC ===");
        test_op(4'b0010, 0, 5,   0,   6,   "INC 5");
        test_op(4'b0010, 0, 255, 0,   0,   "INC 255 wrap");

        $display("=== DEC ===");
        test_op(4'b0011, 0, 5,   0,   4,   "DEC 5");
        test_op(4'b0011, 0, 0,   0,   255, "DEC 0 wrap");

        $display("=== NEG ===");
        test_op(4'b0100, 0, 5,   0,   251, "NEG 5 = 251");
        test_op(4'b0100, 0, 1,   0,   255, "NEG 1 = 255");

        $display("=== AND ===");
        test_op(4'b0101, 0, 8'hFF, 8'h0F, 8'h0F, "AND FF & 0F");
        test_op(4'b0101, 0, 8'hAA, 8'h55, 8'h00, "AND AA & 55 zero");

        $display("=== OR ===");
        test_op(4'b0110, 0, 8'hF0, 8'h0F, 8'hFF, "OR F0 | 0F");
        test_op(4'b0110, 0, 8'h00, 8'h00, 8'h00, "OR 00 | 00 zero");

        $display("=== XOR ===");
        test_op(4'b0111, 0, 8'hFF, 8'hFF, 8'h00, "XOR FF ^ FF zero");
        test_op(4'b0111, 0, 8'hAA, 8'h55, 8'hFF, "XOR AA ^ 55");

        $display("=== NOT ===");
        test_op(4'b1000, 0, 8'h00, 0, 8'hFF, "NOT 00 = FF");
        test_op(4'b1000, 0, 8'hFF, 0, 8'h00, "NOT FF = 00");

        $display("=== SHL ===");
        test_op(4'b1001, 0, 8'b00000001, 0, 8'b00000010, "SHL 1");
        test_op(4'b1001, 0, 8'b00001010, 0, 8'b00010100, "SHL 10=20");

        $display("=== SHR ===");
        test_op(4'b1010, 0, 8'b00000010, 0, 8'b00000001, "SHR 2=1");
        test_op(4'b1010, 0, 8'b00001010, 0, 8'b00000101, "SHR 10=5");

        $display("=== MUL ===");
        test_op(4'b1011, 0, 5,   6,   30,  "MUL 5x6=30");
        test_op(4'b1011, 0, 10,  10,  100, "MUL 10x10=100");
        // Large MUL — check both halves
        opcode=4'b1011; a=255; b=255; #10;
        $display("MUL 255x255 | low=%0d high=%0d full=%0d (expect 65025)",
                  result, mul_result_high,
                  {mul_result_high, result});

        $display("=== CMP ===");
        // CMP sets flags only
        opcode=4'b1101; use_cla=0; a=10; b=10; start=0; #10;
        $display("CMP 10==10 | zero=%0b (expect 1)", zero_flag);
        opcode=4'b1101; a=10; b=5; #10;
        $display("CMP 10>5   | neg=%0b (expect 0)", negative_flag);
        opcode=4'b1101; a=5; b=10; #10;
        $display("CMP 5<10   | neg=%0b (expect 1)", negative_flag);

        $display("=== DIV ===");
        test_div(20,  4,   5,  0);
        test_div(22,  4,   5,  2);
        test_div(100, 7,   14, 2);
        test_div(10,  0,   0,  0);  // div by zero

        $display("=== ALU complete ===");
        $finish;
    end

endmodule