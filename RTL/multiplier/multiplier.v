`timescale 1ns/1ps

module multiplier(
    input  wire [7:0]  a,
    input  wire [7:0]  b,
    output wire [15:0] product
);

    // ── Partial products via AND gates ──────────────────────

    wire [7:0] pp0,pp1,pp2,pp3,pp4,pp5,pp6,pp7;

    and_gate m00(.a(a[0]),.b(b[0]),.y(pp0[0]));
    and_gate m01(.a(a[1]),.b(b[0]),.y(pp0[1]));
    and_gate m02(.a(a[2]),.b(b[0]),.y(pp0[2]));
    and_gate m03(.a(a[3]),.b(b[0]),.y(pp0[3]));
    and_gate m04(.a(a[4]),.b(b[0]),.y(pp0[4]));
    and_gate m05(.a(a[5]),.b(b[0]),.y(pp0[5]));
    and_gate m06(.a(a[6]),.b(b[0]),.y(pp0[6]));
    and_gate m07(.a(a[7]),.b(b[0]),.y(pp0[7]));

    and_gate m10(.a(a[0]),.b(b[1]),.y(pp1[0]));
    and_gate m11(.a(a[1]),.b(b[1]),.y(pp1[1]));
    and_gate m12(.a(a[2]),.b(b[1]),.y(pp1[2]));
    and_gate m13(.a(a[3]),.b(b[1]),.y(pp1[3]));
    and_gate m14(.a(a[4]),.b(b[1]),.y(pp1[4]));
    and_gate m15(.a(a[5]),.b(b[1]),.y(pp1[5]));
    and_gate m16(.a(a[6]),.b(b[1]),.y(pp1[6]));
    and_gate m17(.a(a[7]),.b(b[1]),.y(pp1[7]));

    and_gate m20(.a(a[0]),.b(b[2]),.y(pp2[0]));
    and_gate m21(.a(a[1]),.b(b[2]),.y(pp2[1]));
    and_gate m22(.a(a[2]),.b(b[2]),.y(pp2[2]));
    and_gate m23(.a(a[3]),.b(b[2]),.y(pp2[3]));
    and_gate m24(.a(a[4]),.b(b[2]),.y(pp2[4]));
    and_gate m25(.a(a[5]),.b(b[2]),.y(pp2[5]));
    and_gate m26(.a(a[6]),.b(b[2]),.y(pp2[6]));
    and_gate m27(.a(a[7]),.b(b[2]),.y(pp2[7]));

    and_gate m30(.a(a[0]),.b(b[3]),.y(pp3[0]));
    and_gate m31(.a(a[1]),.b(b[3]),.y(pp3[1]));
    and_gate m32(.a(a[2]),.b(b[3]),.y(pp3[2]));
    and_gate m33(.a(a[3]),.b(b[3]),.y(pp3[3]));
    and_gate m34(.a(a[4]),.b(b[3]),.y(pp3[4]));
    and_gate m35(.a(a[5]),.b(b[3]),.y(pp3[5]));
    and_gate m36(.a(a[6]),.b(b[3]),.y(pp3[6]));
    and_gate m37(.a(a[7]),.b(b[3]),.y(pp3[7]));

    and_gate m40(.a(a[0]),.b(b[4]),.y(pp4[0]));
    and_gate m41(.a(a[1]),.b(b[4]),.y(pp4[1]));
    and_gate m42(.a(a[2]),.b(b[4]),.y(pp4[2]));
    and_gate m43(.a(a[3]),.b(b[4]),.y(pp4[3]));
    and_gate m44(.a(a[4]),.b(b[4]),.y(pp4[4]));
    and_gate m45(.a(a[5]),.b(b[4]),.y(pp4[5]));
    and_gate m46(.a(a[6]),.b(b[4]),.y(pp4[6]));
    and_gate m47(.a(a[7]),.b(b[4]),.y(pp4[7]));

    and_gate m50(.a(a[0]),.b(b[5]),.y(pp5[0]));
    and_gate m51(.a(a[1]),.b(b[5]),.y(pp5[1]));
    and_gate m52(.a(a[2]),.b(b[5]),.y(pp5[2]));
    and_gate m53(.a(a[3]),.b(b[5]),.y(pp5[3]));
    and_gate m54(.a(a[4]),.b(b[5]),.y(pp5[4]));
    and_gate m55(.a(a[5]),.b(b[5]),.y(pp5[5]));
    and_gate m56(.a(a[6]),.b(b[5]),.y(pp5[6]));
    and_gate m57(.a(a[7]),.b(b[5]),.y(pp5[7]));

    and_gate m60(.a(a[0]),.b(b[6]),.y(pp6[0]));
    and_gate m61(.a(a[1]),.b(b[6]),.y(pp6[1]));
    and_gate m62(.a(a[2]),.b(b[6]),.y(pp6[2]));
    and_gate m63(.a(a[3]),.b(b[6]),.y(pp6[3]));
    and_gate m64(.a(a[4]),.b(b[6]),.y(pp6[4]));
    and_gate m65(.a(a[5]),.b(b[6]),.y(pp6[5]));
    and_gate m66(.a(a[6]),.b(b[6]),.y(pp6[6]));
    and_gate m67(.a(a[7]),.b(b[6]),.y(pp6[7]));

    and_gate m70(.a(a[0]),.b(b[7]),.y(pp7[0]));
    and_gate m71(.a(a[1]),.b(b[7]),.y(pp7[1]));
    and_gate m72(.a(a[2]),.b(b[7]),.y(pp7[2]));
    and_gate m73(.a(a[3]),.b(b[7]),.y(pp7[3]));
    and_gate m74(.a(a[4]),.b(b[7]),.y(pp7[4]));
    and_gate m75(.a(a[5]),.b(b[7]),.y(pp7[5]));
    and_gate m76(.a(a[6]),.b(b[7]),.y(pp7[6]));
    and_gate m77(.a(a[7]),.b(b[7]),.y(pp7[7]));

    // ── Shift partial products to correct bit positions ──────

    wire [15:0] pp0_s = {8'b0, pp0};
    wire [15:0] pp1_s = {7'b0, pp1, 1'b0};
    wire [15:0] pp2_s = {6'b0, pp2, 2'b0};
    wire [15:0] pp3_s = {5'b0, pp3, 3'b0};
    wire [15:0] pp4_s = {4'b0, pp4, 4'b0};
    wire [15:0] pp5_s = {3'b0, pp5, 5'b0};
    wire [15:0] pp6_s = {2'b0, pp6, 6'b0};
    wire [15:0] pp7_s = {1'b0, pp7, 7'b0};

    // ── Add partial products using chained 8-bit RCAs ────────

    wire [15:0] sum01, sum23, sum45, sum67;
    wire [15:0] sum0123, sum4567;
    wire        c01, c23, c45, c67, c0123, c4567;

    // sum01 = pp0_s + pp1_s
    wire c01_mid;
    ripple_carry_adder rca01_lo(
        .a(pp0_s[7:0]),  .b(pp1_s[7:0]),
        .b_invert(1'b0), .cin(1'b0),
        .result(sum01[7:0]),
        .cout(c01_mid),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );
    ripple_carry_adder rca01_hi(
        .a(pp0_s[15:8]), .b(pp1_s[15:8]),
        .b_invert(1'b0), .cin(c01_mid),
        .result(sum01[15:8]),
        .cout(c01),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );

    // sum23 = pp2_s + pp3_s
    wire c23_mid;
    ripple_carry_adder rca23_lo(
        .a(pp2_s[7:0]),  .b(pp3_s[7:0]),
        .b_invert(1'b0), .cin(1'b0),
        .result(sum23[7:0]),
        .cout(c23_mid),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );
    ripple_carry_adder rca23_hi(
        .a(pp2_s[15:8]), .b(pp3_s[15:8]),
        .b_invert(1'b0), .cin(c23_mid),
        .result(sum23[15:8]),
        .cout(c23),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );

    // sum45 = pp4_s + pp5_s
    wire c45_mid;
    ripple_carry_adder rca45_lo(
        .a(pp4_s[7:0]),  .b(pp5_s[7:0]),
        .b_invert(1'b0), .cin(1'b0),
        .result(sum45[7:0]),
        .cout(c45_mid),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );
    ripple_carry_adder rca45_hi(
        .a(pp4_s[15:8]), .b(pp5_s[15:8]),
        .b_invert(1'b0), .cin(c45_mid),
        .result(sum45[15:8]),
        .cout(c45),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );

    // sum67 = pp6_s + pp7_s
    wire c67_mid;
    ripple_carry_adder rca67_lo(
        .a(pp6_s[7:0]),  .b(pp7_s[7:0]),
        .b_invert(1'b0), .cin(1'b0),
        .result(sum67[7:0]),
        .cout(c67_mid),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );
    ripple_carry_adder rca67_hi(
        .a(pp6_s[15:8]), .b(pp7_s[15:8]),
        .b_invert(1'b0), .cin(c67_mid),
        .result(sum67[15:8]),
        .cout(c67),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );

    // sum0123 = sum01 + sum23
    wire c0123_mid;
    ripple_carry_adder rca0123_lo(
        .a(sum01[7:0]),  .b(sum23[7:0]),
        .b_invert(1'b0), .cin(1'b0),
        .result(sum0123[7:0]),
        .cout(c0123_mid),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );
    ripple_carry_adder rca0123_hi(
        .a(sum01[15:8]), .b(sum23[15:8]),
        .b_invert(1'b0), .cin(c0123_mid),
        .result(sum0123[15:8]),
        .cout(c0123),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );

    // sum4567 = sum45 + sum67
    wire c4567_mid;
    ripple_carry_adder rca4567_lo(
        .a(sum45[7:0]),  .b(sum67[7:0]),
        .b_invert(1'b0), .cin(1'b0),
        .result(sum4567[7:0]),
        .cout(c4567_mid),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );
    ripple_carry_adder rca4567_hi(
        .a(sum45[15:8]), .b(sum67[15:8]),
        .b_invert(1'b0), .cin(c4567_mid),
        .result(sum4567[15:8]),
        .cout(c4567),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );

    // product = sum0123 + sum4567
    wire cfinal_mid;
    ripple_carry_adder rcafinal_lo(
        .a(sum0123[7:0]),  .b(sum4567[7:0]),
        .b_invert(1'b0),   .cin(1'b0),
        .result(product[7:0]),
        .cout(cfinal_mid),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );
    ripple_carry_adder rcafinal_hi(
        .a(sum0123[15:8]), .b(sum4567[15:8]),
        .b_invert(1'b0),   .cin(cfinal_mid),
        .result(product[15:8]),
        .cout(),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );

endmodule