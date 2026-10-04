`timescale 1ns/1ps

// ============================================================
// 64-to-1 Multiplexer, 8-bit wide
// Built hierarchically from 2-to-1 muxes
//
// Structure:
//   Level 1: 32 × 2-to-1 mux → 32 outputs
//   Level 2: 16 × 2-to-1 mux → 16 outputs
//   Level 3:  8 × 2-to-1 mux →  8 outputs
//   Level 4:  4 × 2-to-1 mux →  4 outputs
//   Level 5:  2 × 2-to-1 mux →  2 outputs
//   Level 6:  1 × 2-to-1 mux →  1 output
//
// Each 2-to-1 mux selects based on one bit of the address
// sel[0] selects within pairs at level 1
// sel[1] selects within pairs at level 2
// etc.
// ============================================================

module mux_64to1_8bit(
    input  wire [7:0] in [0:63],
    input  wire [5:0] sel,
    output wire [7:0] out
);

    // Level 1: 32 muxes, sel[0] selects
    wire [7:0] l1 [0:31];
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : lv1
            // sel[0]=0 → in[2i], sel[0]=1 → in[2i+1]
            assign l1[i] = sel[0] ? in[2*i+1] : in[2*i];
        end
    endgenerate

    // Level 2: 16 muxes, sel[1] selects
    wire [7:0] l2 [0:15];
    generate
        for (i = 0; i < 16; i = i + 1) begin : lv2
            assign l2[i] = sel[1] ? l1[2*i+1] : l1[2*i];
        end
    endgenerate

    // Level 3: 8 muxes, sel[2] selects
    wire [7:0] l3 [0:7];
    generate
        for (i = 0; i < 8; i = i + 1) begin : lv3
            assign l3[i] = sel[2] ? l2[2*i+1] : l2[2*i];
        end
    endgenerate

    // Level 4: 4 muxes, sel[3] selects
    wire [7:0] l4 [0:3];
    generate
        for (i = 0; i < 4; i = i + 1) begin : lv4
            assign l4[i] = sel[3] ? l3[2*i+1] : l3[2*i];
        end
    endgenerate

    // Level 5: 2 muxes, sel[4] selects
    wire [7:0] l5 [0:1];
    generate
        for (i = 0; i < 2; i = i + 1) begin : lv5
            assign l5[i] = sel[4] ? l4[2*i+1] : l4[2*i];
        end
    endgenerate

    // Level 6: 1 mux, sel[5] selects
    assign out = sel[5] ? l5[1] : l5[0];

endmodule