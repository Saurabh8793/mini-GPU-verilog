`timescale 1ns/1ps

// 16 x 8-bit Register File
// Built from 16 instances of register_8bit
// 2 read ports — can read two registers simultaneously
// 1 write port — can write one register per clock cycle
// This is what sits inside each GPU shader core

module register_file_16x8(
    input  wire        clk,
    input  wire        reset,

    // Write port
    input  wire        write_enable,
    input  wire [3:0]  write_addr,    // which register to write (0-15)
    input  wire [7:0]  write_data,    // data to write

    // Read port A
    input  wire [3:0]  read_addr_a,   // which register to read
    output wire [7:0]  read_data_a,   // data output

    // Read port B
    input  wire [3:0]  read_addr_b,
    output wire [7:0]  read_data_b
);

    // 16 register enable signals
    // Only one goes high per write operation
    wire [15:0] reg_enable;

    // Decode write address to enable signal
    // Only the selected register gets enabled for writing
    assign reg_enable[0]  = write_enable & (write_addr == 4'd0);
    assign reg_enable[1]  = write_enable & (write_addr == 4'd1);
    assign reg_enable[2]  = write_enable & (write_addr == 4'd2);
    assign reg_enable[3]  = write_enable & (write_addr == 4'd3);
    assign reg_enable[4]  = write_enable & (write_addr == 4'd4);
    assign reg_enable[5]  = write_enable & (write_addr == 4'd5);
    assign reg_enable[6]  = write_enable & (write_addr == 4'd6);
    assign reg_enable[7]  = write_enable & (write_addr == 4'd7);
    assign reg_enable[8]  = write_enable & (write_addr == 4'd8);
    assign reg_enable[9]  = write_enable & (write_addr == 4'd9);
    assign reg_enable[10] = write_enable & (write_addr == 4'd10);
    assign reg_enable[11] = write_enable & (write_addr == 4'd11);
    assign reg_enable[12] = write_enable & (write_addr == 4'd12);
    assign reg_enable[13] = write_enable & (write_addr == 4'd13);
    assign reg_enable[14] = write_enable & (write_addr == 4'd14);
    assign reg_enable[15] = write_enable & (write_addr == 4'd15);

    // 16 register outputs
    wire [7:0] reg_out [0:15];

    // Instantiate 16 registers
    register_8bit r0 (.clk(clk),.reset(reset),.enable(reg_enable[0]),
                      .d(write_data),.q(reg_out[0]));
    register_8bit r1 (.clk(clk),.reset(reset),.enable(reg_enable[1]),
                      .d(write_data),.q(reg_out[1]));
    register_8bit r2 (.clk(clk),.reset(reset),.enable(reg_enable[2]),
                      .d(write_data),.q(reg_out[2]));
    register_8bit r3 (.clk(clk),.reset(reset),.enable(reg_enable[3]),
                      .d(write_data),.q(reg_out[3]));
    register_8bit r4 (.clk(clk),.reset(reset),.enable(reg_enable[4]),
                      .d(write_data),.q(reg_out[4]));
    register_8bit r5 (.clk(clk),.reset(reset),.enable(reg_enable[5]),
                      .d(write_data),.q(reg_out[5]));
    register_8bit r6 (.clk(clk),.reset(reset),.enable(reg_enable[6]),
                      .d(write_data),.q(reg_out[6]));
    register_8bit r7 (.clk(clk),.reset(reset),.enable(reg_enable[7]),
                      .d(write_data),.q(reg_out[7]));
    register_8bit r8 (.clk(clk),.reset(reset),.enable(reg_enable[8]),
                      .d(write_data),.q(reg_out[8]));
    register_8bit r9 (.clk(clk),.reset(reset),.enable(reg_enable[9]),
                      .d(write_data),.q(reg_out[9]));
    register_8bit r10(.clk(clk),.reset(reset),.enable(reg_enable[10]),
                      .d(write_data),.q(reg_out[10]));
    register_8bit r11(.clk(clk),.reset(reset),.enable(reg_enable[11]),
                      .d(write_data),.q(reg_out[11]));
    register_8bit r12(.clk(clk),.reset(reset),.enable(reg_enable[12]),
                      .d(write_data),.q(reg_out[12]));
    register_8bit r13(.clk(clk),.reset(reset),.enable(reg_enable[13]),
                      .d(write_data),.q(reg_out[13]));
    register_8bit r14(.clk(clk),.reset(reset),.enable(reg_enable[14]),
                      .d(write_data),.q(reg_out[14]));
    register_8bit r15(.clk(clk),.reset(reset),.enable(reg_enable[15]),
                      .d(write_data),.q(reg_out[15]));

    // Read port A — combinational MUX selects register output
    assign read_data_a = reg_out[read_addr_a];

    // Read port B — combinational MUX selects register output
    assign read_data_b = reg_out[read_addr_b];

endmodule