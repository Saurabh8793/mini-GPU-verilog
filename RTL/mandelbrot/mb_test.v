`timescale 1ns/1ps
// Two-batch diagnostic: run first batch then immediately second
module mb_test2;
    reg clk = 0;
    always #5 clk = ~clk;

    reg reset = 1;
    // Use individual regs instead of arrays to avoid for-loop indexing issues
    reg start0=0, start1=0, start2=0, start3=0;
    reg start4=0, start5=0, start6=0, start7=0;
    wire [7:0] done_bus;
    wire [7:0] pout0, pout1, pout2, pout3, pout4, pout5, pout6, pout7;

    // c=2+0i for all (escapes fast)
    mandelbrot_unit #(.MAX_ITER(8)) u0(.clk(clk),.reset(reset),.start(start0),.c_real(16'sd512),.c_imag(16'sd0),.pixel_out(pout0),.done(done_bus[0]));
    mandelbrot_unit #(.MAX_ITER(8)) u1(.clk(clk),.reset(reset),.start(start1),.c_real(16'sd512),.c_imag(16'sd0),.pixel_out(pout1),.done(done_bus[1]));
    mandelbrot_unit #(.MAX_ITER(8)) u2(.clk(clk),.reset(reset),.start(start2),.c_real(16'sd512),.c_imag(16'sd0),.pixel_out(pout2),.done(done_bus[2]));
    mandelbrot_unit #(.MAX_ITER(8)) u3(.clk(clk),.reset(reset),.start(start3),.c_real(16'sd512),.c_imag(16'sd0),.pixel_out(pout3),.done(done_bus[3]));
    mandelbrot_unit #(.MAX_ITER(8)) u4(.clk(clk),.reset(reset),.start(start4),.c_real(16'sd512),.c_imag(16'sd0),.pixel_out(pout4),.done(done_bus[4]));
    mandelbrot_unit #(.MAX_ITER(8)) u5(.clk(clk),.reset(reset),.start(start5),.c_real(16'sd512),.c_imag(16'sd0),.pixel_out(pout5),.done(done_bus[5]));
    mandelbrot_unit #(.MAX_ITER(8)) u6(.clk(clk),.reset(reset),.start(start6),.c_real(16'sd512),.c_imag(16'sd0),.pixel_out(pout6),.done(done_bus[6]));
    mandelbrot_unit #(.MAX_ITER(8)) u7(.clk(clk),.reset(reset),.start(start7),.c_real(16'sd512),.c_imag(16'sd0),.pixel_out(pout7),.done(done_bus[7]));

    reg [7:0] done_latch;
    integer t, timeout;

    task pulse_start;
        begin
            @(posedge clk);
            start0=1; start1=1; start2=1; start3=1;
            start4=1; start5=1; start6=1; start7=1;
            @(posedge clk);
            start0=0; start1=0; start2=0; start3=0;
            start4=0; start5=0; start6=0; start7=0;
        end
    endtask

    task wait_done;
        begin
            done_latch = 8'h00;
            timeout = 0;
            while (done_latch !== 8'hFF && timeout < 30) begin
                @(posedge clk);
                if (done_bus[0]) done_latch[0] = 1;
                if (done_bus[1]) done_latch[1] = 1;
                if (done_bus[2]) done_latch[2] = 1;
                if (done_bus[3]) done_latch[3] = 1;
                if (done_bus[4]) done_latch[4] = 1;
                if (done_bus[5]) done_latch[5] = 1;
                if (done_bus[6]) done_latch[6] = 1;
                if (done_bus[7]) done_latch[7] = 1;
                timeout = timeout + 1;
                $display("  t=%0d done_bus=%08b done_latch=%08b st0=%b", timeout, done_bus, done_latch, u0.state);
            end
        end
    endtask

    initial begin
        repeat(4) @(posedge clk);
        reset = 0;
        repeat(2) @(posedge clk);

        $display("=== BATCH 0 ===");
        pulse_start;
        wait_done;
        $display("Batch 0 done. done_latch=%08b pout0=%0d", done_latch, pout0);

        repeat(2) @(posedge clk); // settle

        $display("=== BATCH 1 ===");
        pulse_start;
        wait_done;
        $display("Batch 1 done. done_latch=%08b pout0=%0d", done_latch, pout0);

        $finish;
    end
endmodule
