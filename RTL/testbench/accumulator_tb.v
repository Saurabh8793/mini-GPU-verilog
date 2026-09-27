`timescale 1ns/1ps

module accumulator_tb;
    reg        clk, reset;
    reg  [1:0] acc_mode;
    reg  [7:0] data_in;
    wire [7:0] acc_out;
    wire       zero_flag;

    accumulator uut(
        .clk(clk), .reset(reset),
        .acc_mode(acc_mode),
        .data_in(data_in),
        .acc_out(acc_out),
        .zero_flag(zero_flag)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("accumulator.vcd");
        $dumpvars(0, accumulator_tb);

        reset=1; acc_mode=2'b00; data_in=0;
        @(posedge clk); @(posedge clk);
        reset=0;

        // LOAD test
        acc_mode=2'b01; data_in=8'd50; @(posedge clk); #1;
        $display("LOAD 50  | acc=%0d (expect 50)", acc_out);

        // HOLD test
        acc_mode=2'b00; data_in=8'd99; @(posedge clk); #1;
        $display("HOLD     | acc=%0d (expect 50)", acc_out);

        // ADD test — accumulate values like dot product
        acc_mode=2'b10; data_in=8'd10; @(posedge clk); #1;
        $display("ADD 10   | acc=%0d (expect 60)", acc_out);

        acc_mode=2'b10; data_in=8'd20; @(posedge clk); #1;
        $display("ADD 20   | acc=%0d (expect 80)", acc_out);

        acc_mode=2'b10; data_in=8'd5;  @(posedge clk); #1;
        $display("ADD 5    | acc=%0d (expect 85)", acc_out);

        // CLEAR test
        acc_mode=2'b11; @(posedge clk); #1;
        $display("CLEAR    | acc=%0d zero=%0b (expect 0, 1)",
                  acc_out, zero_flag);

        // Dot product simulation using accumulator
        // Simulates: 2x3 + 4x5 + 1x7 = 6+20+7 = 33
        acc_mode=2'b10; data_in=8'd6;  @(posedge clk); #1; // 2x3=6
        $display("After ADD 6  | acc=%0d (expect 6)",  acc_out);

        acc_mode=2'b10; data_in=8'd20; @(posedge clk); #1; // 4x5=20
        $display("After ADD 20 | acc=%0d (expect 26)", acc_out);

        acc_mode=2'b10; data_in=8'd7;  @(posedge clk); #1; // 1x7=7
        $display("After ADD 7  | acc=%0d (expect 33)", acc_out);

        // Extra clock cycle so waveform captures final value
        acc_mode=2'b00; @(posedge clk); #1;
        $display("Dot product result | acc=%0d (expect 33)", acc_out);

        if (acc_out === 8'd33)
            $display("PASS | Dot product correct");
        else
            $display("FAIL | Dot product got %0d expected 33", acc_out);

        $display("Accumulator testbench complete");
        $finish;
    end
endmodule