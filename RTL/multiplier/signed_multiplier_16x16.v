`timescale 1ns/1ps

// ============================================================
// Signed 16x16 -> 32-bit Multiplier
// Structural wrapper around four 8x8 unsigned multiplier
// instances (the existing multiplier.v module).
//
// Method: sign-magnitude decomposition
//   1. Detect sign of each operand (MSB)
//   2. Convert negative inputs to positive magnitude
//      using the ripple_carry_adder (b_invert + cin=1 = -x)
//   3. Decompose each 16-bit magnitude into hi/lo 8-bit halves
//   4. Compute four 8x8 partial products:
//        P_HH = a_hi * b_hi   -> bits [31:16]
//        P_HL = a_hi * b_lo   -> bits [23: 8]
//        P_LH = a_lo * b_hi   -> bits [23: 8]
//        P_LL = a_lo * b_lo   -> bits [15: 0]
//   5. Sum the four partial products with the RCA chain
//   6. Restore sign: if signs differ, negate the 32-bit result
//
// Ports:
//   a, b      : 16-bit signed inputs  (Q8.8 format from mandelbrot_unit)
//   product   : 32-bit signed output  (Q16.16 before the caller shifts back)
// ============================================================

module signed_multiplier_16x16 (
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    output wire signed [31:0] product
);

    // ── Step 1: Extract signs ────────────────────────────────
    wire sign_a = a[15];
    wire sign_b = b[15];
    wire sign_out;
    xor_gate sign_xor (.a(sign_a), .b(sign_b), .y(sign_out));

    // ── Step 2: Absolute value of a ──────────────────────────
    // |a| = (~a + 1) when a < 0, else a
    // Use two RCAs: lo byte then hi byte (16-bit abs via two 8-bit RCAs)
    wire [7:0]  a_inv_lo = {8{sign_a}} ^ a[7:0];   // invert if negative
    wire [7:0]  a_inv_hi = {8{sign_a}} ^ a[15:8];
    wire        a_abs_carry_mid, a_abs_carry_out;
    wire [7:0]  a_abs_lo, a_abs_hi;

    ripple_carry_adder rca_a_lo (
        .a(a_inv_lo), .b(8'h00),
        .b_invert(1'b0), .cin(sign_a),
        .result(a_abs_lo), .cout(a_abs_carry_mid),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );
    ripple_carry_adder rca_a_hi (
        .a(a_inv_hi), .b(8'h00),
        .b_invert(1'b0), .cin(a_abs_carry_mid),
        .result(a_abs_hi), .cout(a_abs_carry_out),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );

    // ── Step 3: Absolute value of b ──────────────────────────
    wire [7:0]  b_inv_lo = {8{sign_b}} ^ b[7:0];
    wire [7:0]  b_inv_hi = {8{sign_b}} ^ b[15:8];
    wire        b_abs_carry_mid, b_abs_carry_out;
    wire [7:0]  b_abs_lo, b_abs_hi;

    ripple_carry_adder rca_b_lo (
        .a(b_inv_lo), .b(8'h00),
        .b_invert(1'b0), .cin(sign_b),
        .result(b_abs_lo), .cout(b_abs_carry_mid),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );
    ripple_carry_adder rca_b_hi (
        .a(b_inv_hi), .b(8'h00),
        .b_invert(1'b0), .cin(b_abs_carry_mid),
        .result(b_abs_hi), .cout(b_abs_carry_out),
        .zero_flag(), .negative_flag(), .overflow_flag()
    );

    // ── Step 4: Four 8x8 unsigned partial products ───────────
    // Using the existing structural 8x8 multiplier module
    wire [15:0] p_ll;   // a_lo * b_lo  -> aligned at bit  0
    wire [15:0] p_lh;   // a_lo * b_hi  -> aligned at bit  8
    wire [15:0] p_hl;   // a_hi * b_lo  -> aligned at bit  8
    wire [15:0] p_hh;   // a_hi * b_hi  -> aligned at bit 16

    multiplier mul_ll (.a(a_abs_lo), .b(b_abs_lo), .product(p_ll));
    multiplier mul_lh (.a(a_abs_lo), .b(b_abs_hi), .product(p_lh));
    multiplier mul_hl (.a(a_abs_hi), .b(b_abs_lo), .product(p_hl));
    multiplier mul_hh (.a(a_abs_hi), .b(b_abs_hi), .product(p_hh));

    // ── Step 5: Align and sum the four partial products ──────
    //
    //  Bit positions of the 32-bit unsigned magnitude product:
    //
    //   p_ll                 : bits [15: 0]   (no shift)
    //   p_lh                 : bits [23: 8]   (shift left 8)
    //   p_hl                 : bits [23: 8]   (shift left 8)
    //   p_hh                 : bits [31:16]   (shift left 16)
    //
    // Aligned 32-bit operands:
    wire [31:0] p_ll_s = {16'h0000,  p_ll};
    wire [31:0] p_lh_s = {8'h00,  p_lh,  8'h00};
    wire [31:0] p_hl_s = {8'h00,  p_hl,  8'h00};
    wire [31:0] p_hh_s = {p_hh, 16'h0000};

    // Sum using chained 8-bit RCAs to produce 32-bit magnitude
    // s1 = p_ll_s + p_lh_s
    wire [31:0] s1;
    wire s1_c0, s1_c1, s1_c2;
    ripple_carry_adder rca_s1_b0 (.a(p_ll_s[ 7:0]),  .b(p_lh_s[ 7:0]),  .b_invert(1'b0), .cin(1'b0),  .result(s1[ 7:0]),  .cout(s1_c0), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_s1_b1 (.a(p_ll_s[15:8]),  .b(p_lh_s[15:8]),  .b_invert(1'b0), .cin(s1_c0), .result(s1[15:8]),  .cout(s1_c1), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_s1_b2 (.a(p_ll_s[23:16]), .b(p_lh_s[23:16]), .b_invert(1'b0), .cin(s1_c1), .result(s1[23:16]), .cout(s1_c2), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_s1_b3 (.a(p_ll_s[31:24]), .b(p_lh_s[31:24]), .b_invert(1'b0), .cin(s1_c2), .result(s1[31:24]), .cout(),      .zero_flag(), .negative_flag(), .overflow_flag());

    // s2 = s1 + p_hl_s
    wire [31:0] s2;
    wire s2_c0, s2_c1, s2_c2;
    ripple_carry_adder rca_s2_b0 (.a(s1[ 7:0]),  .b(p_hl_s[ 7:0]),  .b_invert(1'b0), .cin(1'b0),  .result(s2[ 7:0]),  .cout(s2_c0), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_s2_b1 (.a(s1[15:8]),  .b(p_hl_s[15:8]),  .b_invert(1'b0), .cin(s2_c0), .result(s2[15:8]),  .cout(s2_c1), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_s2_b2 (.a(s1[23:16]), .b(p_hl_s[23:16]), .b_invert(1'b0), .cin(s2_c1), .result(s2[23:16]), .cout(s2_c2), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_s2_b3 (.a(s1[31:24]), .b(p_hl_s[31:24]), .b_invert(1'b0), .cin(s2_c2), .result(s2[31:24]), .cout(),      .zero_flag(), .negative_flag(), .overflow_flag());

    // s3 = s2 + p_hh_s  →  unsigned magnitude of product
    wire [31:0] s3;
    wire s3_c0, s3_c1, s3_c2;
    ripple_carry_adder rca_s3_b0 (.a(s2[ 7:0]),  .b(p_hh_s[ 7:0]),  .b_invert(1'b0), .cin(1'b0),  .result(s3[ 7:0]),  .cout(s3_c0), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_s3_b1 (.a(s2[15:8]),  .b(p_hh_s[15:8]),  .b_invert(1'b0), .cin(s3_c0), .result(s3[15:8]),  .cout(s3_c1), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_s3_b2 (.a(s2[23:16]), .b(p_hh_s[23:16]), .b_invert(1'b0), .cin(s3_c1), .result(s3[23:16]), .cout(s3_c2), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_s3_b3 (.a(s2[31:24]), .b(p_hh_s[31:24]), .b_invert(1'b0), .cin(s3_c2), .result(s3[31:24]), .cout(),      .zero_flag(), .negative_flag(), .overflow_flag());

    // ── Step 6: Restore sign via two's complement negate ─────
    // If sign_out=1, product = ~s3 + 1  (negate 32-bit magnitude)
    // If sign_out=0, product = s3
    //
    // neg = ~s3 + 1  built with four chained 8-bit RCAs
    wire [31:0] s3_inv = ~s3;   // bitwise NOT (combinational)
    wire [31:0] neg_s3;
    wire neg_c0, neg_c1, neg_c2;
    ripple_carry_adder rca_neg_b0 (.a(s3_inv[ 7:0]),  .b(8'h00), .b_invert(1'b0), .cin(1'b1),   .result(neg_s3[ 7:0]),  .cout(neg_c0), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_neg_b1 (.a(s3_inv[15:8]),  .b(8'h00), .b_invert(1'b0), .cin(neg_c0), .result(neg_s3[15:8]),  .cout(neg_c1), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_neg_b2 (.a(s3_inv[23:16]), .b(8'h00), .b_invert(1'b0), .cin(neg_c1), .result(neg_s3[23:16]), .cout(neg_c2), .zero_flag(), .negative_flag(), .overflow_flag());
    ripple_carry_adder rca_neg_b3 (.a(s3_inv[31:24]), .b(8'h00), .b_invert(1'b0), .cin(neg_c2), .result(neg_s3[31:24]), .cout(),       .zero_flag(), .negative_flag(), .overflow_flag());

    // Mux: select negated or positive magnitude based on sign_out
    // product[i] = sign_out ? neg_s3[i] : s3[i]
    genvar k;
    generate
        for (k = 0; k < 32; k = k + 1) begin : sign_mux
            // Using: out = (sign & neg) | (~sign & pos)
            wire mux_neg, mux_pos, mux_out;
            and_gate and_neg (.a(sign_out),  .b(neg_s3[k]), .y(mux_neg));
            and_gate and_pos (.a(~sign_out), .b(s3[k]),     .y(mux_pos));
            or_gate  or_out  (.a(mux_neg),   .b(mux_pos),   .y(mux_out));
            assign product[k] = mux_out;
        end
    endgenerate

endmodule
