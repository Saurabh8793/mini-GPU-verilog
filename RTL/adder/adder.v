module half_adder(a,b,sum,carry);
    input wire a,b;
    output wire sum, carry;

    and_gate AG_01(.a(a), .b(b), .y(carry));
    xor_gate XG_01(.a(a), .b(b), .y(sum));
endmodule

module full_adder(a,b,cin,sum,cout);
    input wire a,b,cin;
    output wire sum,cout;

    wire sum1, carry1, carry2;
    half_adder HA_01(.a(a), .b(b), .sum(sum1), .carry(carry1));
    half_adder HA_02(.a(sum1),.b(cin), .sum(sum), .carry(carry2));

    or_gate OR_01(.a(carry1), .b(carry2), .y(cout));

endmodule
