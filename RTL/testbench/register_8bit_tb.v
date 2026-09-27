`timescale 1ns/1ps

module register_8bit_tb;
    reg        clk, reset, enable;
    reg  [7:0] d;
    wire [7:0] q;

    register_8bit uut(.clk(clk),.reset(reset),.enable(enable),.d(d),.q(q));

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("register_8bit.vcd");
        $dumpvars(0, register_8bit_tb);

        reset=1; enable=0; d=0;
        @(posedge clk); @(posedge clk);
        reset=0;

        // Load value
        enable=1; d=8'hAB; @(posedge clk); #1;
        $display("Load AB | q=%h (expect ab)", q);

        // Hold value
        enable=0; d=8'hFF; @(posedge clk); #1;
        $display("Hold    | q=%h (expect ab)", q);

        // Load new value
        enable=1; d=8'h42; @(posedge clk); #1;
        $display("Load 42 | q=%h (expect 42)", q);

        // Reset
        reset=1; @(posedge clk); #1;
        $display("Reset   | q=%h (expect 00)", q);
        reset=0;

        $display("Register 8-bit testbench complete");
        $finish;
    end
endmodule