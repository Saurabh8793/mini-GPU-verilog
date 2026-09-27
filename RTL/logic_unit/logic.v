`timescale 1ns/1ps

module logic_unit(
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [1:0] op,
    output reg  [7:0] result
);
    // op=00 → AND
    // op=01 → OR
    // op=10 → XOR
    // op=11 → NOT a

    wire [7:0] and_result;
    wire [7:0] or_result;
    wire [7:0] xor_result;
    wire [7:0] not_result;

    // Instantiate 8 gates for each operation
    and_gate a0(.a(a[0]),.b(b[0]),.y(and_result[0]));
    and_gate a1(.a(a[1]),.b(b[1]),.y(and_result[1]));
    and_gate a2(.a(a[2]),.b(b[2]),.y(and_result[2]));
    and_gate a3(.a(a[3]),.b(b[3]),.y(and_result[3]));
    and_gate a4(.a(a[4]),.b(b[4]),.y(and_result[4]));
    and_gate a5(.a(a[5]),.b(b[5]),.y(and_result[5]));
    and_gate a6(.a(a[6]),.b(b[6]),.y(and_result[6]));
    and_gate a7(.a(a[7]),.b(b[7]),.y(and_result[7]));

    or_gate  o0(.a(a[0]),.b(b[0]),.y(or_result[0]));
    or_gate  o1(.a(a[1]),.b(b[1]),.y(or_result[1]));
    or_gate  o2(.a(a[2]),.b(b[2]),.y(or_result[2]));
    or_gate  o3(.a(a[3]),.b(b[3]),.y(or_result[3]));
    or_gate  o4(.a(a[4]),.b(b[4]),.y(or_result[4]));
    or_gate  o5(.a(a[5]),.b(b[5]),.y(or_result[5]));
    or_gate  o6(.a(a[6]),.b(b[6]),.y(or_result[6]));
    or_gate  o7(.a(a[7]),.b(b[7]),.y(or_result[7]));

    xor_gate x0(.a(a[0]),.b(b[0]),.y(xor_result[0]));
    xor_gate x1(.a(a[1]),.b(b[1]),.y(xor_result[1]));
    xor_gate x2(.a(a[2]),.b(b[2]),.y(xor_result[2]));
    xor_gate x3(.a(a[3]),.b(b[3]),.y(xor_result[3]));
    xor_gate x4(.a(a[4]),.b(b[4]),.y(xor_result[4]));
    xor_gate x5(.a(a[5]),.b(b[5]),.y(xor_result[5]));
    xor_gate x6(.a(a[6]),.b(b[6]),.y(xor_result[6]));
    xor_gate x7(.a(a[7]),.b(b[7]),.y(xor_result[7]));

    not_gate n0(.a(a[0]),.y(not_result[0]));
    not_gate n1(.a(a[1]),.y(not_result[1]));
    not_gate n2(.a(a[2]),.y(not_result[2]));
    not_gate n3(.a(a[3]),.y(not_result[3]));
    not_gate n4(.a(a[4]),.y(not_result[4]));
    not_gate n5(.a(a[5]),.y(not_result[5]));
    not_gate n6(.a(a[6]),.y(not_result[6]));
    not_gate n7(.a(a[7]),.y(not_result[7]));

    always @(*) begin
        case (op)
            2'b00: result = and_result;
            2'b01: result = or_result;
            2'b10: result = xor_result;
            2'b11: result = not_result;
            default: result = 8'b0;
        endcase
    end

endmodule