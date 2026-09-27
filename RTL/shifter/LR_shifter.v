`timescale 1ns/1ps

// Shifts left or right by 1 bit
// dir=0 → left shift (multiply by 2)
// dir=1 → right shift (divide by 2)

module LR_shifter(
    input  wire [7:0] a,
    input  wire       dir,
    output wire [7:0] result
);
    wire [7:0] shift_left;
    wire [7:0] shift_right;
    wire [7:0] mux_out;

    // Left shift: each bit moves one position left, LSB gets 0
    assign shift_left[7] = a[6];
    assign shift_left[6] = a[5];
    assign shift_left[5] = a[4];
    assign shift_left[4] = a[3];
    assign shift_left[3] = a[2];
    assign shift_left[2] = a[1];
    assign shift_left[1] = a[0];
    assign shift_left[0] = 1'b0;

    // Right shift: each bit moves one position right, MSB gets 0
    assign shift_right[7] = 1'b0;
    assign shift_right[6] = a[7];
    assign shift_right[5] = a[6];
    assign shift_right[4] = a[5];
    assign shift_right[3] = a[4];
    assign shift_right[2] = a[3];
    assign shift_right[1] = a[2];
    assign shift_right[0] = a[1];

    // Mux selects left or right based on dir
    assign result = dir ? shift_right : shift_left;

endmodule