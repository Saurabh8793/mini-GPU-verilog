`timescale 1ns/1ps

module subtractor_tb;

    reg  [7:0] a, b;
    wire [7:0] result;
    wire       bout;

    subtractor uut(
        .a(a),
        .b(b),
        .result(result),
        .bout(bout)
    );

    task check;
        input [7:0]      expected_result;
        input            expected_bout;
        input [7:0]      in_a, in_b;
        input [8*25-1:0] label;
        begin
            #10;
            if (result === expected_result && bout === expected_bout)
                $display("PASS | %-25s | %0d - %0d = %0d borrow=%0b",
                          label, in_a, in_b, result, bout);
            else
                $display("FAIL | %-25s | got=%0d borrow=%0b expected=%0d borrow=%0b",
                          label, result, bout, expected_result, expected_bout);
        end
    endtask

    initial begin
        $dumpfile("subtractor.vcd");
        $dumpvars(0, subtractor_tb);

        // Normal subtraction
        a=20;  b=10;  check(10,  0, 20,  10,  "SUB 20-10");
        a=100; b=50;  check(50,  0, 100, 50,  "SUB 100-50");
        a=255; b=1;   check(254, 0, 255, 1,   "SUB 255-1");
        a=1;   b=1;   check(0,   0, 1,   1,   "SUB 1-1");

        // Zero result
        a=5;   b=5;   check(0,   0, 5,   5,   "SUB 5-5 zero");
        a=0;   b=0;   check(0,   0, 0,   0,   "SUB 0-0 zero");

        
        // Borrow cases (a < b) — easy to read values
        a=0;   b=1;   check(255, 1, 0,   1,   "SUB 0-1 borrow");
        a=5;   b=10;  check(251, 1, 5,   10,  "SUB 5-10 borrow");
        a=10;  b=20;  check(246, 1, 10,  20,  "SUB 10-20 borrow");
        a=1;   b=255; check(2,   1, 1,   255, "SUB 1-255 borrow");

        // Largest possible borrow case
        a=0;   b=255; check(1,   1, 0,   255, "SUB 0-255 max borrow");
        // Edge cases
        a=255; b=255; check(0,   0, 255, 255, "SUB 255-255");
        a=128; b=127; check(1,   0, 128, 127, "SUB 128-127");
        a=127; b=128; check(255, 1, 127, 128, "SUB 127-128 borrow");

        $display("Subtractor testbench complete");
        $finish;
    end

endmodule