`timescale 1ns/1ps

module register_file_tb;
    reg        clk, reset, write_enable;
    reg  [3:0] write_addr, read_addr_a, read_addr_b;
    reg  [7:0] write_data;
    wire [7:0] read_data_a, read_data_b;

    register_file_16x8 uut(
        .clk(clk), .reset(reset),
        .write_enable(write_enable),
        .write_addr(write_addr),
        .write_data(write_data),
        .read_addr_a(read_addr_a),
        .read_data_a(read_data_a),
        .read_addr_b(read_addr_b),
        .read_data_b(read_data_b)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task write_reg;
        input [3:0] addr;
        input [7:0] data;
        begin
            write_enable = 1;
            write_addr   = addr;
            write_data   = data;
            @(posedge clk);
            #1;
            write_enable = 0;
        end
    endtask

    task read_check;
        input [3:0]      addr;
        input [7:0]      expected;
        input [8*20-1:0] label;
        begin
            read_addr_a = addr;
            #1;
            if (read_data_a === expected)
                $display("PASS | %-20s | R%0d = %0d", label, addr, read_data_a);
            else
                $display("FAIL | %-20s | R%0d = %0d expected %0d",
                          label, addr, read_data_a, expected);
        end
    endtask

    integer i;

    initial begin
        $dumpfile("register_file.vcd");
        $dumpvars(0, register_file_tb);

        reset=1; write_enable=0;
        read_addr_a=0; read_addr_b=0;
        @(posedge clk); @(posedge clk);
        reset=0;

        // Write to all 16 registers
        $display("--- Writing to all 16 registers ---");
        for (i=0; i<16; i=i+1)
            write_reg(i, i*10);

        // Read all back through port A
        $display("--- Reading all registers through port A ---");
        for (i=0; i<16; i=i+1)
            read_check(i, i*10, "READ_A");

        // Test dual port read — read two at same time
        $display("--- Dual port read test ---");
        read_addr_a = 4'd3;
        read_addr_b = 4'd7;
        #1;
        $display("Port A: R3 = %0d (expect 30)", read_data_a);
        $display("Port B: R7 = %0d (expect 70)", read_data_b);

        // Write to R5 and immediately read back
        $display("--- Write then read R5 ---");
        write_reg(4'd5, 8'hFF);
        read_check(4'd5, 8'hFF, "WRITE_READ");

        // Verify other registers unchanged
        read_check(4'd4, 8'd40, "UNCHANGED R4");
        read_check(4'd6, 8'd60, "UNCHANGED R6");

        // Reset test
        $display("--- Reset test ---");
        reset=1; @(posedge clk); #1;
        reset=0;
        read_check(4'd0, 8'd0, "AFTER RESET R0");
        read_check(4'd5, 8'd0, "AFTER RESET R5");

        $display("Register file testbench complete");
        $finish;
    end
endmodule