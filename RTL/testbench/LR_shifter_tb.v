`timescale 1ns/1ps

module LR_shifter_tb;

    reg  [7:0] a;
    reg        dir;
    wire [7:0] result;

    // Declare here — NOT inside initial block
    reg [7:0] after_shl;

    LR_shifter uut(
        .a(a),
        .dir(dir),
        .result(result)
    );

    task check;
        input [7:0] expected;
        input [7:0] in_a;
        input       in_dir;
        input [8*20-1:0] label;
        begin
            #10;
            if (result === expected)
                $display("PASS | %-25s | in=%08b out=%08b",
                          label, in_a, result);
            else
                $display("FAIL | %-25s | in=%08b got=%08b expected=%08b",
                          label, in_a, result, expected);
        end
    endtask

    initial begin
        $dumpfile("LR_shifter.vcd");
        $dumpvars(0, LR_shifter_tb);

        // ── LEFT SHIFT tests (dir=0) ──────────────────────────
        a = 8'b00000001; dir = 0;
        check(8'b00000010, a, dir, "SHL 00000001");

        a = 8'b00000010; dir = 0;
        check(8'b00000100, a, dir, "SHL 00000010");

        a = 8'b00010000; dir = 0;
        check(8'b00100000, a, dir, "SHL 00010000");

        a = 8'b01000000; dir = 0;
        check(8'b10000000, a, dir, "SHL 01000000");

        a = 8'b10000000; dir = 0;
        check(8'b00000000, a, dir, "SHL 10000000 MSB lost");

        a = 8'b00000101; dir = 0;
        check(8'b00001010, a, dir, "SHL 5 = 10");

        a = 8'b00001010; dir = 0;
        check(8'b00010100, a, dir, "SHL 10 = 20");

        a = 8'b00110010; dir = 0;
        check(8'b01100100, a, dir, "SHL 50 = 100");

        a = 8'b00000000; dir = 0;
        check(8'b00000000, a, dir, "SHL 0 = 0");

        a = 8'b11111111; dir = 0;
        check(8'b11111110, a, dir, "SHL 11111111");

        // ── RIGHT SHIFT tests (dir=1) ─────────────────────────
        a = 8'b10000000; dir = 1;
        check(8'b01000000, a, dir, "SHR 10000000");

        a = 8'b01000000; dir = 1;
        check(8'b00100000, a, dir, "SHR 01000000");

        a = 8'b00000010; dir = 1;
        check(8'b00000001, a, dir, "SHR 00000010");

        a = 8'b00000001; dir = 1;
        check(8'b00000000, a, dir, "SHR 00000001 LSB lost");

        a = 8'b00001010; dir = 1;
        check(8'b00000101, a, dir, "SHR 10 = 5");

        a = 8'b00010100; dir = 1;
        check(8'b00001010, a, dir, "SHR 20 = 10");

        a = 8'b01100100; dir = 1;
        check(8'b00110010, a, dir, "SHR 100 = 50");

        a = 8'b00000000; dir = 1;
        check(8'b00000000, a, dir, "SHR 0 = 0");

        a = 8'b11111111; dir = 1;
        check(8'b01111111, a, dir, "SHR 11111111");

        // ── SHL then SHR relationship ─────────────────────────
        a = 8'b00001010; dir = 0; #10;
        after_shl = result;         // save result of SHL
        a = after_shl; dir = 1;
        check(8'b00001010, after_shl, dir, "SHL then SHR");

        $display("Barrel shifter testbench complete");
        $finish;
    end

endmodule