`timescale 1ns/1ps

// D Flip Flop — single bit memory
// The fundamental building block of all registers
// On every rising clock edge: Q captures value of D
// Synchronous reset: when reset=1, Q goes to 0 on next clock edge
// Enable: when enable=0, Q holds its current value

module dff(
    input  wire clk,
    input  wire reset,
    input  wire enable,
    input  wire d,
    output reg  q
);
    always @(posedge clk) begin
        if (reset)
            q <= 1'b0;
        else if (enable)
            q <= d;
        // when enable=0, q holds value automatically
    end
endmodule