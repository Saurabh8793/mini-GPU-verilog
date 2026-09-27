`timescale 1ns/1ps

module multiplier_tb;

    reg  [7:0]  a, b;
    wire [15:0] product;

    multiplier uut(
        .a(a),
        .b(b),
        .product(product)
    );

    task check;
        input [15:0] expected;
        input [7:0]  in_a, in_b;
        input [8*30-1:0] label;
        begin
            #10;
            if (product === expected)
                $display("PASS | %-30s | %0d x %0d = %0d",
                          label, in_a, in_b, product);
            else
                $display("FAIL | %-30s | %0d x %0d = %0d (expected %0d)",
                          label, in_a, in_b, product, expected);
        end
    endtask

    initial begin
        $dumpfile("multiplier.vcd");
        $dumpvars(0, multiplier_tb);

        // ── Basic cases ───────────────────────────────────────
        a=0;   b=0;
        check(0, a, b, "0 x 0");

        a=1;   b=1;
        check(1, a, b, "1 x 1");

        a=1;   b=255;
        check(255, a, b, "1 x 255 identity");

        a=255; b=1;
        check(255, a, b, "255 x 1 identity");

        a=0;   b=255;
        check(0, a, b, "0 x 255 zero");

        a=255; b=0;
        check(0, a, b, "255 x 0 zero");

        // ── Small values ──────────────────────────────────────
        a=2;   b=3;
        check(6, a, b, "2 x 3");

        a=5;   b=6;
        check(30, a, b, "5 x 6");

        a=7;   b=8;
        check(56, a, b, "7 x 8");

        a=10;  b=10;
        check(100, a, b, "10 x 10");

        a=12;  b=12;
        check(144, a, b, "12 x 12");

        // ── Powers of 2 (shift left equivalents) ──────────────
        // Multiply by 2 = shift left 1
        // Multiply by 4 = shift left 2
        // etc.
        a=5;   b=2;
        check(10, a, b, "5 x 2 = SHL once");

        a=5;   b=4;
        check(20, a, b, "5 x 4 = SHL twice");

        a=5;   b=8;
        check(40, a, b, "5 x 8 = SHL three");

        a=5;   b=16;
        check(80, a, b, "5 x 16 = SHL four");

        a=1;   b=128;
        check(128, a, b, "1 x 128");

        // ── Medium values ─────────────────────────────────────
        a=16;  b=16;
        check(256, a, b, "16 x 16 = 256");

        a=50;  b=50;
        check(2500, a, b, "50 x 50 = 2500");

        a=100; b=100;
        check(10000, a, b, "100 x 100 = 10000");

        a=64;  b=64;
        check(4096, a, b, "64 x 64 = 4096");

        // ── Large values — needs full 16 bits ─────────────────
        a=128; b=128;
        check(16384, a, b, "128 x 128 = 16384");

        a=200; b=200;
        check(40000, a, b, "200 x 200 = 40000");

        a=255; b=255;
        check(65025, a, b, "255 x 255 = 65025 max");

        a=255; b=128;
        check(32640, a, b, "255 x 128");

        a=128; b=255;
        check(32640, a, b, "128 x 255 commutative");

        // ── Commutativity check ───────────────────────────────
        // a x b must equal b x a always

        a=37;  b=91;
        check(3367, a, b, "37 x 91");

        a=91;  b=37;
        check(3367, a, b, "91 x 37 commutative check");

        a=123; b=45;
        check(5535, a, b, "123 x 45");

        a=45;  b=123;
        check(5535, a, b, "45 x 123 commutative check");

        $display("Multiplier testbench complete");
        $finish;
    end

endmodule