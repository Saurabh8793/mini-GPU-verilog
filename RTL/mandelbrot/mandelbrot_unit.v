`timescale 1ns/1ps

// ============================================================
// Mandelbrot Unit  —  Structural RTL
// Dedicated Q8.8 signed fixed-point compute unit.
// Computes the Mandelbrot iteration count for one pixel.
//
// Format: Q8.8 signed fixed-point
//   16-bit value represents value/256
//   1.0  = 16'sd256    -1.0  = -16'sd256
//   0.5  = 16'sd128     2.0  = 16'sd512
//
// Algorithm:
//   c = complex coordinate
//   z = 0 + 0i
//   repeat until |z|^2 > 4 or iter == MAX_ITER:
//     z = z*z + c
//   pixel = (iter / MAX_ITER) * 255    [0 = inside = black]
//
// FSM (4 states):
//   IDLE   → MUL   : latch c, zero z, enable multipliers
//   MUL    → CHECK : three structural multipliers settle;
//                    products registered on next clock edge
//   CHECK  → MUL   : update z, increment iter
//   CHECK  → FINISH: escaped OR iter == MAX_ITER
//   FINISH → IDLE  : output pixel, pulse done
//
// Multipliers:
//   Three signed_multiplier_16x16 instances (structural).
//   Each wraps four 8×8 unsigned multiplier.v quadrants
//   with sign-magnitude decomposition and RCA summation.
//   All multiply logic is gate-level — no behavioral '*'.
//
// Parallelism:
//   8 instances run simultaneously (one pixel each).
// ============================================================

module mandelbrot_unit #(
    parameter MAX_ITER = 64
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,          // 1-cycle pulse: begin pixel
    input  wire signed [15:0] c_real,  // Q8.8 real part of c
    input  wire signed [15:0] c_imag,  // Q8.8 imag part of c
    output reg  [7:0]  pixel_out,     // 8-bit result for framebuffer
    output reg         done           // 1-cycle pulse when complete
);

    // ── FSM state encoding ────────────────────────────────────
    localparam IDLE   = 2'b00;
    localparam MUL    = 2'b01;  // multipliers active; latch products next edge
    localparam CHECK  = 2'b10;  // products valid; evaluate escape / update z
    localparam FINISH = 2'b11;  // map iter→pixel, pulse done

    reg [1:0] state;

    // ── Z registers (Q8.8 signed) ─────────────────────────────
    reg signed [15:0] z_real;
    reg signed [15:0] z_imag;

    // ── Latched c (captured on start) ─────────────────────────
    reg signed [15:0] cr, ci;

    // ── Iteration counter ─────────────────────────────────────
    reg [6:0] iter;    // 7 bits → supports MAX_ITER up to 127

    // ── Structural multiplier inputs ──────────────────────────
    // Driven combinationally from z_real / z_imag in MUL state.
    // Outside MUL we tie them to zero to minimise switching power.
    reg signed [15:0] mul_a_zr2, mul_b_zr2;   // z_real × z_real
    reg signed [15:0] mul_a_zi2, mul_b_zi2;   // z_imag × z_imag
    reg signed [15:0] mul_a_zrzi, mul_b_zrzi; // z_real × z_imag

    // ── Three signed 16×16 → 32-bit structural multipliers ────
    wire signed [31:0] mul_out_zr2;
    wire signed [31:0] mul_out_zi2;
    wire signed [31:0] mul_out_zrzi;

    signed_multiplier_16x16 mul_zr2 (
        .a(mul_a_zr2),  .b(mul_b_zr2),  .product(mul_out_zr2)
    );
    signed_multiplier_16x16 mul_zi2 (
        .a(mul_a_zi2),  .b(mul_b_zi2),  .product(mul_out_zi2)
    );
    signed_multiplier_16x16 mul_zrzi (
        .a(mul_a_zrzi), .b(mul_b_zrzi), .product(mul_out_zrzi)
    );

    // ── Product registers (latched on posedge in MUL state) ───
    // Q8.8 × Q8.8 = Q16.16 (32-bit).  Bits [23:8] give Q8.8.
    reg signed [31:0] zr2;
    reg signed [31:0] zi2;
    reg signed [31:0] zrzi;

    // ── Back to Q8.8: extract the integer+fraction 16 bits ────
    wire signed [15:0] zr2_fp   = zr2[23:8];
    wire signed [15:0] zi2_fp   = zi2[23:8];
    wire signed [15:0] zrzi_fp  = zrzi[23:8];

    // ── Escape condition: |z|^2 > 4.0 ─────────────────────────
    // 4.0 in Q8.8 = 1024.  Evaluated from *registered* products
    // (guaranteed stable in CHECK state).
    wire signed [15:0] z_mag2  = zr2_fp + zi2_fp;
    wire               escaped = (z_mag2 > 16'sd1024);

    // ── Multiplier input steering ─────────────────────────────
    // Drive multiplier inputs with current z in MUL state;
    // hold at zero otherwise (saves gate toggles).
    always @(*) begin
        if (state == MUL) begin
            mul_a_zr2  = z_real; mul_b_zr2  = z_real;
            mul_a_zi2  = z_imag; mul_b_zi2  = z_imag;
            mul_a_zrzi = z_real; mul_b_zrzi = z_imag;
        end else begin
            mul_a_zr2  = 16'sd0; mul_b_zr2  = 16'sd0;
            mul_a_zi2  = 16'sd0; mul_b_zi2  = 16'sd0;
            mul_a_zrzi = 16'sd0; mul_b_zrzi = 16'sd0;
        end
    end

    // ── Sequential FSM ────────────────────────────────────────
    always @(posedge clk) begin
        if (reset) begin
            state     <= IDLE;
            done      <= 0;
            pixel_out <= 0;
            z_real    <= 0;
            z_imag    <= 0;
            cr        <= 0;
            ci        <= 0;
            iter      <= 0;
            zr2       <= 0;
            zi2       <= 0;
            zrzi      <= 0;
        end else begin

            done <= 0;  // default: done is a 1-cycle pulse

            case (state)

                // ── IDLE ──────────────────────────────────────
                IDLE: begin
                    if (start) begin
                        cr     <= c_real;
                        ci     <= c_imag;
                        z_real <= 0;
                        z_imag <= 0;
                        iter   <= 0;
                        state  <= MUL;
                    end
                end

                // ── MUL ───────────────────────────────────────
                // Multiplier inputs are steered combinationally
                // from z_real/z_imag (see always @(*) above).
                // On this clock edge we latch the combinational
                // multiplier outputs into registers.
                // First entry: z=0 → products=0 → z_new = c.
                MUL: begin
                    zr2   <= mul_out_zr2;
                    zi2   <= mul_out_zi2;
                    zrzi  <= mul_out_zrzi;
                    state <= CHECK;
                end

                // ── CHECK ─────────────────────────────────────
                // Registered products are now valid.
                // Test escape; update z if continuing.
                CHECK: begin
                    if (escaped || iter == MAX_ITER[6:0]) begin
                        state <= FINISH;
                    end else begin
                        // z_real_new = zr² - zi² + c_real
                        z_real <= zr2_fp - zi2_fp + cr;
                        // z_imag_new = 2·zr·zi + c_imag
                        z_imag <= (zrzi_fp <<< 1) + ci;
                        iter   <= iter + 1;
                        state  <= MUL;
                    end
                end

                // ── FINISH ────────────────────────────────────
                // iter >= MAX_ITER → inside set → black (0)
                // iter <  MAX_ITER → escaped   → map to 0-255
                FINISH: begin
                    if (iter >= MAX_ITER[6:0])
                        pixel_out <= 8'd0;
                    else
                        pixel_out <= (iter * 255) / MAX_ITER[6:0];

                    done  <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule