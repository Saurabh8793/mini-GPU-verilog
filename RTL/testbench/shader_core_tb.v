`timescale 1ns/1ps

module shader_core_tb;

    reg        clk, reset;
    reg        instr_valid;
    reg [15:0] instruction;
    reg [1:0]  acc_ctrl;
    reg        load_en;
    reg  [3:0] load_addr;
    reg  [7:0] load_data;
    reg        div_start;

    wire [7:0] result_out;
    wire [7:0] mul_result_high;
    wire [7:0] acc_out;
    wire       zero_flag, carry_flag;
    wire       negative_flag, overflow_flag;
    wire       div_done, div_by_zero;

    shader_core #(.CORE_ID(0)) uut(
        .clk(clk), .reset(reset),
        .instr_valid(instr_valid),
        .instruction(instruction),
        .acc_ctrl(acc_ctrl),
        .load_en(load_en),
        .load_addr(load_addr),
        .load_data(load_data),
        .div_start(div_start),
        .div_done(div_done),
        .div_by_zero(div_by_zero),
        .result_out(result_out),
        .mul_result_high(mul_result_high),
        .acc_out(acc_out),
        .zero_flag(zero_flag),
        .carry_flag(carry_flag),
        .negative_flag(negative_flag),
        .overflow_flag(overflow_flag)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Load value directly into register file
    task load_reg;
        input [3:0] addr;
        input [7:0] data;
        begin
            load_en   = 1;
            load_addr = addr;
            load_data = data;
            acc_ctrl  = 2'b00;
            instr_valid = 0;
            @(posedge clk);
            load_en = 0;
            @(posedge clk);
        end
    endtask

    // Execute one instruction with explicit acc_ctrl
    task execute;
        input [15:0]     instr;
        input [1:0]      ctrl;
        input [8*35-1:0] label;
        begin
            instr_valid = 1;
            instruction = instr;
            acc_ctrl    = ctrl;
            @(posedge clk);
            instr_valid = 0;
            acc_ctrl    = 2'b00;
            @(posedge clk);
            #1;
            $display("%-35s | result=%0d acc=%0d z=%0b c=%0b n=%0b",
                      label, result_out, acc_out,
                      zero_flag, carry_flag, negative_flag);
        end
    endtask

    initial begin
        $dumpfile("shader_core.vcd");
        $dumpvars(0, shader_core_tb);

        reset=1; instr_valid=0; load_en=0;
        div_start=0; acc_ctrl=2'b00;
        instruction=0; load_addr=0; load_data=0;
        repeat(3) @(posedge clk);
        reset=0;

        // ── Test 1: ADD, accumulator held ────────────────────
        $display("--- Test 1: ADD R3=R1+R2, acc HOLD ---");
        load_reg(4'd1, 8'd10);   // R1 = 10
        load_reg(4'd2, 8'd20);   // R2 = 20
        // ADD R3,R1,R2 → opcode=0000 dest=3 srcA=1 srcB=2
        execute(16'b0000_0011_0001_0010, 2'b00,
                "ADD R3=R1+R2=30 acc HOLD");
        // R3 = 30, acc unchanged

        // ── Test 2: SUB ──────────────────────────────────────
        $display("--- Test 2: SUB R4=R3-R1 ---");
        // SUB R4,R3,R1 → opcode=0001 dest=4 srcA=3 srcB=1
        execute(16'b0001_0100_0011_0001, 2'b00,
                "SUB R4=R3-R1=20");
        // R4 = 30-10 = 20

        // ── Test 3: AND ──────────────────────────────────────
        $display("--- Test 3: AND R5=R1&R2 ---");
        load_reg(4'd1, 8'hFF);
        load_reg(4'd2, 8'h0F);
        // AND R5,R1,R2 → opcode=0101 dest=5 srcA=1 srcB=2
        execute(16'b0101_0101_0001_0010, 2'b00,
                "AND R5=FF&0F=0F");

        // ── Test 4: OR ───────────────────────────────────────
        $display("--- Test 4: OR R6=R1|R2 ---");
        load_reg(4'd1, 8'hF0);
        load_reg(4'd2, 8'h0F);
        // OR R6,R1,R2 → opcode=0110 dest=6 srcA=1 srcB=2
        execute(16'b0110_0110_0001_0010, 2'b00,
                "OR R6=F0|0F=FF");

        // ── Test 5: MUL, check upper 8 bits ──────────────────
        $display("--- Test 5: MUL check both halves ---");
        load_reg(4'd1, 8'd20);
        load_reg(4'd2, 8'd15);
        // MUL R7,R1,R2 → opcode=1011 dest=7 srcA=1 srcB=2
        // 20x15=300, low=300%256=44, high=300/256=1
        execute(16'b1011_0111_0001_0010, 2'b00,
                "MUL R7=20x15=300");
        #1;
        $display("     result_low=%0d mul_high=%0d (300: low=44 high=1)",
                  result_out, mul_result_high);
        if (result_out === 8'd44 && mul_result_high === 8'd1)
            $display("PASS | MUL 20x15 both halves correct");
        else
            $display("FAIL | MUL 20x15 got low=%0d high=%0d",
                      result_out, mul_result_high);

        // ── Test 6: SHL ──────────────────────────────────────
        $display("--- Test 6: SHL ---");
        load_reg(4'd1, 8'b00000101);
        load_reg(4'd2, 8'b00000000);
        // SHL R8,R1,R1 → opcode=1001 dest=8 srcA=1 srcB=1
        execute(16'b1001_1000_0001_0001, 2'b00,
                "SHL R8=00000101 left");
        // expect 00001010 = 10

        // ── Test 7: Zero flag ─────────────────────────────────
        $display("--- Test 7: Zero flag ---");
        load_reg(4'd1, 8'd7);
        load_reg(4'd2, 8'd7);
        // SUB R9,R1,R2 → opcode=0001 dest=9 srcA=1 srcB=2
        execute(16'b0001_1001_0001_0010, 2'b00,
                "SUB R9=7-7=0 zero flag");
        if (zero_flag === 1'b1)
            $display("PASS | zero_flag correct");
        else
            $display("FAIL | zero_flag=%0b expected 1", zero_flag);

        // ── Test 8: Negative flag ─────────────────────────────
        $display("--- Test 8: Negative flag ---");
        load_reg(4'd1, 8'd3);
        load_reg(4'd2, 8'd10);
        // SUB R10,R1,R2 → opcode=0001 dest=10 srcA=1 srcB=2
        execute(16'b0001_1010_0001_0010, 2'b00,
                "SUB R10=3-10 negative");
        if (negative_flag === 1'b1)
            $display("PASS | negative_flag correct");
        else
            $display("FAIL | negative_flag=%0b expected 1", negative_flag);

        // ── Test 9: acc_ctrl gating ───────────────────────────
        // When instr_valid=0, acc should HOLD even if acc_ctrl=ADD
        $display("--- Test 9: acc_ctrl gating test ---");
        // First load known value into acc
        load_reg(4'd1, 8'd5);
        load_reg(4'd2, 8'd5);
        execute(16'b0000_0011_0001_0010, 2'b01,
                "ADD R3=5+5=10 acc LOAD");
        $display("     acc after LOAD=%0d (expect 10)", acc_out);

        // Now assert acc_ctrl=ADD but instr_valid=0
        // acc should not change
        instr_valid = 0;
        acc_ctrl    = 2'b10;   // ADD mode
        @(posedge clk); #1;
        acc_ctrl = 2'b00;
        $display("     acc after invalid+ADD=%0d (expect 10 unchanged)",
                  acc_out);
        if (acc_out === 8'd10)
            $display("PASS | acc correctly held when instr_valid=0");
        else
            $display("FAIL | acc changed to %0d should be 10", acc_out);

        // ── Test 10: Dot product 2x3 + 4x5 + 1x7 = 33 ───────
        $display("--- Test 10: Dot product ---");

        // Clear accumulator
        instr_valid=0; acc_ctrl=2'b11;
        @(posedge clk); acc_ctrl=2'b00; @(posedge clk);
        $display("CLEAR acc=%0d (expect 0)", acc_out);

        // MUL 2x3=6, LOAD into acc
        load_reg(4'd0, 8'd2);
        load_reg(4'd1, 8'd3);
        // MUL R2,R0,R1 → opcode=1011 dest=2 srcA=0 srcB=1
        execute(16'b1011_0010_0000_0001, 2'b01,
                "MUL R2=2x3=6 acc LOAD");
        $display("     acc=%0d (expect 6)", acc_out);

        // MUL 4x5=20, ADD to acc
        load_reg(4'd0, 8'd4);
        load_reg(4'd1, 8'd5);
        // MUL R3,R0,R1 → opcode=1011 dest=3 srcA=0 srcB=1
        execute(16'b1011_0011_0000_0001, 2'b10,
                "MUL R3=4x5=20 acc ADD");
        $display("     acc=%0d (expect 26)", acc_out);

        // MUL 1x7=7, ADD to acc
        load_reg(4'd0, 8'd1);
        load_reg(4'd1, 8'd7);
        // MUL R4,R0,R1 → opcode=1011 dest=4 srcA=0 srcB=1
        execute(16'b1011_0100_0000_0001, 2'b10,
                "MUL R4=1x7=7 acc ADD");
        $display("     acc=%0d (expect 33)", acc_out);

        if (acc_out === 8'd33)
            $display("PASS | Dot product 2x3+4x5+1x7 = 33");
        else
            $display("FAIL | Dot product got %0d expected 33", acc_out);

        $display("--- Shader core testbench complete ---");
        $finish;
    end

endmodule