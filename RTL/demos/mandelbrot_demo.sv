`timescale 1ns/1ps

// ============================================================
// True Mandelbrot Demo
//
// Uses dedicated mandelbrot_unit for fixed-point computation.
// 8 units run in parallel (one per pixel in a batch).
// Results written directly to a behavioral pixel store and
// then dumped to pixels.hex for Python visualization.
//
// Fixed-point format: Q8.8 signed (value = raw/256)
//
// Complex plane:
//   Real: -2.0 to +0.5  (64 pixels, step = 2.5/64*256 = 10)
//   Imag: -1.25 to +1.25 (64 pixels, step = 2.5/64*256 = 10)
//
// MAX_ITER = 64
// ============================================================

module mandelbrot_demo;

    localparam WIDTH    = 64;
    localparam HEIGHT   = 64;
    localparam DEPTH    = WIDTH * HEIGHT;   // 4096
    localparam MAX_ITER = 64;

    // Each iteration = MUL + CHECK = 2 cycles.  Extra margin for transitions.
    localparam TIMEOUT_LIMIT = MAX_ITER * 2 + 10;

    // ── Clock ─────────────────────────────────────────────────
    reg clk, reset;
    initial clk = 0;
    always #5 clk = ~clk;

    // ── 8 Mandelbrot units — explicit ports (no array indexing) ──
    // Avoids Icarus Verilog unpacked-array dynamic-index issues
    reg        start0, start1, start2, start3;
    reg        start4, start5, start6, start7;

    reg signed [15:0] cr0, cr1, cr2, cr3, cr4, cr5, cr6, cr7;
    reg signed [15:0] ci0, ci1, ci2, ci3, ci4, ci5, ci6, ci7;

    wire [7:0] pout0, pout1, pout2, pout3, pout4, pout5, pout6, pout7;
    wire [7:0] done_bus; // [7] = unit7 done, [0] = unit0 done

    mandelbrot_unit #(.MAX_ITER(MAX_ITER)) u0(.clk(clk),.reset(reset),.start(start0),.c_real(cr0),.c_imag(ci0),.pixel_out(pout0),.done(done_bus[0]));
    mandelbrot_unit #(.MAX_ITER(MAX_ITER)) u1(.clk(clk),.reset(reset),.start(start1),.c_real(cr1),.c_imag(ci1),.pixel_out(pout1),.done(done_bus[1]));
    mandelbrot_unit #(.MAX_ITER(MAX_ITER)) u2(.clk(clk),.reset(reset),.start(start2),.c_real(cr2),.c_imag(ci2),.pixel_out(pout2),.done(done_bus[2]));
    mandelbrot_unit #(.MAX_ITER(MAX_ITER)) u3(.clk(clk),.reset(reset),.start(start3),.c_real(cr3),.c_imag(ci3),.pixel_out(pout3),.done(done_bus[3]));
    mandelbrot_unit #(.MAX_ITER(MAX_ITER)) u4(.clk(clk),.reset(reset),.start(start4),.c_real(cr4),.c_imag(ci4),.pixel_out(pout4),.done(done_bus[4]));
    mandelbrot_unit #(.MAX_ITER(MAX_ITER)) u5(.clk(clk),.reset(reset),.start(start5),.c_real(cr5),.c_imag(ci5),.pixel_out(pout5),.done(done_bus[5]));
    mandelbrot_unit #(.MAX_ITER(MAX_ITER)) u6(.clk(clk),.reset(reset),.start(start6),.c_real(cr6),.c_imag(ci6),.pixel_out(pout6),.done(done_bus[6]));
    mandelbrot_unit #(.MAX_ITER(MAX_ITER)) u7(.clk(clk),.reset(reset),.start(start7),.c_real(cr7),.c_imag(ci7),.pixel_out(pout7),.done(done_bus[7]));

    // ── Behavioral pixel store ────────────────────────────────
    reg [7:0] pixels [0:DEPTH-1];

    // ── Fixed-point mapping ───────────────────────────────────
    // Q8.8: value * 256 = integer
    // Real: -2.0..+0.5  → step = 2.5/64*256 = 10
    // Imag: -1.25..+1.25 → step = 2.5/64*256 = 10
    localparam signed [15:0] REAL_START = -16'sd512;
    localparam signed [15:0] IMAG_START = -16'sd320;
    localparam STEP = 10;

    // ── Simulation variables ──────────────────────────────────
    integer pixel_base, px, py, i, timeout, total_done, fh;
    reg [7:0] done_latch;

    // ── Helper tasks ──────────────────────────────────────────

    // Set c values for 8 pixels starting at base pixel index b
    task set_c;
        input integer b;
        integer lx, ly;
        begin
            lx = (b+0) % WIDTH; ly = (b+0) / WIDTH;
            cr0 = REAL_START + lx*STEP; ci0 = IMAG_START + ly*STEP;
            lx = (b+1) % WIDTH; ly = (b+1) / WIDTH;
            cr1 = REAL_START + lx*STEP; ci1 = IMAG_START + ly*STEP;
            lx = (b+2) % WIDTH; ly = (b+2) / WIDTH;
            cr2 = REAL_START + lx*STEP; ci2 = IMAG_START + ly*STEP;
            lx = (b+3) % WIDTH; ly = (b+3) / WIDTH;
            cr3 = REAL_START + lx*STEP; ci3 = IMAG_START + ly*STEP;
            lx = (b+4) % WIDTH; ly = (b+4) / WIDTH;
            cr4 = REAL_START + lx*STEP; ci4 = IMAG_START + ly*STEP;
            lx = (b+5) % WIDTH; ly = (b+5) / WIDTH;
            cr5 = REAL_START + lx*STEP; ci5 = IMAG_START + ly*STEP;
            lx = (b+6) % WIDTH; ly = (b+6) / WIDTH;
            cr6 = REAL_START + lx*STEP; ci6 = IMAG_START + ly*STEP;
            lx = (b+7) % WIDTH; ly = (b+7) / WIDTH;
            cr7 = REAL_START + lx*STEP; ci7 = IMAG_START + ly*STEP;
        end
    endtask

    // Pulse start HIGH for 1 clock cycle on all 8 units
    task pulse_start;
        begin
            @(posedge clk);
            start0=1; start1=1; start2=1; start3=1;
            start4=1; start5=1; start6=1; start7=1;
            @(posedge clk);
            start0=0; start1=0; start2=0; start3=0;
            start4=0; start5=0; start6=0; start7=0;
        end
    endtask

    // Wait until all 8 done pulses have been captured (or timeout)
    task wait_all_done;
        input integer base;
        begin
            done_latch = 8'h00;
            timeout    = 0;
            while (done_latch !== 8'hFF) begin
                @(posedge clk);
                if (done_bus[0]) done_latch[0] = 1'b1;
                if (done_bus[1]) done_latch[1] = 1'b1;
                if (done_bus[2]) done_latch[2] = 1'b1;
                if (done_bus[3]) done_latch[3] = 1'b1;
                if (done_bus[4]) done_latch[4] = 1'b1;
                if (done_bus[5]) done_latch[5] = 1'b1;
                if (done_bus[6]) done_latch[6] = 1'b1;
                if (done_bus[7]) done_latch[7] = 1'b1;
                timeout = timeout + 1;
                if (timeout >= TIMEOUT_LIMIT) begin
                    $display("ERROR: timeout at pixel_base=%0d done_latch=%08b",
                              base, done_latch);
                    $finish;
                end
            end
        end
    endtask

    // Capture pixel results into behavioral array at offset b
    task capture_pixels;
        input integer b;
        begin
            pixels[b+0] = pout0;
            pixels[b+1] = pout1;
            pixels[b+2] = pout2;
            pixels[b+3] = pout3;
            pixels[b+4] = pout4;
            pixels[b+5] = pout5;
            pixels[b+6] = pout6;
            pixels[b+7] = pout7;
        end
    endtask

    // ── Main simulation ───────────────────────────────────────
    initial begin
        // VCD dump disabled at gate level — re-enable for waveform debug
        // $dumpfile("mandelbrot.vcd");
        // $dumpvars(0, mandelbrot_demo);

        // Reset all signals
        reset  = 1;
        start0 = 0; start1 = 0; start2 = 0; start3 = 0;
        start4 = 0; start5 = 0; start6 = 0; start7 = 0;
        cr0=0; cr1=0; cr2=0; cr3=0; cr4=0; cr5=0; cr6=0; cr7=0;
        ci0=0; ci1=0; ci2=0; ci3=0; ci4=0; ci5=0; ci6=0; ci7=0;
        for (i = 0; i < DEPTH; i = i + 1) pixels[i] = 8'h00;

        repeat(4) @(posedge clk);
        reset = 0;
        // 2 settle cycles so all FSMs land cleanly in IDLE
        repeat(2) @(posedge clk);

        $display("============================================");
        $display("  Mini GPU - True Mandelbrot Demo");
        $display("============================================");
        $display("Format:     Q8.8 signed fixed-point");
        $display("Real axis:  -2.0 to +0.5");
        $display("Imag axis:  -1.25 to +1.25");
        $display("Max iter:   %0d", MAX_ITER);
        $display("Resolution: %0d x %0d", WIDTH, HEIGHT);
        $display("Cores:      8 parallel Mandelbrot units");
        $display("--------------------------------------------");
        $display("Rendering...");

        total_done = 0;
        pixel_base = 0;

        while (pixel_base < DEPTH) begin
            set_c(pixel_base);
            pulse_start;
            wait_all_done(pixel_base);
            capture_pixels(pixel_base);

            total_done = total_done + 8;
            pixel_base = pixel_base + 8;

            if (total_done % 512 == 0)
                $display("  Progress: %0d / %0d pixels", total_done, DEPTH);
        end

        // Dump pixels.hex
        fh = $fopen("pixels.hex", "w");
        if (fh == 0) begin
            $display("ERROR: Cannot open pixels.hex for writing");
        end else begin
            for (i = 0; i < DEPTH; i = i + 1)
                $fwrite(fh, "%02x\n", pixels[i]);
            $fclose(fh);
            $display("Framebuffer dumped: %0d pixels to pixels.hex", DEPTH);
        end

        $display("--------------------------------------------");
        $display("Render complete!");

        $finish;
    end

endmodule