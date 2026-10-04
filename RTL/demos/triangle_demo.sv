`timescale 1ns/1ps

// ============================================================
// Flat Shaded Triangle Demo
//
// TRUE parallel rasterization using 8 shader cores.
// Each core computes three edge functions for one pixel.
// All 8 cores compute simultaneously every batch (combinational).
//
// Edge function:
//   E = (bx-ax)(py-ay) - (by-ay)(px-ax)
//   Uses signed_multiplier_16x16 (structural gate-level).
//
// Triangle vertices:
//   V0 = (32, 4)   top center
//   V1 = (4,  60)  bottom left
//   V2 = (60, 60)  bottom right
//
// Inside test (counter-clockwise winding):
//   inside iff E0 <= 0 AND E1 <= 0 AND E2 <= 0
//
// Output: pixels_tri.hex (renamed to avoid clash with pixels.hex
//         produced by mandelbrot_demo)
// ============================================================

module triangle_demo;

    localparam WIDTH  = 64;
    localparam HEIGHT = 64;
    localparam DEPTH  = WIDTH * HEIGHT;   // 4096

    reg clk, reset;
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Triangle vertices ─────────────────────────────────────
    localparam signed [7:0] V0X = 8'sd32;
    localparam signed [7:0] V0Y = 8'sd4;
    localparam signed [7:0] V1X = 8'sd4;
    localparam signed [7:0] V1Y = 8'sd60;
    localparam signed [7:0] V2X = 8'sd60;
    localparam signed [7:0] V2Y = 8'sd60;

    // ── Constant edge deltas (compile-time, sign-extended to 16b) ─
    localparam signed [15:0] D01X = {{8{V1X[7]-V0X[7]}}, V1X - V0X}; // -28
    localparam signed [15:0] D01Y = {{8{V1Y[7]-V0Y[7]}}, V1Y - V0Y}; // +56
    localparam signed [15:0] D12X = {{8{V2X[7]-V1X[7]}}, V2X - V1X}; // +56
    localparam signed [15:0] D12Y = {{8{V2Y[7]-V1Y[7]}}, V2Y - V1Y}; //  0
    localparam signed [15:0] D20X = {{8{V0X[7]-V2X[7]}}, V0X - V2X}; // -28
    localparam signed [15:0] D20Y = {{8{V0Y[7]-V2Y[7]}}, V0Y - V2Y}; // -56

    // ── 8 pixel coordinate registers ─────────────────────────
    // Explicit signals per core — avoids Icarus unpacked-array issues
    reg signed [15:0] px0, px1, px2, px3, px4, px5, px6, px7;
    reg signed [15:0] py0, py1, py2, py3, py4, py5, py6, py7;

    // ── 32-bit product wires from structural multipliers ─────
    // E(core) = D*offset_y - D*offset_x  (both terms are 32-bit products)
    // We only need the lower 32 bits; for edge comparison, bits[31] is sign.
    wire signed [31:0] e0t1_0, e0t2_0, e1t1_0, e1t2_0, e2t1_0, e2t2_0;
    wire signed [31:0] e0t1_1, e0t2_1, e1t1_1, e1t2_1, e2t1_1, e2t2_1;
    wire signed [31:0] e0t1_2, e0t2_2, e1t1_2, e1t2_2, e2t1_2, e2t2_2;
    wire signed [31:0] e0t1_3, e0t2_3, e1t1_3, e1t2_3, e2t1_3, e2t2_3;
    wire signed [31:0] e0t1_4, e0t2_4, e1t1_4, e1t2_4, e2t1_4, e2t2_4;
    wire signed [31:0] e0t1_5, e0t2_5, e1t1_5, e1t2_5, e2t1_5, e2t2_5;
    wire signed [31:0] e0t1_6, e0t2_6, e1t1_6, e1t2_6, e2t1_6, e2t2_6;
    wire signed [31:0] e0t1_7, e0t2_7, e1t1_7, e1t2_7, e2t1_7, e2t2_7;

    // Edge function results (32-bit signed)
    wire signed [31:0] e0_0 = e0t1_0 - e0t2_0;
    wire signed [31:0] e1_0 = e1t1_0 - e1t2_0;
    wire signed [31:0] e2_0 = e2t1_0 - e2t2_0;

    wire signed [31:0] e0_1 = e0t1_1 - e0t2_1;
    wire signed [31:0] e1_1 = e1t1_1 - e1t2_1;
    wire signed [31:0] e2_1 = e2t1_1 - e2t2_1;

    wire signed [31:0] e0_2 = e0t1_2 - e0t2_2;
    wire signed [31:0] e1_2 = e1t1_2 - e1t2_2;
    wire signed [31:0] e2_2 = e2t1_2 - e2t2_2;

    wire signed [31:0] e0_3 = e0t1_3 - e0t2_3;
    wire signed [31:0] e1_3 = e1t1_3 - e1t2_3;
    wire signed [31:0] e2_3 = e2t1_3 - e2t2_3;

    wire signed [31:0] e0_4 = e0t1_4 - e0t2_4;
    wire signed [31:0] e1_4 = e1t1_4 - e1t2_4;
    wire signed [31:0] e2_4 = e2t1_4 - e2t2_4;

    wire signed [31:0] e0_5 = e0t1_5 - e0t2_5;
    wire signed [31:0] e1_5 = e1t1_5 - e1t2_5;
    wire signed [31:0] e2_5 = e2t1_5 - e2t2_5;

    wire signed [31:0] e0_6 = e0t1_6 - e0t2_6;
    wire signed [31:0] e1_6 = e1t1_6 - e1t2_6;
    wire signed [31:0] e2_6 = e2t1_6 - e2t2_6;

    wire signed [31:0] e0_7 = e0t1_7 - e0t2_7;
    wire signed [31:0] e1_7 = e1t1_7 - e1t2_7;
    wire signed [31:0] e2_7 = e2t1_7 - e2t2_7;

    // Inside: all three edge functions <= 0
    wire inside0 = (e0_0 <= 0) && (e1_0 <= 0) && (e2_0 <= 0);
    wire inside1 = (e0_1 <= 0) && (e1_1 <= 0) && (e2_1 <= 0);
    wire inside2 = (e0_2 <= 0) && (e1_2 <= 0) && (e2_2 <= 0);
    wire inside3 = (e0_3 <= 0) && (e1_3 <= 0) && (e2_3 <= 0);
    wire inside4 = (e0_4 <= 0) && (e1_4 <= 0) && (e2_4 <= 0);
    wire inside5 = (e0_5 <= 0) && (e1_5 <= 0) && (e2_5 <= 0);
    wire inside6 = (e0_6 <= 0) && (e1_6 <= 0) && (e2_6 <= 0);
    wire inside7 = (e0_7 <= 0) && (e1_7 <= 0) && (e2_7 <= 0);

    // ── Structural signed multipliers — Core 0 ───────────────
    // E0 = D01X*(py-V0Y) - D01Y*(px-V0X)
    signed_multiplier_16x16 mul_e0t1_c0(.a(D01X), .b(py0 - V0Y), .product(e0t1_0));
    signed_multiplier_16x16 mul_e0t2_c0(.a(D01Y), .b(px0 - V0X), .product(e0t2_0));
    // E1 = D12X*(py-V1Y) - D12Y*(px-V1X)
    signed_multiplier_16x16 mul_e1t1_c0(.a(D12X), .b(py0 - V1Y), .product(e1t1_0));
    signed_multiplier_16x16 mul_e1t2_c0(.a(D12Y), .b(px0 - V1X), .product(e1t2_0));
    // E2 = D20X*(py-V2Y) - D20Y*(px-V2X)
    signed_multiplier_16x16 mul_e2t1_c0(.a(D20X), .b(py0 - V2Y), .product(e2t1_0));
    signed_multiplier_16x16 mul_e2t2_c0(.a(D20Y), .b(px0 - V2X), .product(e2t2_0));

    // ── Core 1 ───────────────────────────────────────────────
    signed_multiplier_16x16 mul_e0t1_c1(.a(D01X), .b(py1 - V0Y), .product(e0t1_1));
    signed_multiplier_16x16 mul_e0t2_c1(.a(D01Y), .b(px1 - V0X), .product(e0t2_1));
    signed_multiplier_16x16 mul_e1t1_c1(.a(D12X), .b(py1 - V1Y), .product(e1t1_1));
    signed_multiplier_16x16 mul_e1t2_c1(.a(D12Y), .b(px1 - V1X), .product(e1t2_1));
    signed_multiplier_16x16 mul_e2t1_c1(.a(D20X), .b(py1 - V2Y), .product(e2t1_1));
    signed_multiplier_16x16 mul_e2t2_c1(.a(D20Y), .b(px1 - V2X), .product(e2t2_1));

    // ── Core 2 ───────────────────────────────────────────────
    signed_multiplier_16x16 mul_e0t1_c2(.a(D01X), .b(py2 - V0Y), .product(e0t1_2));
    signed_multiplier_16x16 mul_e0t2_c2(.a(D01Y), .b(px2 - V0X), .product(e0t2_2));
    signed_multiplier_16x16 mul_e1t1_c2(.a(D12X), .b(py2 - V1Y), .product(e1t1_2));
    signed_multiplier_16x16 mul_e1t2_c2(.a(D12Y), .b(px2 - V1X), .product(e1t2_2));
    signed_multiplier_16x16 mul_e2t1_c2(.a(D20X), .b(py2 - V2Y), .product(e2t1_2));
    signed_multiplier_16x16 mul_e2t2_c2(.a(D20Y), .b(px2 - V2X), .product(e2t2_2));

    // ── Core 3 ───────────────────────────────────────────────
    signed_multiplier_16x16 mul_e0t1_c3(.a(D01X), .b(py3 - V0Y), .product(e0t1_3));
    signed_multiplier_16x16 mul_e0t2_c3(.a(D01Y), .b(px3 - V0X), .product(e0t2_3));
    signed_multiplier_16x16 mul_e1t1_c3(.a(D12X), .b(py3 - V1Y), .product(e1t1_3));
    signed_multiplier_16x16 mul_e1t2_c3(.a(D12Y), .b(px3 - V1X), .product(e1t2_3));
    signed_multiplier_16x16 mul_e2t1_c3(.a(D20X), .b(py3 - V2Y), .product(e2t1_3));
    signed_multiplier_16x16 mul_e2t2_c3(.a(D20Y), .b(px3 - V2X), .product(e2t2_3));

    // ── Core 4 ───────────────────────────────────────────────
    signed_multiplier_16x16 mul_e0t1_c4(.a(D01X), .b(py4 - V0Y), .product(e0t1_4));
    signed_multiplier_16x16 mul_e0t2_c4(.a(D01Y), .b(px4 - V0X), .product(e0t2_4));
    signed_multiplier_16x16 mul_e1t1_c4(.a(D12X), .b(py4 - V1Y), .product(e1t1_4));
    signed_multiplier_16x16 mul_e1t2_c4(.a(D12Y), .b(px4 - V1X), .product(e1t2_4));
    signed_multiplier_16x16 mul_e2t1_c4(.a(D20X), .b(py4 - V2Y), .product(e2t1_4));
    signed_multiplier_16x16 mul_e2t2_c4(.a(D20Y), .b(px4 - V2X), .product(e2t2_4));

    // ── Core 5 ───────────────────────────────────────────────
    signed_multiplier_16x16 mul_e0t1_c5(.a(D01X), .b(py5 - V0Y), .product(e0t1_5));
    signed_multiplier_16x16 mul_e0t2_c5(.a(D01Y), .b(px5 - V0X), .product(e0t2_5));
    signed_multiplier_16x16 mul_e1t1_c5(.a(D12X), .b(py5 - V1Y), .product(e1t1_5));
    signed_multiplier_16x16 mul_e1t2_c5(.a(D12Y), .b(px5 - V1X), .product(e1t2_5));
    signed_multiplier_16x16 mul_e2t1_c5(.a(D20X), .b(py5 - V2Y), .product(e2t1_5));
    signed_multiplier_16x16 mul_e2t2_c5(.a(D20Y), .b(px5 - V2X), .product(e2t2_5));

    // ── Core 6 ───────────────────────────────────────────────
    signed_multiplier_16x16 mul_e0t1_c6(.a(D01X), .b(py6 - V0Y), .product(e0t1_6));
    signed_multiplier_16x16 mul_e0t2_c6(.a(D01Y), .b(px6 - V0X), .product(e0t2_6));
    signed_multiplier_16x16 mul_e1t1_c6(.a(D12X), .b(py6 - V1Y), .product(e1t1_6));
    signed_multiplier_16x16 mul_e1t2_c6(.a(D12Y), .b(px6 - V1X), .product(e1t2_6));
    signed_multiplier_16x16 mul_e2t1_c6(.a(D20X), .b(py6 - V2Y), .product(e2t1_6));
    signed_multiplier_16x16 mul_e2t2_c6(.a(D20Y), .b(px6 - V2X), .product(e2t2_6));

    // ── Core 7 ───────────────────────────────────────────────
    signed_multiplier_16x16 mul_e0t1_c7(.a(D01X), .b(py7 - V0Y), .product(e0t1_7));
    signed_multiplier_16x16 mul_e0t2_c7(.a(D01Y), .b(px7 - V0X), .product(e0t2_7));
    signed_multiplier_16x16 mul_e1t1_c7(.a(D12X), .b(py7 - V1Y), .product(e1t1_7));
    signed_multiplier_16x16 mul_e1t2_c7(.a(D12Y), .b(px7 - V1X), .product(e1t2_7));
    signed_multiplier_16x16 mul_e2t1_c7(.a(D20X), .b(py7 - V2Y), .product(e2t1_7));
    signed_multiplier_16x16 mul_e2t2_c7(.a(D20Y), .b(px7 - V2X), .product(e2t2_7));

    // ── Behavioral pixel store ────────────────────────────────
    reg [7:0] pixels [0:DEPTH-1];

    // ── Simulation variables ──────────────────────────────────
    integer pixel_base, i, px, py;
    integer inside_count, fh;

    // ── Helper task: set pixel coordinates for 8 cores ───────
    task set_pixels;
        input integer base;
        begin
            px0 = (base+0) % WIDTH; py0 = (base+0) / WIDTH;
            px1 = (base+1) % WIDTH; py1 = (base+1) / WIDTH;
            px2 = (base+2) % WIDTH; py2 = (base+2) / WIDTH;
            px3 = (base+3) % WIDTH; py3 = (base+3) / WIDTH;
            px4 = (base+4) % WIDTH; py4 = (base+4) / WIDTH;
            px5 = (base+5) % WIDTH; py5 = (base+5) / WIDTH;
            px6 = (base+6) % WIDTH; py6 = (base+6) / WIDTH;
            px7 = (base+7) % WIDTH; py7 = (base+7) / WIDTH;
        end
    endtask

    // ── Main simulation ───────────────────────────────────────
    initial begin
        // VCD disabled — gate-level dump is too slow
        // $dumpfile("triangle.vcd");
        // $dumpvars(0, triangle_demo);

        reset        = 1;
        inside_count = 0;
        pixel_base   = 0;
        px0=0; py0=0; px1=0; py1=0;
        px2=0; py2=0; px3=0; py3=0;
        px4=0; py4=0; px5=0; py5=0;
        px6=0; py6=0; px7=0; py7=0;
        for (i = 0; i < DEPTH; i = i + 1) pixels[i] = 8'h00;

        repeat(4) @(posedge clk);
        reset = 0;
        repeat(2) @(posedge clk);

        $display("============================================");
        $display("  Mini GPU - Triangle Rasterization");
        $display("============================================");
        $display("Algorithm:  Edge function rasterization");
        $display("Vertices:   V0(%0d,%0d) V1(%0d,%0d) V2(%0d,%0d)",
                  V0X, V0Y, V1X, V1Y, V2X, V2Y);
        $display("Cores:      8 parallel edge function units");
        $display("Winding:    Counter-clockwise (inside <= 0)");
        $display("Multiplier: signed_multiplier_16x16 (structural)");
        $display("--------------------------------------------");

        while (pixel_base < DEPTH) begin
            // Load coordinates into all 8 cores
            set_pixels(pixel_base);

            // One clock cycle: all 8 combinational edge units evaluate
            @(posedge clk);

            // Capture results into behavioral pixel store
            pixels[pixel_base+0] = inside0 ? 8'hFF : 8'h00;
            pixels[pixel_base+1] = inside1 ? 8'hFF : 8'h00;
            pixels[pixel_base+2] = inside2 ? 8'hFF : 8'h00;
            pixels[pixel_base+3] = inside3 ? 8'hFF : 8'h00;
            pixels[pixel_base+4] = inside4 ? 8'hFF : 8'h00;
            pixels[pixel_base+5] = inside5 ? 8'hFF : 8'h00;
            pixels[pixel_base+6] = inside6 ? 8'hFF : 8'h00;
            pixels[pixel_base+7] = inside7 ? 8'hFF : 8'h00;

            if (inside0) inside_count = inside_count + 1;
            if (inside1) inside_count = inside_count + 1;
            if (inside2) inside_count = inside_count + 1;
            if (inside3) inside_count = inside_count + 1;
            if (inside4) inside_count = inside_count + 1;
            if (inside5) inside_count = inside_count + 1;
            if (inside6) inside_count = inside_count + 1;
            if (inside7) inside_count = inside_count + 1;

            pixel_base = pixel_base + 8;

            if (pixel_base % 512 == 0)
                $display("  Progress: %0d / %0d pixels",
                          pixel_base, DEPTH);
        end

        // Dump to pixels_tri.hex (separate from mandelbrot's pixels.hex)
        fh = $fopen("pixels_tri.hex", "w");
        if (fh == 0) begin
            $display("ERROR: Cannot open pixels_tri.hex for writing");
        end else begin
            for (i = 0; i < DEPTH; i = i + 1)
                $fwrite(fh, "%02x\n", pixels[i]);
            $fclose(fh);
            $display("Framebuffer dumped: %0d pixels to pixels_tri.hex",
                      DEPTH);
        end

        $display("--------------------------------------------");
        $display("Render complete!");
        $display("Inside pixels:  %0d", inside_count);
        $display("Outside pixels: %0d", DEPTH - inside_count);
        $display("Coverage:       %0d%%", (inside_count * 100) / DEPTH);
        $display("Run: python python/triangle_viz.py");
        $display("============================================");

        $finish;
    end

endmodule