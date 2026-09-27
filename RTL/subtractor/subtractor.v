`timescale 1ns/1ps

// 8-bit unsigned subtractor
// Reuses the ripple carry adder configured for two's complement subtraction (A - B)
// Borrow-out (bout) is derived by inverting carry-out:
//   bout = 0 -> A >= B (no borrow needed)
//   bout = 1 -> A < B  (borrow occurred)

module subtractor(
    input  wire [7:0] a,
    input  wire [7:0] b,
    output wire [7:0] result,
    output wire       bout
);

    wire cout;
    wire zero_flag, negative_flag, overflow_flag;

    // Run A + (~B) + 1 through the RCA
    ripple_carry_adder rca(
        .a(a),
        .b(b),
        .b_invert(1'b1),
        .cin(1'b1),
        .result(result),
        .cout(cout),
        .zero_flag(zero_flag),
        .negative_flag(negative_flag),
        .overflow_flag(overflow_flag)
    );

    // Active-high borrow is the complement of carry-out
    assign bout = ~cout;

endmodule