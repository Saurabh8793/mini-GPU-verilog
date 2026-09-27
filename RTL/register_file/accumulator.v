`timescale 1ns/1ps

// Accumulator Register
// Uses our ripple_carry_adder for ADD operation
// No behavioural + operator used anywhere
// Modes:
//   00 → HOLD    keep current value
//   01 → LOAD    load new value from data_in
//   10 → ADD     add data_in to accumulator using RCA
//   11 → CLEAR   reset to zero

module accumulator(
    input  wire clk,
    input  wire reset,
    input  wire [1:0] acc_mode,
    input  wire [7:0] data_in,
    output reg  [7:0] acc_out,
    output wire zero_flag,
    output wire carry_out
);
    localparam HOLD  = 2'b00;
    localparam LOAD  = 2'b01;
    localparam ADD   = 2'b10;
    localparam CLEAR = 2'b11;

    // RCA adds current accumulator value with data_in
    // acc_out + data_in using our actual hardware adder
    wire [7:0] rca_result;
    wire rca_cout;
    wire rca_zero;
    wire rca_neg;
    wire rca_overflow;

    ripple_carry_adder rca_add(
        .a(acc_out),
        .b(data_in),
        .b_invert(1'b0),
        .cin(1'b0),
        .result(rca_result),
        .cout(rca_cout),
        .zero_flag(rca_zero),
        .negative_flag(rca_neg),
        .overflow_flag(rca_overflow)
    );

    always @(posedge clk) begin
        if (reset) begin
            acc_out <= 8'b0;
        end else begin
            case (acc_mode)
                HOLD:  acc_out <= acc_out;
                LOAD:  acc_out <= data_in;
                ADD:   acc_out <= rca_result;  // uses RCA output
                CLEAR: acc_out <= 8'b0;
                default: acc_out <= acc_out;
            endcase
        end
    end

    assign zero_flag = (acc_out == 8'b0);
    assign carry_out = rca_cout;

endmodule