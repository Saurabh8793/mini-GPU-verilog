`timescale 1ns/1ps

module logic_unit_tb;

    reg  [7:0] a, b;
    reg  [2:0] op;
    wire [7:0] result;

    logic_unit uut(
        .a(a),
        .b(b),
        .op(op),
        .result(result)
    );

    task check;
        input [7:0]      expected;
        input [7:0]      in_a, in_b;
        input [2:0]      in_op;
        input [8*25-1:0] label;
        begin
            #10;
            if (result === expected)
                $display("PASS | %-25s | result=%08b (%0d)",
                          label, result, result);
            else
                $display("FAIL | %-25s | got=%08b expected=%08b",
                          label, result, expected);
        end
    endtask

    initial begin
        $dumpfile("logic_unit.vcd");
        $dumpvars(0, logic_unit_tb);

        // ── AND (op=00) ───────────────────────────────────────
        a=8'hFF; b=8'h0F; op=3'b000;
        check(8'h0F, a, b, op, "AND FF & 0F");

        a=8'hAA; b=8'h55; op=3'b000;
        check(8'h00, a, b, op, "AND AA & 55 zero");

        a=8'hFF; b=8'hFF; op=3'b000;
        check(8'hFF, a, b, op, "AND FF & FF");

        a=8'h00; b=8'hFF; op=3'b000;
        check(8'h00, a, b, op, "AND 00 & FF zero");

        a=8'b10101010; b=8'b11001100; op=3'b000;
        check(8'b10001000, a, b, op, "AND AA & CC");

        // ── OR (op=01) ────────────────────────────────────────
        a=8'hF0; b=8'h0F; op=3'b001;
        check(8'hFF, a, b, op, "OR F0 | 0F");

        a=8'h00; b=8'h00; op=3'b001;
        check(8'h00, a, b, op, "OR 00 | 00 zero");

        a=8'hAA; b=8'h55; op=3'b001;
        check(8'hFF, a, b, op, "OR AA | 55");

        a=8'hFF; b=8'h00; op=3'b001;
        check(8'hFF, a, b, op, "OR FF | 00");

        a=8'b10101010; b=8'b01010101; op=3'b001;
        check(8'hFF, a, b, op, "OR AA | 55 = FF");

        // ── XOR (op=10) ───────────────────────────────────────
        a=8'hFF; b=8'hFF; op=3'b010;
        check(8'h00, a, b, op, "XOR FF ^ FF zero");

        a=8'hAA; b=8'h55; op=3'b010;
        check(8'hFF, a, b, op, "XOR AA ^ 55");

        a=8'h00; b=8'hFF; op=3'b010;
        check(8'hFF, a, b, op, "XOR 00 ^ FF");

        a=8'hFF; b=8'h00; op=3'b010;
        check(8'hFF, a, b, op, "XOR FF ^ 00");

        a=8'b10101010; b=8'b10101010; op=3'b010;
        check(8'h00, a, b, op, "XOR same inputs zero");

        // ── NOT (op=11) ───────────────────────────────────────
        // NOT only uses input a, b is ignored
        a=8'h00; b=8'h00; op=3'b011;
        check(8'hFF, a, b, op, "NOT 00 = FF");

        a=8'hFF; b=8'h00; op=3'b011;
        check(8'h00, a, b, op, "NOT FF = 00");

        a=8'b10101010; b=8'h00; op=3'b011;
        check(8'b01010101, a, b, op, "NOT AA = 55");

        a=8'b01010101; b=8'h00; op=3'b011;
        check(8'b10101010, a, b, op, "NOT 55 = AA");

        a=8'b11110000; b=8'h00; op=3'b011;
        check(8'b00001111, a, b, op, "NOT F0 = 0F");

                // ── NAND (op=100) ─────────────────────────────────────
        a=8'hFF; b=8'hFF; op=3'b100;
        check(8'h00, a, b, op, "NAND FF & FF = 00");

        a=8'hFF; b=8'h0F; op=3'b100;
        check(8'hF0, a, b, op, "NAND FF & 0F = F0");

        a=8'h00; b=8'hFF; op=3'b100;
        check(8'hFF, a, b, op, "NAND 00 & FF = FF");

        a=8'hAA; b=8'h55; op=3'b100;
        check(8'hFF, a, b, op, "NAND AA & 55 = FF");

        a=8'b10101010; b=8'b11001100; op=3'b100;
        check(8'b01110111, a, b, op, "NAND AA & CC");

        // ── NOR (op=101) ──────────────────────────────────────
        a=8'hFF; b=8'h00; op=3'b101;
        check(8'h00, a, b, op, "NOR FF | 00 = 00");

        a=8'h00; b=8'h00; op=3'b101;
        check(8'hFF, a, b, op, "NOR 00 | 00 = FF");

        a=8'hF0; b=8'h0F; op=3'b101;
        check(8'h00, a, b, op, "NOR F0 | 0F = 00");

        a=8'hAA; b=8'h55; op=3'b101;
        check(8'h00, a, b, op, "NOR AA | 55 = 00");

        a=8'b10100000; b=8'b00001010; op=3'b101;
        check(8'b01010101, a, b, op, "NOR A0 | 0A");
        
        $display("Logic unit testbench complete");
        $finish;
    end

endmodule