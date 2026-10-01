`timescale 1ns/1ps

// ============================================================
// Renderer
// Drives the GPU to compute pixel colors for all pixels
//
// Processes pixels in batches of 8 simultaneously
// Each batch:
//   1. Loads x,y coordinates into 8 shader cores
//   2. Dispatches shader program instructions
//   3. Reads results and writes to framebuffer
//
// Register conventions for all shader programs:
//   R0 → x coordinate (column)
//   R1 → y coordinate (row)
//   R2 → scratch
//   R3 → scratch
//   R4 → scratch
//   R5 → final pixel color output for arithmetic shaders
          //negative_flag → conditional output for comparison-based shaders
//   R6 → constant preloaded per program (threshold etc)
//   R7 → constant 255 (white)
//   R8 → constant 0   (black)
//
// Address calculation:
//   addr = y * WIDTH + x
//   WIDTH = 64 is intentionally a power of two
//   x = addr % 64 = addr[5:0]   (lower 6 bits)
//   y = addr / 64 = addr >> 6   (upper bits)
//   Behavioral % and / used for clarity
//   Synthesizer optimizes to bit select and shift for power-of-2
//
// Shader programs:
//   PROG_DOT    → visualization: R5 = 2*x*y
//   PROG_SHADE  → flat triangle: white if x+y < 64
//   PROG_MANDEL → Mandelbrot-inspired: R5 = x2+y2+x
//
// Conditional pixel color (for triangle shader):
//   negative_flag from gpu_top used in WRITE_FB state
//   Renderer reads flag and selects 255 or 0
//   This is correct architectural separation:
//     shader computes comparison result
//     renderer acts on the flag
//
// FSM states:
//   IDLE     → waiting for start
//   LOAD_X   → loading x coordinates into R0
//   LOAD_Y   → loading y coordinates into R1
//   LOAD_K   → loading program constants into R6,R7,R8
//   DISPATCH → running shader instructions
//   WRITE_FB → writing 8 pixel results to framebuffer
//   NEXT     → advance pixel_base by 8
//   DUMP     → dump framebuffer to pixels.hex
//   DONE_ST  → signal completion
// ============================================================

module renderer #(
    parameter WIDTH  = 64,
    parameter HEIGHT = 64
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [1:0]  prog_select,
    output reg         done,

    // Instruction stream to gpu_top warp scheduler
    output reg  [15:0] instruction_in,
    output reg         instr_valid_in,
    output reg  [1:0]  acc_ctrl_in,
    input  wire        instr_advance,

    // Data loading interface to gpu_top
    output reg  [7:0]  load_en_bus,
    output reg  [3:0]  load_addr,
    output reg  [7:0]  load_data [0:7],

    // Results and flags from gpu_top
    input  wire [7:0]  result_bus    [0:7],
    input  wire [7:0]  negative_bus,   // used for conditional color

    // Framebuffer interface
    output reg         fb_write_enable,
    output reg [ADDR_WIDTH-1:0] fb_addr,
    output reg  [7:0]  fb_pixel_in,
    output reg         fb_dump
);

    // ── Derived parameters ────────────────────────────────────
    localparam DEPTH      = WIDTH * HEIGHT;
    localparam ADDR_WIDTH = $clog2(DEPTH);

    // ── Program select constants ──────────────────────────────
    localparam PROG_DOT    = 2'b00;
    localparam PROG_SHADE  = 2'b01;
    localparam PROG_MANDEL = 2'b10;

    // ── FSM state encoding ────────────────────────────────────
    localparam IDLE     = 4'b0000;
    localparam LOAD_X   = 4'b0001;
    localparam LOAD_Y   = 4'b0010;
    localparam LOAD_K   = 4'b0011;  // load constants
    localparam DISPATCH = 4'b0100;
    localparam WRITE_FB = 4'b0101;
    localparam NEXT     = 4'b0110;
    localparam DUMP     = 4'b0111;
    localparam DONE_ST  = 4'b1000;

    reg [3:0] state;

    // ── Pixel tracking ────────────────────────────────────────
    reg [ADDR_WIDTH-1:0] pixel_base;  // first addr of current batch
    reg [3:0]            write_idx;   // which core writing to FB now (4-bit to reach 8)
    reg [2:0]            load_k_step; // which constant loading now

    // ── Shader program storage ────────────────────────────────
    // Behavioral initialization — not synthesizable ROM
    // Loaded once at start based on prog_select
    reg [15:0] prog_instr [0:7];
    reg [1:0]  prog_acc   [0:7];
    reg [3:0]  prog_len;              // 4-bit supports 0-8 instructions
    reg [3:0]  instr_idx;

    // Constants to preload per program
    // R6 = threshold constant
    // R7 = white (255)
    // R8 = black (0)
    reg [7:0]  const_r6;
    reg        use_negative_flag;     // 1 = use flag for color select

    // ── Shader program loader ─────────────────────────────────
    task load_program;
        input [1:0] sel;
        integer m;
        begin
            // Clear all slots first
            for (m = 0; m < 8; m = m + 1) begin
                prog_instr[m] = 16'b0;
                prog_acc[m]   = 2'b00;
            end

            case (sel)

                PROG_DOT: begin
                    // Dot product visualization
                    // Computes R5 = 2 * x * y
                    // R0=x R1=y
                    // MUL R2,R0,R1  → R2 = x*y
                    // ADD R5,R2,R2  → R5 = 2*x*y
                    // Pixel brightness proportional to 2xy
                    // Produces X-shaped gradient pattern
                    prog_instr[0] = 16'b1011_0010_0000_0001; // MUL R2,R0,R1
                    prog_instr[1] = 16'b0000_0101_0010_0010; // ADD R5,R2,R2
                    prog_acc[0]   = 2'b00;
                    prog_acc[1]   = 2'b00;
                    prog_len      = 4'd2;
                    const_r6          = 8'd0;
                    use_negative_flag = 0;
                end

                PROG_SHADE: begin
                    // Flat shaded triangle
                    // White pixels where x + y < 64
                    // R0=x R1=y R6=64 (threshold preloaded)
                    // ADD R2,R0,R1   → R2 = x+y
                    // SUB R3,R2,R6   → R3 = (x+y) - 64
                    // if negative_flag → inside → white(255)
                    // else             → outside → black(0)
                    // Color selected by renderer using negative_bus
                    prog_instr[0] = 16'b0000_0010_0000_0001; // ADD R2,R0,R1
                    prog_instr[1] = 16'b0001_0011_0010_0110; // SUB R3,R2,R6
                    prog_acc[0]   = 2'b00;
                    prog_acc[1]   = 2'b00;
                    prog_len      = 4'd2;
                    const_r6          = 8'd64; // triangle threshold
                    use_negative_flag = 1;     // renderer reads flag
                end

                PROG_MANDEL: begin
                    // Mandelbrot-inspired arithmetic demo
                    // Computes R5 = x2 + y2 + x
                    // Not a true Mandelbrot (no iteration loop)
                    // Produces radial gradient pattern
                    // R0=x R1=y
                    // MUL R2,R0,R0  → R2 = x*x
                    // MUL R3,R1,R1  → R3 = y*y
                    // ADD R4,R2,R3  → R4 = x2+y2
                    // ADD R5,R4,R0  → R5 = x2+y2+x
                    prog_instr[0] = 16'b1011_0010_0000_0000; // MUL R2,R0,R0
                    prog_instr[1] = 16'b1011_0011_0001_0001; // MUL R3,R1,R1
                    prog_instr[2] = 16'b0000_0100_0010_0011; // ADD R4,R2,R3
                    prog_instr[3] = 16'b0000_0101_0100_0000; // ADD R5,R4,R0
                    prog_acc[0]   = 2'b00;
                    prog_acc[1]   = 2'b00;
                    prog_acc[2]   = 2'b00;
                    prog_acc[3]   = 2'b00;
                    prog_len      = 4'd4;
                    const_r6          = 8'd0;
                    use_negative_flag = 0;
                end

                default: begin
                    prog_instr[0] = 16'b0;
                    prog_acc[0]   = 2'b00;
                    prog_len      = 4'd1;
                    const_r6          = 8'd0;
                    use_negative_flag = 0;
                end

            endcase
        end
    endtask

    // ── Main FSM ──────────────────────────────────────────────
    integer k;

    always @(posedge clk) begin
        if (reset) begin
            state           <= IDLE;
            done            <= 0;
            pixel_base      <= 0;
            write_idx       <= 0;
            load_k_step     <= 0;
            instr_idx       <= 0;
            load_en_bus     <= 8'h00;
            load_addr       <= 0;
            instr_valid_in  <= 0;
            acc_ctrl_in     <= 2'b00;
            fb_write_enable <= 0;
            fb_dump         <= 0;
            fb_addr         <= 0;
            fb_pixel_in     <= 0;
            for (k=0; k<8; k=k+1) load_data[k] <= 0;
        end else begin

            // Defaults every cycle
            load_en_bus     <= 8'h00;
            instr_valid_in  <= 0;
            acc_ctrl_in     <= 2'b00;
            fb_write_enable <= 0;
            fb_dump         <= 0;
            done            <= 0;

            case (state)

                // ── IDLE ─────────────────────────────────────
                IDLE: begin
                    pixel_base <= 0;
                    if (start) begin
                        load_program(prog_select);
                        state <= LOAD_X;
                    end
                end

                // ── LOAD_X ───────────────────────────────────
                // Load x coordinate into R0 of all 8 cores
                // x[core i] = (pixel_base + i) % WIDTH
                // For WIDTH=64: x = lower 6 bits of address
                LOAD_X: begin
                    load_addr   <= 4'd0;
                    load_en_bus <= 8'hFF;
                    for (k=0; k<8; k=k+1)
                        load_data[k] <= (pixel_base + k) % WIDTH;
                    state <= LOAD_Y;
                end

                // ── LOAD_Y ───────────────────────────────────
                // Load y coordinate into R1 of all 8 cores
                // y[core i] = (pixel_base + i) / WIDTH
                // For WIDTH=64: y = upper bits of address
                LOAD_Y: begin
                    load_addr   <= 4'd1;
                    load_en_bus <= 8'hFF;
                    for (k=0; k<8; k=k+1)
                        load_data[k] <= (pixel_base + k) / WIDTH;
                    load_k_step <= 0;
                    state       <= LOAD_K;
                end

                // ── LOAD_K ───────────────────────────────────
                // Load program constants into R6, R7, R8
                // R6 = threshold (program specific)
                // R7 = 255 white constant
                // R8 = 0   black constant
                // Takes 3 cycles, one register per cycle
                LOAD_K: begin
                    load_en_bus <= 8'hFF;
                    case (load_k_step)
                        3'd0: begin
                            load_addr <= 4'd6;
                            for (k=0; k<8; k=k+1)
                                load_data[k] <= const_r6;
                            load_k_step <= 1;
                        end
                        3'd1: begin
                            load_addr <= 4'd7;
                            for (k=0; k<8; k=k+1)
                                load_data[k] <= 8'd255;
                            load_k_step <= 2;
                        end
                        3'd2: begin
                            load_addr <= 4'd8;  // R8
                            for (k=0; k<8; k=k+1)
                                load_data[k] <= 8'd0;
                            instr_idx   <= 0;
                            state       <= DISPATCH;
                        end
                        default: state <= DISPATCH;
                    endcase
                end

                // ── DISPATCH ─────────────────────────────────
                // Send shader instructions one by one
                // Wait for instr_advance before sending next
                DISPATCH: begin
                    if (instr_idx < prog_len) begin
                        instruction_in <= prog_instr[instr_idx];
                        acc_ctrl_in    <= prog_acc[instr_idx];
                        instr_valid_in <= 1;
                        if (instr_advance)
                            instr_idx <= instr_idx + 1;
                    end else begin
                        instr_valid_in <= 0;
                        write_idx      <= 0;
                        state          <= WRITE_FB;
                    end
                end

                // ── WRITE_FB ─────────────────────────────────
                // Write one pixel per cycle to framebuffer
                // For triangle shader uses negative_bus flag
                // to select white or black pixel color
                WRITE_FB: begin
                    if (write_idx < 8) begin
                        fb_write_enable <= 1;
                        fb_addr         <= pixel_base + write_idx;

                        if (use_negative_flag) begin
                            // Triangle shader
                            // negative_bus[i]=1 → inside → white
                            // negative_bus[i]=0 → outside → black
                            case (write_idx)
                                0: fb_pixel_in <= negative_bus[0] ?
                                                  8'd255 : 8'd0;
                                1: fb_pixel_in <= negative_bus[1] ?
                                                  8'd255 : 8'd0;
                                2: fb_pixel_in <= negative_bus[2] ?
                                                  8'd255 : 8'd0;
                                3: fb_pixel_in <= negative_bus[3] ?
                                                  8'd255 : 8'd0;
                                4: fb_pixel_in <= negative_bus[4] ?
                                                  8'd255 : 8'd0;
                                5: fb_pixel_in <= negative_bus[5] ?
                                                  8'd255 : 8'd0;
                                6: fb_pixel_in <= negative_bus[6] ?
                                                  8'd255 : 8'd0;
                                7: fb_pixel_in <= negative_bus[7] ?
                                                  8'd255 : 8'd0;
                                default: fb_pixel_in <= 8'd0;
                            endcase
                        end else begin
                            // Other shaders use R5 directly
                            case (write_idx)
                                0: fb_pixel_in <= result_bus[0];
                                1: fb_pixel_in <= result_bus[1];
                                2: fb_pixel_in <= result_bus[2];
                                3: fb_pixel_in <= result_bus[3];
                                4: fb_pixel_in <= result_bus[4];
                                5: fb_pixel_in <= result_bus[5];
                                6: fb_pixel_in <= result_bus[6];
                                7: fb_pixel_in <= result_bus[7];
                                default: fb_pixel_in <= 8'd0;
                            endcase
                        end

                        write_idx <= write_idx + 1;
                    end else begin
                        fb_write_enable <= 0;
                        state           <= NEXT;
                    end
                end

                // ── NEXT ─────────────────────────────────────
                // Advance to next batch of 8 pixels
                // If all pixels done go to DUMP
                NEXT: begin
                    if (pixel_base + 8 < DEPTH) begin
                        pixel_base <= pixel_base + 8;
                        state      <= LOAD_X;
                    end else begin
                        state <= DUMP;
                    end
                end

                // ── DUMP ─────────────────────────────────────
                // Trigger framebuffer dump to pixels.hex
                DUMP: begin
                    fb_dump <= 1;
                    state   <= DONE_ST;
                end

                // ── DONE_ST ──────────────────────────────────
                DONE_ST: begin
                    done  <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule