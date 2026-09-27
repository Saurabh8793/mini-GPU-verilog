`timescale 1ns/1ps

module ripple_carry_adder(
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire b_invert,
    input  wire cin,
    output wire cout,
    output wire zero_flag,
    output wire negative_flag,
    output wire overflow_flag,
    output wire [7:0] result
);

    wire [7:0] b_modified;

    // When b_invert is high, XOR flips every bit of b (needed for subtraction).
    // When low, b passes straight through untouched.
    
    xor_gate bx0(.a(b[0]), .b(b_invert), .y(b_modified[0]));
    xor_gate bx1(.a(b[1]), .b(b_invert), .y(b_modified[1]));
    xor_gate bx2(.a(b[2]), .b(b_invert), .y(b_modified[2]));
    xor_gate bx3(.a(b[3]), .b(b_invert), .y(b_modified[3]));
    xor_gate bx4(.a(b[4]), .b(b_invert), .y(b_modified[4]));
    xor_gate bx5(.a(b[5]), .b(b_invert), .y(b_modified[5]));
    xor_gate bx6(.a(b[6]), .b(b_invert), .y(b_modified[6]));
    xor_gate bx7(.a(b[7]), .b(b_invert), .y(b_modified[7]));

     wire [6:0] carry;

    // Internal carry ripple chain between stages (bit 0 up to bit 6)
    full_adder fa0(.a(a[0]), .b(b_modified[0]), .cin(cin), .sum(result[0]),
     .cout(carry[0]));
        
    full_adder fa1(.a(a[1]), .b(b_modified[1]), .cin(carry[0]), .sum(result[1]), 
    .cout(carry[1]));
        
    full_adder fa2(.a(a[2]), .b(b_modified[2]), .cin(carry[1]), .sum(result[2]), 
    .cout(carry[2]));
        
    full_adder fa3(.a(a[3]), .b(b_modified[3]), .cin(carry[2]), .sum(result[3]),
    .cout(carry[3]));
    
    full_adder fa4(.a(a[4]), .b(b_modified[4]), .cin(carry[3]), .sum(result[4]),
    .cout(carry[4]));
   
    full_adder fa5(.a(a[5]), .b(b_modified[5]), .cin(carry[4]), .sum(result[5]),
    .cout(carry[5]));  
         
  
    full_adder fa6(.a(a[6]), .b(b_modified[6]), .cin(carry[5]), .sum(result[6]),
    .cout(carry[6]));

    full_adder fa7(.a(a[7]), .b(b_modified[7]), .cin(carry[6]),
    .sum(result[7]), .cout(cout));
    
    // Status flags: 1. Z: high if the result evaluates to all zeros 
                //   2.N: high if the sign bit (MSB) is 1 (two's complement negative)
    assign zero_flag     = (result == 8'b0);
    assign negative_flag = result[7];

    // Signed overflow check: Flags when carry-in to the sign bit (carry[6])
    // doesn't match carry-out (cout)

   xor_gate overflow_xor(.a(carry[6]), .b(cout), .y(overflow_flag));
        
endmodule