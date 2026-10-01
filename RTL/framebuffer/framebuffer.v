`timescale 1ns/1ps

// ============================================================
// Framebuffer
// Pixel memory for GPU render output
//
// Built from register_8bit modules (which use DFF primitives)
// Each pixel location is one register_8bit instance
//
// Parameters:
//   WIDTH  → horizontal resolution in pixels
//   HEIGHT → vertical resolution in pixels
//   DEPTH  → total pixels = WIDTH * HEIGHT (derived)
//
// Address mapping:
//   addr = row * WIDTH + col
//   Example for 64x64:
//     row=0,  col=0  → addr=0
//     row=1,  col=0  → addr=64
//     row=63, col=63 → addr=4095
//   Address calculation is the renderer's responsibility
//   Framebuffer only receives the final address
//
// Write interface:
//   write_enable=1 → store pixel_in at addr on clock edge
//
// Read interface:
//   write_enable=0 → addr selects the pixel to read
//   Synchronous read — pixel_out updates on the clock edge
// Dump interface:
//   Simulation-only. Not synthesizable.
//   Used to export framebuffer contents to Python renderer.
//   dump_enable pulse → writes all pixels to pixels.hex
// ============================================================

module framebuffer #(
    parameter WIDTH      = 64,
    parameter HEIGHT     = 64,
    parameter DEPTH      = WIDTH * HEIGHT,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  write_enable,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [7:0]            pixel_in,
    output reg  [7:0]            pixel_out,
    input  wire                  dump_enable
);

    // ── Pixel memory ──────────────────────────────────────────
    // DEPTH instances of register_8bit
    // Each stores one 8-bit grayscale pixel
    // All instances share clk and reset
    // Only selected instance gets write enable

    wire [7:0]      mem_out    [0:DEPTH-1];
    wire [DEPTH-1:0] loc_write_en;

    genvar i;

    // Address decoder
    // Exactly one loc_write_en bit goes high per write
    generate
        for (i = 0; i < DEPTH; i = i + 1) begin : addr_decode
            assign loc_write_en[i] = write_enable &
                                     (addr == i[ADDR_WIDTH-1:0]);
        end
    endgenerate

    // Pixel register instances
    // Built from register_8bit which is built from DFF primitives
    generate
        for (i = 0; i < DEPTH; i = i + 1) begin : pixel_regs
            register_8bit pixel_reg(
                .clk(clk),
                .reset(reset),
                .enable(loc_write_en[i]),
                .d(pixel_in),
                .q(mem_out[i])
            );
        end
    endgenerate

    // ── Synchronous read ──────────────────────────────────────
    // One cycle latency
    // addr presented → pixel_out valid next cycle
    always @(posedge clk) begin
        if (reset)
            pixel_out <= 8'b0;
        else
            pixel_out <= mem_out[addr];
    end

    // ── Simulation-only dump interface ───────────────────────
    // NOT synthesizable
    // Exports framebuffer contents to pixels.hex
    // Python reads this file to render the final image
    //
    // pixels.hex format:
    //   One pixel per line in hex
    //   Line 0    = pixel at addr 0   (row=0, col=0)
    //   Line 64   = pixel at addr 64  (row=1, col=0)
    //   Line 4095 = pixel at addr 4095 (row=63, col=63)

    integer file_handle;
    integer j;

    always @(posedge clk) begin
        if (dump_enable) begin
            file_handle = $fopen("pixels.hex", "w");

            // Check $fopen succeeded
            if (file_handle == 0) begin
                $display("ERROR: Could not open pixels.hex for writing");
            end else begin
                for (j = 0; j < DEPTH; j = j + 1)
                    $fwrite(file_handle, "%02x\n", mem_out[j]);
                $fclose(file_handle);
                $display("Framebuffer dumped: %0d pixels written to pixels.hex",
                          DEPTH);
            end
        end
    end

endmodule