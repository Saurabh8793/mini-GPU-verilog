`timescale 1ns/1ps

module dff_tb;
    reg  clk, reset, enable, d;
    wire q;

    dff uut(.clk(clk),.reset(reset),.enable(enable),.d(d),.q(q));

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dff.vcd");
        $dumpvars(0, dff_tb);

        reset=1; enable=0; d=0; @(posedge clk); @(posedge clk);
        reset=0;

        // Enable test — q should follow d
        enable=1; d=1; @(posedge clk); #1;
        $display("Enable=1 d=1 | q=%0b (expect 1)", q);

        d=0; @(posedge clk); #1;
        $display("Enable=1 d=0 | q=%0b (expect 0)", q);

        // Hold test — q should not change when enable=0
        d=1; enable=0; @(posedge clk); #1;
        $display("Enable=0 d=1 | q=%0b (expect 0, held)", q);

        // Reset test
        enable=1; d=1; @(posedge clk); #1;
        $display("Load 1   | q=%0b (expect 1)", q);
        reset=1; @(posedge clk); #1;
        $display("Reset    | q=%0b (expect 0)", q);
        reset=0;

        $display("DFF testbench complete");
        $finish;
    end
endmodule