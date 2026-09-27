`timescale 1ns/1ps

module instruction_decoder_tb;

    reg  [15:0] instruction;
    wire [3:0]  opcode, dest, src_a, src_b;
    wire        write_enable;
    wire        is_mul, is_div;
    wire        use_cla;

    instruction_decoder uut(
        .instruction(instruction),
        .opcode(opcode),
        .dest(dest),
        .src_a(src_a),
        .src_b(src_b),
        .write_enable(write_enable),
        .is_mul(is_mul),
        .is_div(is_div),
        .use_cla(use_cla)
    );

    task check;
        input [15:0]     instr;
        input [3:0]      exp_op;
        input [3:0]      exp_dest;
        input [3:0]      exp_a;
        input [3:0]      exp_b;
        input            exp_we;
        input            exp_mul;
        input            exp_div;
        input            exp_cla;
        input [8*35-1:0] label;
        begin
            instruction = instr;
            #10;
            if (opcode       === exp_op   &&
                dest         === exp_dest &&
                src_a        === exp_a    &&
                src_b        === exp_b    &&
                write_enable === exp_we   &&
                is_mul       === exp_mul  &&
                is_div       === exp_div  &&
                use_cla      === exp_cla)
                $display("PASS | %-35s | op=%04b d=%0d a=%0d b=%0d we=%0b mul=%0b div=%0b cla=%0b",
                          label, opcode, dest, src_a, src_b,
                          write_enable, is_mul, is_div, use_cla);
            else
                $display("FAIL | %-35s | op=%04b d=%0d a=%0d b=%0d we=%0b mul=%0b div=%0b cla=%0b",
                          label, opcode, dest, src_a, src_b,
                          write_enable, is_mul, is_div, use_cla);
        end
    endtask

    initial begin
        $dumpfile("instruction_decoder.vcd");
        $dumpvars(0, instruction_decoder_tb);

        // ── Field decoding tests ──────────────────────────────

        // ADD R3, R1, R2
        // opcode=0000 dest=3 srcA=1 srcB=2
        // we=1 mul=0 div=0 cla=1
        check(16'b0000_0011_0001_0010,
              4'b0000, 3, 1, 2, 1, 0, 0, 1,
              "ADD R3,R1,R2");

        // SUB R4, R3, R1
        // opcode=0001 dest=4 srcA=3 srcB=1
        // we=1 mul=0 div=0 cla=1
        check(16'b0001_0100_0011_0001,
              4'b0001, 4, 3, 1, 1, 0, 0, 1,
              "SUB R4,R3,R1");

        // MUL R5, R2, R3
        // opcode=1011 dest=5 srcA=2 srcB=3
        // we=1 mul=1 div=0 cla=0
        check(16'b1011_0101_0010_0011,
              4'b1011, 5, 2, 3, 1, 1, 0, 0,
              "MUL R5,R2,R3");

        // DIV R6, R4, R2
        // opcode=1100 dest=6 srcA=4 srcB=2
        // we=0 mul=0 div=1 cla=0
        check(16'b1100_0110_0100_0010,
              4'b1100, 6, 4, 2, 0, 0, 1, 0,
              "DIV R6,R4,R2 no writeback");

        // CMP R0, R1, R2
        // opcode=1101 dest=0 srcA=1 srcB=2
        // we=0 mul=0 div=0 cla=0
        check(16'b1101_0000_0001_0010,
              4'b1101, 0, 1, 2, 0, 0, 0, 0,
              "CMP R0,R1,R2 no writeback");

        // AND R7, R5, R6
        // opcode=0101 dest=7 srcA=5 srcB=6
        // we=1 mul=0 div=0 cla=0
        check(16'b0101_0111_0101_0110,
              4'b0101, 7, 5, 6, 1, 0, 0, 0,
              "AND R7,R5,R6");

        // OR R8, R0, R1
        // opcode=0110 dest=8 srcA=0 srcB=1
        // we=1 mul=0 div=0 cla=0
        check(16'b0110_1000_0000_0001,
              4'b0110, 8, 0, 1, 1, 0, 0, 0,
              "OR R8,R0,R1");

        // SHL R9, R1, R1
        // opcode=1001 dest=9 srcA=1 srcB=1
        // we=1 mul=0 div=0 cla=0
        check(16'b1001_1001_0001_0001,
              4'b1001, 9, 1, 1, 1, 0, 0, 0,
              "SHL R9,R1,R1");

        // SHR R10, R2, R2
        // opcode=1010 dest=10 srcA=2 srcB=2
        // we=1 mul=0 div=0 cla=0
        check(16'b1010_1010_0010_0010,
              4'b1010, 10, 2, 2, 1, 0, 0, 0,
              "SHR R10,R2,R2");

        // NOT R11, R3, R3
        // opcode=1000 dest=11 srcA=3 srcB=3
        // we=1 mul=0 div=0 cla=0
        check(16'b1000_1011_0011_0011,
              4'b1000, 11, 3, 3, 1, 0, 0, 0,
              "NOT R11,R3,R3");

        // INC R12, R0, R0
        // opcode=0010 dest=12 srcA=0 srcB=0
        // we=1 mul=0 div=0 cla=0
        check(16'b0010_1100_0000_0000,
              4'b0010, 12, 0, 0, 1, 0, 0, 0,
              "INC R12,R0,R0");

        // DEC R13, R1, R1
        // opcode=0011 dest=13 srcA=1 srcB=1
        // we=1 mul=0 div=0 cla=0
        check(16'b0011_1101_0001_0001,
              4'b0011, 13, 1, 1, 1, 0, 0, 0,
              "DEC R13,R1,R1");

        // ── write_enable verification ─────────────────────────
        $display("--- write_enable check ---");

        // Only CMP and DIV should have write_enable=0
        instruction = 16'b1101_0000_0000_0000; #10; // CMP
        $display("CMP  write_enable=%0b (expect 0)", write_enable);

        instruction = 16'b1100_0000_0000_0000; #10; // DIV
        $display("DIV  write_enable=%0b (expect 0)", write_enable);

        instruction = 16'b0000_0000_0000_0000; #10; // ADD
        $display("ADD  write_enable=%0b (expect 1)", write_enable);

        instruction = 16'b0001_0000_0000_0000; #10; // SUB
        $display("SUB  write_enable=%0b (expect 1)", write_enable);

        instruction = 16'b1011_0000_0000_0000; #10; // MUL
        $display("MUL  write_enable=%0b (expect 1)", write_enable);

        // ── is_mul and is_div verification ───────────────────
        $display("--- is_mul and is_div check ---");

        instruction = 16'b1011_0000_0000_0000; #10; // MUL
        $display("MUL  is_mul=%0b is_div=%0b (expect 1 0)",
                  is_mul, is_div);

        instruction = 16'b1100_0000_0000_0000; #10; // DIV
        $display("DIV  is_mul=%0b is_div=%0b (expect 0 1)",
                  is_mul, is_div);

        instruction = 16'b0000_0000_0000_0000; #10; // ADD
        $display("ADD  is_mul=%0b is_div=%0b (expect 0 0)",
                  is_mul, is_div);

        // ── use_cla verification ──────────────────────────────
        $display("--- use_cla check ---");

        instruction = 16'b0000_0000_0000_0000; #10; // ADD
        $display("ADD  use_cla=%0b (expect 1)", use_cla);

        instruction = 16'b0001_0000_0000_0000; #10; // SUB
        $display("SUB  use_cla=%0b (expect 1)", use_cla);

        instruction = 16'b1011_0000_0000_0000; #10; // MUL
        $display("MUL  use_cla=%0b (expect 0)", use_cla);

        instruction = 16'b0101_0000_0000_0000; #10; // AND
        $display("AND  use_cla=%0b (expect 0)", use_cla);

        $display("Instruction decoder testbench complete");
        $finish;
    end

endmodule