`timescale 1ns/1ps

module divider_tb;

    reg        clk, reset, start;
    reg  [7:0] dividend, divisor;
    wire [7:0] quotient, remainder;
    wire       done, div_by_zero;

    divider uut(
        .clk(clk), .reset(reset), .start(start),
        .dividend(dividend), .divisor(divisor),
        .quotient(quotient), .remainder(remainder),
        .done(done), .div_by_zero(div_by_zero)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task do_divide;
        input [7:0] dd;
        input [7:0] dv;
        input [7:0] exp_q;
        input [7:0] exp_r;
        begin
            @(posedge clk);
            dividend = dd;
            divisor  = dv;
            start    = 1;
            @(posedge clk);
            start = 0;

            // Wait until done goes high
            wait(done == 1'b1);
            @(posedge clk);

            if (div_by_zero) begin
                $display("DIV_BY_ZERO | %0d / %0d", dd, dv);
            end else if (quotient === exp_q && remainder === exp_r) begin
                $display("PASS | %0d / %0d = %0d rem %0d",
                          dd, dv, quotient, remainder);
            end else begin
                $display("FAIL | %0d / %0d = %0d rem %0d (expected q=%0d r=%0d)",
                          dd, dv, quotient, remainder, exp_q, exp_r);
            end

            // Wait for state to return to IDLE
            @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("divider.vcd");
        $dumpvars(0, divider_tb);

        reset = 1; start = 0;
        repeat(3) @(posedge clk);
        reset = 0;
        @(posedge clk);

        //          dividend  divisor  exp_q  exp_r
        do_divide(  20,       4,       5,     0    );
        do_divide(  22,       4,       5,     2    );
        do_divide(  100,      7,       14,    2    );
        do_divide(  255,      16,      15,    15   );
        do_divide(  1,        1,       1,     0    );
        do_divide(  0,        5,       0,     0    );
        do_divide(  128,      2,       64,    0    );
        do_divide(  200,      13,      15,    5    );
        do_divide(  255,      255,     1,     0    );
        do_divide(  7,        10,      0,     7    ); // divisor > dividend
        do_divide(  10,       0,       0,     0    ); // div by zero

        $display("Divider testbench complete");
        $finish;
    end

endmodule