`timescale 1ns/1ps

// 16-bit Ripple Carry Adder
// Built by chaining two 8-bit RCAs
// Lower 8-bit RCA handles bits [7:0]
// Upper 8-bit RCA handles bits [15:8]
// carry_out of lower feeds carry_in of upper
// Same b_invert and cin control as 8-bit version

module ripple_carry_adder_16bit(
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire        b_invert,
    input  wire        cin,
    output wire [15:0] result,
    output wire        cout,
    output wire        zero_flag,
    output wire        negative_flag,
    output wire        overflow_flag
);
    wire carry_mid;    // carry out of lower half into upper half
    wire ov_low;       // overflow from lower half (not used)
    wire ov_high;      // overflow from upper half (the real one)

    // Lower 8 bits — handles bits [7:0]
    ripple_carry_adder rca_low(
        .a(a[7:0]),
        .b(b[7:0]),
        .b_invert(b_invert),
        .cin(cin),
        .result(result[7:0]),
        .cout(carry_mid),
        .zero_flag(),
        .negative_flag(),
        .overflow_flag(ov_low)
    );

    // Upper 8 bits — handles bits [15:8]
    // carry_mid from lower feeds as cin here
    // b_invert still applied to upper bits too
    ripple_carry_adder rca_high(
        .a(a[15:8]),
        .b(b[15:8]),
        .b_invert(b_invert),
        .cin(carry_mid),
        .result(result[15:8]),
        .cout(cout),
        .zero_flag(),
        .negative_flag(),
        .overflow_flag(ov_high)
    );

    // Flags for the full 16-bit result
    assign zero_flag     = (result == 16'b0);
    assign negative_flag = result[15];
    assign overflow_flag = ov_high;

endmodule       