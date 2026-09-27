`timescale 1ns/1ps

// 8-bit Register
// Built from 8 D flip flops
// Stores one byte of data
// All 8 bits share the same clk, reset, enable

module register_8bit(
    input  wire       clk,
    input  wire       reset,
    input  wire       enable,
    input  wire [7:0] d,
    output wire [7:0] q
);
    // Instantiate 8 DFFs, one per bit
    dff bit0(.clk(clk),.reset(reset),.enable(enable),.d(d[0]),.q(q[0]));
    dff bit1(.clk(clk),.reset(reset),.enable(enable),.d(d[1]),.q(q[1]));
    dff bit2(.clk(clk),.reset(reset),.enable(enable),.d(d[2]),.q(q[2]));
    dff bit3(.clk(clk),.reset(reset),.enable(enable),.d(d[3]),.q(q[3]));
    dff bit4(.clk(clk),.reset(reset),.enable(enable),.d(d[4]),.q(q[4]));
    dff bit5(.clk(clk),.reset(reset),.enable(enable),.d(d[5]),.q(q[5]));
    dff bit6(.clk(clk),.reset(reset),.enable(enable),.d(d[6]),.q(q[6]));
    dff bit7(.clk(clk),.reset(reset),.enable(enable),.d(d[7]),.q(q[7]));

endmodule