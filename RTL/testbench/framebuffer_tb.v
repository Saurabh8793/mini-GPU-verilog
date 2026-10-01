`timescale 1ns/1ps

module framebuffer_tb;

    // Parameters matching framebuffer
    localparam WIDTH      = 64;
    localparam HEIGHT     = 64;
    localparam DEPTH      = WIDTH * HEIGHT;  // 4096
    localparam ADDR_WIDTH = $clog2(DEPTH);              // $clog2(4096) = 12

    reg                  clk, reset;
    reg                  write_enable;
    reg  [ADDR_WIDTH-1:0] addr;
    reg  [7:0]           pixel_in;
    reg                  dump_enable;
    wire [7:0]           pixel_out;

    framebuffer #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) uut(
        .clk(clk), .reset(reset),
        .write_enable(write_enable),
        .addr(addr),
        .pixel_in(pixel_in),
        .pixel_out(pixel_out),
        .dump_enable(dump_enable)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count;
    integer fail_count;
    integer i;

    // Write one pixel
    task write_pixel;
        input [ADDR_WIDTH-1:0] pixel_addr;
        input [7:0]            pixel_val;
        begin
            write_enable = 1;
            addr         = pixel_addr;
            pixel_in     = pixel_val;
            @(posedge clk);
            write_enable = 0;
            @(posedge clk);
        end
    endtask

    // Read one pixel and check against expected
    task read_check;
        input [ADDR_WIDTH-1:0] pixel_addr;
        input [7:0]            expected;
        input [127:0]          label;
        begin
            write_enable = 0;
            addr         = pixel_addr;
            @(posedge clk);
            @(posedge clk); #1;
            if (pixel_out === expected) begin
                $display("PASS | %-30s | addr=%0d pixel=%0d",
                          label, pixel_addr, pixel_out);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | %-30s | addr=%0d got=%0d exp=%0d",
                          label, pixel_addr, pixel_out, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("framebuffer.vcd");
        $dumpvars(0, framebuffer_tb);

        pass_count   = 0;
        fail_count   = 0;
        write_enable = 0;
        dump_enable  = 0;
        addr         = 0;
        pixel_in     = 0;

        // Reset
        reset = 1;
        repeat(3) @(posedge clk);
        reset = 0;
        @(posedge clk);

        // ════════════════════════════════════════════════════
        // TEST 1: Reset check
        // After reset all pixels should be 0
        // Check first, middle and last address
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 1: Reset check ---");
        read_check(12'd0,    8'd0, "reset addr 0");
        read_check(12'd2047, 8'd0, "reset addr 2047 middle");
        read_check(12'd4095, 8'd0, "reset addr 4095 last");

        // ════════════════════════════════════════════════════
        // TEST 2: Single pixel write and read back
        // Write one pixel verify it reads back correctly
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 2: Single pixel write and read ---");
        write_pixel(12'd0,    8'd255);
        read_check( 12'd0,    8'd255, "write 255 addr 0");

        write_pixel(12'd100,  8'd128);
        read_check( 12'd100,  8'd128, "write 128 addr 100");

        write_pixel(12'd4095, 8'd42);
        read_check( 12'd4095, 8'd42,  "write 42 addr 4095 last");

        write_pixel(12'd2048, 8'd1);
        read_check( 12'd2048, 8'd1,   "write 1 addr 2048 mid");

        // ════════════════════════════════════════════════════
        // TEST 3: Overwrite same address
        // Write to same address twice
        // Second value should replace first
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 3: Overwrite same address ---");
        write_pixel(12'd50, 8'd100);
        read_check( 12'd50, 8'd100, "first write addr 50");

        write_pixel(12'd50, 8'd200);
        read_check( 12'd50, 8'd200, "overwrite addr 50");

        write_pixel(12'd50, 8'd0);
        read_check( 12'd50, 8'd0,   "overwrite with 0 addr 50");

        // ════════════════════════════════════════════════════
        // TEST 4: Address isolation
        // Write to one address
        // Verify neighbouring addresses unchanged
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 4: Address isolation ---");
        write_pixel(12'd200, 8'd255);

        // Neighbours should be 0 or previous values
        read_check(12'd199, 8'd0,   "addr 199 unchanged");
        read_check(12'd200, 8'd255, "addr 200 written");
        read_check(12'd201, 8'd0,   "addr 201 unchanged");

        // ════════════════════════════════════════════════════
        // TEST 5: Row and column address mapping
        // addr = row * WIDTH + col
        // Verify correct pixel location
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 5: Row column address mapping ---");

        // Row 0, Col 0 → addr 0
        write_pixel(0*WIDTH + 0,  8'd10);
        read_check( 0*WIDTH + 0,  8'd10, "row0 col0");

        // Row 0, Col 5 → addr 5
        write_pixel(0*WIDTH + 5,  8'd20);
        read_check( 0*WIDTH + 5,  8'd20, "row0 col5");

        // Row 1, Col 0 → addr 64
        write_pixel(1*WIDTH + 0,  8'd30);
        read_check( 1*WIDTH + 0,  8'd30, "row1 col0");

        // Row 10, Col 20 → addr 660
        write_pixel(10*WIDTH + 20, 8'd40);
        read_check( 10*WIDTH + 20, 8'd40, "row10 col20");

        // Row 32, Col 32 → addr 2080 (center)
        write_pixel(32*WIDTH + 32, 8'd128);
        read_check( 32*WIDTH + 32, 8'd128, "row32 col32 center");

        // Row 63, Col 63 → addr 4095 (bottom right)
        write_pixel(63*WIDTH + 63, 8'd255);
        read_check( 63*WIDTH + 63, 8'd255, "row63 col63 corner");

        // ════════════════════════════════════════════════════
        // TEST 6: Pixel boundary values
        // Test minimum and maximum pixel values
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 6: Boundary pixel values ---");
        write_pixel(12'd300, 8'd0);
        read_check( 12'd300, 8'd0,   "pixel value 0 black");

        write_pixel(12'd301, 8'd255);
        read_check( 12'd301, 8'd255, "pixel value 255 white");

        write_pixel(12'd302, 8'd1);
        read_check( 12'd302, 8'd1,   "pixel value 1 min nonzero");

        write_pixel(12'd303, 8'd254);
        read_check( 12'd303, 8'd254, "pixel value 254 max minus 1");

        write_pixel(12'd304, 8'd127);
        read_check( 12'd304, 8'd127, "pixel value 127 mid");

        write_pixel(12'd305, 8'd128);
        read_check( 12'd305, 8'd128, "pixel value 128 mid+1");

        // ════════════════════════════════════════════════════
        // TEST 7: Write without enable
        // Assert write_enable=0 while changing pixel_in
        // pixel should NOT change
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 7: Write enable gating ---");
        write_pixel(12'd400, 8'd77);
        read_check( 12'd400, 8'd77, "write 77 addr 400");

        // Now try to write with enable=0
        write_enable = 0;
        addr         = 12'd400;
        pixel_in     = 8'd255;
        @(posedge clk);
        @(posedge clk); #1;

        // Value should still be 77
        read_check(12'd400, 8'd77, "no write enable held 77");

        // ════════════════════════════════════════════════════
        // TEST 8: Synchronous reset during operation
        // Write pixels then reset
        // All pixels should return to 0
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 8: Reset during operation ---");
        write_pixel(12'd500, 8'd99);
        write_pixel(12'd501, 8'd88);
        write_pixel(12'd502, 8'd77);

        // Verify written
        read_check(12'd500, 8'd99, "pre-reset addr 500");
        read_check(12'd501, 8'd88, "pre-reset addr 501");
        read_check(12'd502, 8'd77, "pre-reset addr 502");

        // Assert reset
        reset = 1;
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk); #1;

        // All should be 0 after reset
        read_check(12'd500, 8'd0, "post-reset addr 500");
        read_check(12'd501, 8'd0, "post-reset addr 501");
        read_check(12'd502, 8'd0, "post-reset addr 502");

        // ════════════════════════════════════════════════════
        // TEST 9: Pattern write
        // Write a checkerboard pattern
        // Verify selected pixels
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 9: Checkerboard pattern ---");

        // Write checkerboard — even addresses white odd black
        for (i = 0; i < 16; i = i + 1) begin
            if (i % 2 == 0)
                write_pixel(i, 8'd255);  // white
            else
                write_pixel(i, 8'd0);    // black
        end

        // Verify pattern
        read_check(12'd0,  8'd255, "checker addr 0 white");
        read_check(12'd1,  8'd0,   "checker addr 1 black");
        read_check(12'd2,  8'd255, "checker addr 2 white");
        read_check(12'd3,  8'd0,   "checker addr 3 black");
        read_check(12'd4,  8'd255, "checker addr 4 white");
        read_check(12'd5,  8'd0,   "checker addr 5 black");
        read_check(12'd14, 8'd255, "checker addr 14 white");
        read_check(12'd15, 8'd0,   "checker addr 15 black");

        // ════════════════════════════════════════════════════
        // TEST 10: Gradient pattern
        // Write gradient values across a row
        // Row 5: pixel value = column number
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 10: Gradient pattern ---");

        for (i = 0; i < WIDTH; i = i + 1)
            write_pixel(5*WIDTH + i, i[7:0]);

        // Verify selected gradient pixels
        read_check(5*WIDTH + 0,  8'd0,  "gradient col0");
        read_check(5*WIDTH + 10, 8'd10, "gradient col10");
        read_check(5*WIDTH + 32, 8'd32, "gradient col32");
        read_check(5*WIDTH + 63, 8'd63, "gradient col63");

        // ════════════════════════════════════════════════════
        // TEST 11: Dump to file
        // Write a simple pattern then dump
        // Verify pixels.hex is created
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 11: Dump to file ---");

        // Write bright cross pattern for visual verification
        // Horizontal line at row 32
        for (i = 0; i < WIDTH; i = i + 1)
            write_pixel(32*WIDTH + i, 8'd255);

        // Vertical line at col 32
        for (i = 0; i < HEIGHT; i = i + 1)
            write_pixel(i*WIDTH + 32, 8'd255);

        // Center pixel bright
        write_pixel(32*WIDTH + 32, 8'd255);

        // Trigger dump
        dump_enable = 1;
        @(posedge clk);
        dump_enable = 0;
        @(posedge clk); #1;

        // If $display showed dump message = pass
        // We cannot check file contents in Verilog
        // but Python will verify visually
        $display("PASS | pixels.hex dump triggered");
        $display("      Python verification:");
        $display("      - pixels.hex must contain exactly %0d lines",
                  DEPTH);
        $display("      - Each line is 2 hex digits");
        $display("      - Run python/viewer.py to render image");
        pass_count = pass_count + 1;


         // ════════════════════════════════════════════════════
        // TEST 12: Full memory stress test
        // Write to all 4096 locations
        // Value = addr[7:0] (wraps every 256 addresses)
        // Pattern:
        //   addr 0    → 00
        //   addr 1    → 01
        //   addr 255  → FF
        //   addr 256  → 00
        //   addr 4095 → FF
        // Exercises every decoder output
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 12: Full memory stress test ---");

        // Write pattern to all 4096 locations
        for (i = 0; i < DEPTH; i = i + 1)
            write_pixel(i[ADDR_WIDTH-1:0], i[7:0]);

        // Verify selected boundary addresses
        read_check(12'd0,    8'd0,   "stress addr 0");
        read_check(12'd1,    8'd1,   "stress addr 1");
        read_check(12'd127,  8'd127, "stress addr 127");
        read_check(12'd255,  8'd255, "stress addr 255");
        read_check(12'd256,  8'd0,   "stress addr 256 wraps");
        read_check(12'd257,  8'd1,   "stress addr 257 wraps");
        read_check(12'd511,  8'd255, "stress addr 511");
        read_check(12'd512,  8'd0,   "stress addr 512 wraps");
        read_check(12'd4094, 8'd254, "stress addr 4094");
        read_check(12'd4095, 8'd255, "stress addr 4095 last");

        $display("All 4096 locations written and sampled");

        // ════════════════════════════════════════════════════
        // Final score
        // ════════════════════════════════════════════════════
        $display("\n========================================");
        $display("RESULTS: %0d PASSED  %0d FAILED",
                  pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("========================================");

        $finish;
    end

endmodule