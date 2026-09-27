`timescale 1ns/1ps

module carry_lookahead_adder(
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire       b_invert,
    input  wire       cin,
    output wire [7:0] result,
    output wire       cout,
    output wire       zero_flag,
    output wire       negative_flag,
    output wire       overflow_flag
);

    // Conditional invert on B for subtraction (1's complement)
    wire [7:0] b_modified;

    xor_gate bx0(.a(b[0]), .b(b_invert), .y(b_modified[0]));
    xor_gate bx1(.a(b[1]), .b(b_invert), .y(b_modified[1]));
    xor_gate bx2(.a(b[2]), .b(b_invert), .y(b_modified[2]));
    xor_gate bx3(.a(b[3]), .b(b_invert), .y(b_modified[3]));
    xor_gate bx4(.a(b[4]), .b(b_invert), .y(b_modified[4]));
    xor_gate bx5(.a(b[5]), .b(b_invert), .y(b_modified[5]));
    xor_gate bx6(.a(b[6]), .b(b_invert), .y(b_modified[6]));
    xor_gate bx7(.a(b[7]), .b(b_invert), .y(b_modified[7]));

    // Bitwise Generate (G) and Propagate (P) terms
    wire [7:0] G;
    wire [7:0] P;

    and_gate g0(.a(a[0]), .b(b_modified[0]), .y(G[0]));
    and_gate g1(.a(a[1]), .b(b_modified[1]), .y(G[1]));
    and_gate g2(.a(a[2]), .b(b_modified[2]), .y(G[2]));
    and_gate g3(.a(a[3]), .b(b_modified[3]), .y(G[3]));
    and_gate g4(.a(a[4]), .b(b_modified[4]), .y(G[4]));
    and_gate g5(.a(a[5]), .b(b_modified[5]), .y(G[5]));
    and_gate g6(.a(a[6]), .b(b_modified[6]), .y(G[6]));
    and_gate g7(.a(a[7]), .b(b_modified[7]), .y(G[7]));

    xor_gate p0(.a(a[0]), .b(b_modified[0]), .y(P[0]));
    xor_gate p1(.a(a[1]), .b(b_modified[1]), .y(P[1]));
    xor_gate p2(.a(a[2]), .b(b_modified[2]), .y(P[2]));
    xor_gate p3(.a(a[3]), .b(b_modified[3]), .y(P[3]));
    xor_gate p4(.a(a[4]), .b(b_modified[4]), .y(P[4]));
    xor_gate p5(.a(a[5]), .b(b_modified[5]), .y(P[5]));
    xor_gate p6(.a(a[6]), .b(b_modified[6]), .y(P[6]));
    xor_gate p7(.a(a[7]), .b(b_modified[7]), .y(P[7]));

    // Parallel carry logic: compute all stage carries without ripple delay
    wire [7:0] C; // C[i] = carry into bit i

    assign C[0] = cin;
    assign C[1] = G[0] | (P[0] & cin);
    assign C[2] = G[1] | (P[1] & G[0]) | (P[1] & P[0] & cin);
    assign C[3] = G[2] | (P[2] & G[1]) | (P[2] & P[1] & G[0])
                       | (P[2] & P[1] & P[0] & cin);

    assign C[4] = G[3] | (P[3] & G[2]) | (P[3] & P[2] & G[1])
                       | (P[3] & P[2] & P[1] & G[0])
                       | (P[3] & P[2] & P[1] & P[0] & cin);

    assign C[5] = G[4] | (P[4] & G[3]) | (P[4] & P[3] & G[2])
                       | (P[4] & P[3] & P[2] & G[1])
                       | (P[4] & P[3] & P[2] & P[1] & G[0])
                       | (P[4] & P[3] & P[2] & P[1] & P[0] & cin);

    assign C[6] = G[5] | (P[5] & G[4]) | (P[5] & P[4] & G[3])
                       | (P[5] & P[4] & P[3] & G[2])
                       | (P[5] & P[4] & P[3] & P[2] & G[1])
                       | (P[5] & P[4] & P[3] & P[2] & P[1] & G[0])
                       | (P[5] & P[4] & P[3] & P[2] & P[1] & P[0] & cin);

    assign C[7] = G[6] | (P[6] & G[5]) | (P[6] & P[5] & G[4])
                       | (P[6] & P[5] & P[4] & G[3])
                       | (P[6] & P[5] & P[4] & P[3] & G[2])
                       | (P[6] & P[5] & P[4] & P[3] & P[2] & G[1])
                       | (P[6] & P[5] & P[4] & P[3] & P[2] & P[1] & G[0])
                       | (P[6] & P[5] & P[4] & P[3] & P[2] & P[1] & P[0] & cin);

    assign cout = G[7] | (P[7] & C[7]);

    // Sum calculation: S[i] = P[i] ^ C[i]
    xor_gate s0(.a(P[0]), .b(C[0]), .y(result[0]));
    xor_gate s1(.a(P[1]), .b(C[1]), .y(result[1]));
    xor_gate s2(.a(P[2]), .b(C[2]), .y(result[2]));
    xor_gate s3(.a(P[3]), .b(C[3]), .y(result[3]));
    xor_gate s4(.a(P[4]), .b(C[4]), .y(result[4]));
    xor_gate s5(.a(P[5]), .b(C[5]), .y(result[5]));
    xor_gate s6(.a(P[6]), .b(C[6]), .y(result[6]));
    xor_gate s7(.a(P[7]), .b(C[7]), .y(result[7]));

    // Status flags
    assign zero_flag     = (result == 8'b0);
    assign negative_flag = result[7];

    // Signed overflow: mismatch between carry into and out of MSB
    xor_gate ov(.a(C[7]), .b(cout), .y(overflow_flag));

endmodule