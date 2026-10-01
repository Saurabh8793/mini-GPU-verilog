`timescale 1ns/1ps

// ============================================================
// Renderer Testbench
// Tests renderer FSM in complete isolation
// All GPU responses simulated internally
// ============================================================

module renderer_tb;

    localparam WIDTH      = 64;
    localparam HEIGHT     = 64;
    localparam DEPTH      = WIDTH * HEIGHT;
    localparam ADDR_WIDTH = $clog2(DEPTH);

    // ── Clock and reset ───────────────────────────────────────
    reg clk, reset;
    initial clk = 0;
    always #5 clk = ~clk;

    // ── DUT ports ─────────────────────────────────────────────
    reg        start;
    reg [1:0]  prog_select;

    wire        done;
    wire [15:0] instruction_in;
    wire        instr_valid_in;
    wire [1:0]  acc_ctrl_in;
    wire [7:0]  load_en_bus;
    wire [3:0]  load_addr;
    wire [7:0]  load_data   [0:7];
    wire        fb_write_enable;
    wire [11:0] fb_addr;
    wire [7:0]  fb_pixel_in;
    wire        fb_dump;

    // ── Simulated GPU signals ─────────────────────────────────
    reg        instr_advance;
    reg [7:0]  result_bus   [0:7];
    reg [7:0]  negative_bus;

    // ── DUT ───────────────────────────────────────────────────
    renderer #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) uut(
        .clk(clk),
        .reset(reset),
        .start(start),
        .prog_select(prog_select),
        .done(done),
        .instruction_in(instruction_in),
        .instr_valid_in(instr_valid_in),
        .acc_ctrl_in(acc_ctrl_in),
        .instr_advance(instr_advance),
        .load_en_bus(load_en_bus),
        .load_addr(load_addr),
        .load_data(load_data),
        .result_bus(result_bus),
        .negative_bus(negative_bus),
        .fb_write_enable(fb_write_enable),
        .fb_addr(fb_addr),
        .fb_pixel_in(fb_pixel_in),
        .fb_dump(fb_dump)
    );

    // ── Test counters ─────────────────────────────────────────
    integer pass_count;
    integer fail_count;
    integer i, j;

    // ── Framebuffer model ─────────────────────────────────────
    reg [7:0] fb_model [0:DEPTH-1];

    always @(posedge clk) begin
        if (fb_write_enable)
            fb_model[fb_addr] <= fb_pixel_in;
    end

    // ── GPU model ─────────────────────────────────────────────
    // Tracks loaded registers per core
    // Computes mathematically correct shader results
    // Combinational output so results are always current

    reg [7:0] core_r0 [0:7];
    reg [7:0] core_r1 [0:7];
    reg [7:0] core_r6 [0:7];

    // Register capture: update core registers on posedge when load fires
    always @(posedge clk) begin
        if (load_en_bus == 8'hFF) begin
            case (load_addr)
                4'd0: for (j=0; j<8; j=j+1)
                          core_r0[j] <= load_data[j];
                4'd1: for (j=0; j<8; j=j+1)
                          core_r1[j] <= load_data[j];
                4'd6: for (j=0; j<8; j=j+1)
                          core_r6[j] <= load_data[j];
                default: ;
            endcase
        end
    end

    // Generate instr_advance one cycle after instr_valid_in
    always @(posedge clk) begin
        instr_advance <= instr_valid_in;
    end

    // Compute shader outputs COMBINATIONALLY — no lag on result_bus
    always @(*) begin
        case (prog_select)
            2'b00: begin
                // PROG_DOT: result = 2 * x * y (lower 8 bits)
                for (j=0; j<8; j=j+1)
                    result_bus[j] = (core_r0[j] * core_r1[j] * 2) & 8'hFF;
                negative_bus = 8'h00;
            end
            2'b01: begin
                // PROG_SHADE: pixel white if x+y < 64
                for (j=0; j<8; j=j+1) begin
                    result_bus[j]   = 8'd0;
                    negative_bus[j] =
                        ((core_r0[j] + core_r1[j]) < 64) ? 1'b1 : 1'b0;
                end
            end
            2'b10: begin
                // PROG_MANDEL: result = x2 + y2 + x (lower 8 bits)
                for (j=0; j<8; j=j+1)
                    result_bus[j] =
                        (core_r0[j]*core_r0[j] +
                         core_r1[j]*core_r1[j] +
                         core_r0[j]) & 8'hFF;
                negative_bus = 8'h00;
            end
            default: begin
                for (j=0; j<8; j=j+1) result_bus[j] = 8'd0;
                negative_bus = 8'h00;
            end
        endcase
    end

    // ── Tasks ─────────────────────────────────────────────────

    task do_reset;
        begin
            reset = 1;
            start = 0;
            repeat(4) @(posedge clk);
            reset = 0;
            @(posedge clk);
            // Clear framebuffer model
            for (i=0; i<DEPTH; i=i+1)
                fb_model[i] = 8'h00;
            // Clear GPU model core registers
            for (i=0; i<8; i=i+1) begin
                core_r0[i] = 8'd0;
                core_r1[i] = 8'd0;
                core_r6[i] = 8'd0;
            end
        end
    endtask

    // Assert start on negedge so renderer sees it on next posedge
    // This avoids the race condition between TB and DUT
    task pulse_start;
        begin
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
        end
    endtask

    // Run complete render and wait for done pulse
    // Samples done AFTER each posedge to avoid missing 1-cycle pulse
    // Timeout of 30000 cycles is well above the ~10240 cycles needed
    task run_renderer;
        input [1:0] prog;
        integer     timeout;
        reg         saw_done;
        begin
            prog_select = prog;
            pulse_start;
            timeout  = 0;
            saw_done = 0;
            @(posedge clk);
            while (!saw_done && timeout < 30000) begin
                @(posedge clk);
                if (done) saw_done = 1;
                timeout = timeout + 1;
            end
            if (!saw_done)
                $display("WARNING: render timeout prog=%0d", prog);
            else
                @(posedge clk); // one extra cycle after done
        end
    endtask

    task pass;
        input [127:0] label;
        begin
            $display("PASS | %s", label);
            pass_count = pass_count + 1;
        end
    endtask

    task fail;
        input [127:0] label;
        input integer  got;
        input integer  exp;
        begin
            $display("FAIL | %s | got=%0d exp=%0d", label, got, exp);
            fail_count = fail_count + 1;
        end
    endtask

    task check_eq;
        input integer  actual;
        input integer  expected;
        input [127:0]  label;
        begin
            if (actual === expected) pass(label);
            else fail(label, actual, expected);
        end
    endtask

    task check_pixel;
        input [ADDR_WIDTH-1:0] addr;
        input [7:0]            expected;
        input [127:0]          label;
        begin
            if (fb_model[addr] === expected) begin
                $display("PASS | %-40s addr=%0d val=%0d",
                          label, addr, fb_model[addr]);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | %-40s addr=%0d got=%0d exp=%0d",
                          label, addr, fb_model[addr], expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── Test loop helper: wait for N occurrences of a clock event ──
    // These tasks avoid using named-block disable which skips checks

    // ── Main test ─────────────────────────────────────────────
    initial begin
        $dumpfile("renderer.vcd");
        $dumpvars(0, renderer_tb);

        pass_count    = 0;
        fail_count    = 0;
        start         = 0;
        prog_select   = 0;
        instr_advance = 0;
        negative_bus  = 0;
        for (i=0; i<8;     i=i+1) result_bus[i] = 0;
        for (i=0; i<8;     i=i+1) core_r0[i]    = 0;
        for (i=0; i<8;     i=i+1) core_r1[i]    = 0;
        for (i=0; i<8;     i=i+1) core_r6[i]    = 0;
        for (i=0; i<DEPTH; i=i+1) fb_model[i]   = 0;

        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 1: FSM leaves IDLE — load_en_bus asserts
        // Start renderer, wait 1 posedge, sample on negedge
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 1: FSM leaves IDLE ---");
        prog_select = 2'b00;
        pulse_start;
        @(posedge clk);   // renderer processes start, moves to LOAD_X
        @(negedge clk);   // stable sampling point

        check_eq(load_en_bus, 8'hFF, "load_en_bus=FF in LOAD_X");
        check_eq(load_addr,   4'd0,  "load_addr=R0 in LOAD_X");
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 2: LOAD_X — x coordinates for batch 0
        // pixel_base=0: x[i] = i for i=0..7
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 2: LOAD_X batch 0 x coordinates ---");
        prog_select = 2'b00;
        pulse_start;
        @(posedge clk);  // in LOAD_X
        @(negedge clk);  // sample

        check_eq(load_en_bus,  8'hFF, "LOAD_X en=FF");
        check_eq(load_addr,    4'd0,  "LOAD_X addr=R0");
        check_eq(load_data[0], 8'd0,  "x[0]=0");
        check_eq(load_data[1], 8'd1,  "x[1]=1");
        check_eq(load_data[2], 8'd2,  "x[2]=2");
        check_eq(load_data[3], 8'd3,  "x[3]=3");
        check_eq(load_data[4], 8'd4,  "x[4]=4");
        check_eq(load_data[5], 8'd5,  "x[5]=5");
        check_eq(load_data[6], 8'd6,  "x[6]=6");
        check_eq(load_data[7], 8'd7,  "x[7]=7");
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 3: LOAD_Y — y coordinates for batch 0
        // pixel_base=0: all pixels on row 0 so y=0
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 3: LOAD_Y batch 0 y coordinates ---");
        prog_select = 2'b00;
        pulse_start;
        @(posedge clk);  // LOAD_X
        @(posedge clk);  // LOAD_Y
        @(negedge clk);  // sample

        check_eq(load_en_bus,  8'hFF, "LOAD_Y en=FF");
        check_eq(load_addr,    4'd1,  "LOAD_Y addr=R1");
        for (i=0; i<8; i=i+1)
            check_eq(load_data[i], 8'd0, "y[i]=0 row0");
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 4: LOAD_K constants for PROG_SHADE
        // Step 0: R6=64  Step 1: R7=255  Step 2: R8=0
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 4: LOAD_K constants PROG_SHADE ---");
        prog_select = 2'b01; // PROG_SHADE uses R6=64
        pulse_start;
        @(posedge clk);  // LOAD_X
        @(posedge clk);  // LOAD_Y
        @(posedge clk);  // LOAD_K step 0
        @(negedge clk);
        check_eq(load_addr,    4'd6,  "LOAD_K R6 addr=6");
        check_eq(load_data[0], 8'd64, "R6=64 threshold");

        @(posedge clk);  // LOAD_K step 1
        @(negedge clk);
        check_eq(load_addr,    4'd7,   "LOAD_K R7 addr=7");
        check_eq(load_data[0], 8'd255, "R7=255 white");

        @(posedge clk);  // LOAD_K step 2
        @(negedge clk);
        check_eq(load_addr,    4'd8,  "LOAD_K R8 addr=8");
        check_eq(load_data[0], 8'd0,  "R8=0 black");
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 5: LOAD_K constants for PROG_DOT
        // R6=0 for dot program
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 5: LOAD_K constants PROG_DOT ---");
        prog_select = 2'b00;
        pulse_start;
        @(posedge clk);  // LOAD_X
        @(posedge clk);  // LOAD_Y
        @(posedge clk);  // LOAD_K step 0
        @(negedge clk);
        check_eq(load_data[0], 8'd0, "DOT R6=0");
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 6: DISPATCH PROG_DOT instruction sequence
        // Instructions: MUL R2,R0,R1 then ADD R5,R2,R2
        // Poll for instr_valid_in, capture opcodes, check AFTER loop
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 6: DISPATCH PROG_DOT sequence ---");
        begin
            // Capture each unique instruction by detecting when instr_advance
            // fires — that signals the renderer accepted the current instruction.
            // At the moment instr_advance=1, instruction_in holds the accepted instr.
            reg [3:0]  opcodes0, opcodes1;
            reg [15:0] prev_instr6;
            integer    idx6;
            reg        prev_valid6, done6;
            idx6 = 0; done6 = 0; prev_valid6 = 0;
            opcodes0 = 4'hF; opcodes1 = 4'hF;
            prev_instr6 = 16'hFFFF;
            prog_select = 2'b00;
            pulse_start;
            // Capture on rising edge of instr_valid_in (new instruction starts)
            repeat(200) begin
                @(posedge clk); @(negedge clk);
                // Rising edge of instr_valid_in = first cycle of each new dispatch
                if (!done6 && instr_valid_in && !prev_valid6) begin
                    if (idx6 == 0) opcodes0 = instruction_in[15:12];
                    if (idx6 == 1) opcodes1 = instruction_in[15:12];
                    idx6 = idx6 + 1;
                    if (idx6 == 2) done6 = 1;
                end
                // Also capture on instruction change while valid
                if (!done6 && instr_valid_in && prev_valid6 &&
                    instruction_in !== prev_instr6) begin
                    if (idx6 == 0) opcodes0 = instruction_in[15:12];
                    if (idx6 == 1) opcodes1 = instruction_in[15:12];
                    idx6 = idx6 + 1;
                    if (idx6 == 2) done6 = 1;
                end
                prev_valid6 = instr_valid_in;
                prev_instr6 = instruction_in;
            end
            check_eq(opcodes0, 4'b1011, "DOT instr0 MUL opcode");
            check_eq(opcodes1, 4'b0000, "DOT instr1 ADD opcode");
        end
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 7: DISPATCH PROG_SHADE sequence
        // Instructions: ADD R2,R0,R1 then SUB R3,R2,R6
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 7: DISPATCH PROG_SHADE sequence ---");
        begin
            reg [3:0]  s_op0, s_op1;
            reg [15:0] s_prev_instr;
            integer    s_idx;
            reg        s_prev_valid, s_done;
            s_idx = 0; s_done = 0; s_prev_valid = 0;
            s_op0 = 4'hF; s_op1 = 4'hF;
            s_prev_instr = 16'hFFFF;
            prog_select = 2'b01;
            pulse_start;
            repeat(200) begin
                @(posedge clk); @(negedge clk);
                if (!s_done && instr_valid_in && !s_prev_valid) begin
                    if (s_idx == 0) s_op0 = instruction_in[15:12];
                    if (s_idx == 1) s_op1 = instruction_in[15:12];
                    s_idx = s_idx + 1;
                    if (s_idx == 2) s_done = 1;
                end
                if (!s_done && instr_valid_in && s_prev_valid &&
                    instruction_in !== s_prev_instr) begin
                    if (s_idx == 0) s_op0 = instruction_in[15:12];
                    if (s_idx == 1) s_op1 = instruction_in[15:12];
                    s_idx = s_idx + 1;
                    if (s_idx == 2) s_done = 1;
                end
                s_prev_valid = instr_valid_in;
                s_prev_instr = instruction_in;
            end
            check_eq(s_op0, 4'b0000, "SHADE instr0 ADD");
            check_eq(s_op1, 4'b0001, "SHADE instr1 SUB");
        end
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 8: DISPATCH PROG_MANDEL sequence
        // Instructions: MUL MUL ADD ADD
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 8: DISPATCH PROG_MANDEL sequence ---");
        begin
            reg [3:0]  m_op0, m_op1, m_op2, m_op3;
            reg [15:0] m_prev_instr;
            integer    m_idx;
            reg        m_prev_valid, m_done;
            m_idx = 0; m_done = 0; m_prev_valid = 0;
            m_op0 = 4'hF; m_op1 = 4'hF;
            m_op2 = 4'hF; m_op3 = 4'hF;
            m_prev_instr = 16'hFFFF;
            prog_select = 2'b10;
            pulse_start;
            repeat(200) begin
                @(posedge clk); @(negedge clk);
                // Rising edge of instr_valid_in
                if (!m_done && instr_valid_in && !m_prev_valid) begin
                    if (m_idx == 0) m_op0 = instruction_in[15:12];
                    if (m_idx == 1) m_op1 = instruction_in[15:12];
                    if (m_idx == 2) m_op2 = instruction_in[15:12];
                    if (m_idx == 3) m_op3 = instruction_in[15:12];
                    m_idx = m_idx + 1;
                    if (m_idx == 4) m_done = 1;
                end
                // Instruction change while valid
                if (!m_done && instr_valid_in && m_prev_valid &&
                    instruction_in !== m_prev_instr) begin
                    if (m_idx == 0) m_op0 = instruction_in[15:12];
                    if (m_idx == 1) m_op1 = instruction_in[15:12];
                    if (m_idx == 2) m_op2 = instruction_in[15:12];
                    if (m_idx == 3) m_op3 = instruction_in[15:12];
                    m_idx = m_idx + 1;
                    if (m_idx == 4) m_done = 1;
                end
                m_prev_valid = instr_valid_in;
                m_prev_instr = instruction_in;
            end
            check_eq(m_op0, 4'b1011, "MANDEL instr0 MUL");
            check_eq(m_op1, 4'b1011, "MANDEL instr1 MUL");
            check_eq(m_op2, 4'b0000, "MANDEL instr2 ADD");
            check_eq(m_op3, 4'b0000, "MANDEL instr3 ADD");
        end
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 9: WRITE_FB — addresses 0-7 correct batch 0
        // Capture first 8 fb_write_enable pulses
        // Verify addresses sequential 0-7 and pixel values correct
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 9: WRITE_FB addresses 0-7 ---");
        begin
            reg [11:0] addrs9  [0:7];
            reg [7:0]  pixels9 [0:7];
            integer    w9_idx;
            w9_idx = 0;
            prog_select = 2'b00;
            pulse_start;
            // Wait for 8 FB writes — renderer dispatches then writes
            // Generous timeout of 1000 cycles
            repeat(1000) begin
                @(posedge clk); @(negedge clk);
                if (fb_write_enable && w9_idx < 8) begin
                    addrs9[w9_idx]  = fb_addr;
                    pixels9[w9_idx] = fb_pixel_in;
                    w9_idx = w9_idx + 1;
                end
            end
            for (i=0; i<8; i=i+1) begin
                check_eq(addrs9[i],  i,    "fb_addr sequential");
                // PROG_DOT row0: result = 2*x*0 = 0
                check_eq(pixels9[i], 8'd0, "pixel 2*x*0=0 row0");
            end
        end
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 10: WRITE_FB triangle shader batch 0
        // batch 0 all on row 0: x+y = x < 64, all inside → white
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 10: WRITE_FB triangle batch 0 white ---");
        begin
            reg [7:0] sp10 [0:7];
            integer   sp10_idx;
            sp10_idx = 0;
            prog_select = 2'b01;
            pulse_start;
            repeat(1000) begin
                @(posedge clk); @(negedge clk);
                if (fb_write_enable && sp10_idx < 8) begin
                    sp10[sp10_idx] = fb_pixel_in;
                    sp10_idx = sp10_idx + 1;
                end
            end
            for (i=0; i<8; i=i+1)
                check_eq(sp10[i], 8'd255, "batch0 triangle pixel white");
        end
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 11: NEXT state advances pixel_base by 8
        // Second batch should write addresses 8-15
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 11: NEXT pixel_base advances by 8 ---");
        begin
            reg [11:0] b2addr11 [0:7];
            integer    total11;
            integer    b2_idx11;
            total11  = 0;
            b2_idx11 = 0;
            prog_select = 2'b00;
            pulse_start;
            repeat(2000) begin
                @(posedge clk); @(negedge clk);
                if (fb_write_enable) begin
                    total11 = total11 + 1;
                    if (total11 > 8 && b2_idx11 < 8) begin
                        b2addr11[b2_idx11] = fb_addr;
                        b2_idx11 = b2_idx11 + 1;
                    end
                end
            end
            for (i=0; i<8; i=i+1)
                check_eq(b2addr11[i], 12'd8+i, "batch2 addr=8+i");
        end
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 12: Row boundary — pixel 56-63 vs 64-71
        // Batch pixel_base=56: x=56..63, y=0
        // Batch pixel_base=64: x=0..7,   y=1
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 12: Row boundary batch 7 and 8 ---");
        begin
            reg [7:0] lx_x0_bat7, lx_x7_bat7;
            reg [7:0] lx_x0_bat8, lx_x7_bat8;
            reg [7:0] ly_bat8 [0:7];
            integer   lx_seen12;
            reg       found_bat7, found_bat8, found_y1;
            lx_seen12 = 0;
            found_bat7 = 0; found_bat8 = 0; found_y1 = 0;
            lx_x0_bat7 = 8'hFF; lx_x7_bat7 = 8'hFF;
            lx_x0_bat8 = 8'hFF; lx_x7_bat8 = 8'hFF;
            prog_select = 2'b00;
            pulse_start;
            // Find 8th and 9th LOAD_X events and next LOAD_Y
            repeat(5000) begin
                @(posedge clk); @(negedge clk);
                if (load_en_bus===8'hFF && load_addr===4'd0) begin
                    lx_seen12 = lx_seen12 + 1;
                    if (lx_seen12 == 8 && !found_bat7) begin
                        lx_x0_bat7 = load_data[0];
                        lx_x7_bat7 = load_data[7];
                        found_bat7 = 1;
                    end
                    if (lx_seen12 == 9 && !found_bat8) begin
                        lx_x0_bat8 = load_data[0];
                        lx_x7_bat8 = load_data[7];
                        found_bat8 = 1;
                    end
                end
                if (found_bat8 && !found_y1 &&
                    load_en_bus===8'hFF && load_addr===4'd1) begin
                    for (j=0; j<8; j=j+1) ly_bat8[j] = load_data[j];
                    found_y1 = 1;
                end
            end
            check_eq(lx_x0_bat7, 8'd56, "batch7 x[0]=56");
            check_eq(lx_x7_bat7, 8'd63, "batch7 x[7]=63");
            check_eq(lx_x0_bat8, 8'd0,  "batch8 x[0]=0");
            check_eq(lx_x7_bat8, 8'd7,  "batch8 x[7]=7");
            for (i=0; i<8; i=i+1)
                check_eq(ly_bat8[i], 8'd1, "batch8 y=1");
        end
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 13: Final batch addresses 4088-4095
        // Run full render, capture last 8 write addresses
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 13: Final batch addr 4088-4095 ---");
        begin
            reg [11:0] last_addr13 [0:7];
            integer    total_fb13;
            integer    last_idx13;
            total_fb13 = 0;
            last_idx13 = 0;
            // Initialize with sentinel value
            for (i=0; i<8; i=i+1) last_addr13[i] = 12'hFFF;
            prog_select = 2'b00;
            pulse_start;
            // Renderer needs ~10240 cycles for full 4096-pixel render
            // Use 30000 cycle timeout — exit after last 8 captured
            repeat(30000) begin
                @(posedge clk); @(negedge clk);
                if (fb_write_enable) begin
                    total_fb13 = total_fb13 + 1;
                    if (total_fb13 > DEPTH-8 && last_idx13 < 8) begin
                        last_addr13[last_idx13] = fb_addr;
                        last_idx13 = last_idx13 + 1;
                    end
                end
            end
            for (i=0; i<8; i=i+1)
                check_eq(last_addr13[i], 12'd4088+i,
                          "final addr 4088+i");
        end
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 14: fb_dump pulses before done
        // done must arrive exactly 1 cycle after fb_dump
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 14: fb_dump then done timing ---");
        begin
            reg dump_seen14;
            reg done_seen14;
            integer cycles14;
            dump_seen14 = 0;
            done_seen14 = 0;
            cycles14    = 0;
            prog_select = 2'b00;
            pulse_start;
            // Renderer needs ~10240 cycles plus 2 extra (DUMP+DONE_ST)
            repeat(30000) begin
                @(posedge clk); @(negedge clk);
                if (fb_dump && !dump_seen14) begin
                    dump_seen14 = 1;
                    cycles14    = 0;
                end else if (dump_seen14 && !done_seen14) begin
                    cycles14 = cycles14 + 1;
                    if (done) begin
                        done_seen14 = 1;
                        check_eq(cycles14, 1,
                                  "done 1 cycle after fb_dump");
                    end
                end
            end
        end
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 15: Full render PROG_DOT pixel verification
        // result = 2 * x * y (lower 8 bits)
        // Sample known addresses and verify mathematically
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 15: Full render PROG_DOT ---");
        run_renderer(2'b00);

        // Row 0: y=0 so 2*x*0=0 for all
        check_pixel(0*WIDTH+0,  8'd0,              "DOT row0 col0=0");
        check_pixel(0*WIDTH+32, 8'd0,              "DOT row0 col32=0");
        check_pixel(0*WIDTH+63, 8'd0,              "DOT row0 col63=0");
        // Row 1: y=1 so 2*x*1=2x
        check_pixel(1*WIDTH+1,  (2*1*1)  &8'hFF,  "DOT row1 col1=2");
        check_pixel(1*WIDTH+5,  (2*5*1)  &8'hFF,  "DOT row1 col5=10");
        // Row 2: y=2 so 2*x*2=4x
        check_pixel(2*WIDTH+3,  (2*3*2)  &8'hFF,  "DOT row2 col3=12");
        check_pixel(2*WIDTH+10, (2*10*2) &8'hFF,  "DOT row2 col10=40");
        // Row 5: y=5 so 2*x*5=10x
        check_pixel(5*WIDTH+5,  (2*5*5)  &8'hFF,  "DOT row5 col5=50");
        // Row 10: y=10 so 2*x*10=20x
        check_pixel(10*WIDTH+10,(2*10*10)&8'hFF,  "DOT row10 col10=200");
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 16: Full render PROG_SHADE triangle
        // white if x+y < 64 else black
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 16: Full render PROG_SHADE ---");
        run_renderer(2'b01);

        // Inside triangle x+y < 64 → white
        check_pixel(0*WIDTH+0,   8'd255, "SHADE row0 col0 inside");
        check_pixel(5*WIDTH+5,   8'd255, "SHADE row5 col5 inside");
        check_pixel(30*WIDTH+30, 8'd255, "SHADE row30 col30 inside");
        check_pixel(32*WIDTH+31, 8'd255, "SHADE row32 col31 boundary in");
        // Outside triangle x+y >= 64 → black
        check_pixel(32*WIDTH+32, 8'd0,   "SHADE row32 col32 boundary out");
        check_pixel(32*WIDTH+33, 8'd0,   "SHADE row32 col33 outside");
        check_pixel(63*WIDTH+63, 8'd0,   "SHADE row63 col63 corner out");
        check_pixel(40*WIDTH+40, 8'd0,   "SHADE row40 col40 outside");
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 17: Full render PROG_MANDEL
        // result = x2 + y2 + x (lower 8 bits)
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 17: Full render PROG_MANDEL ---");
        run_renderer(2'b10);

        check_pixel(0*WIDTH+0, 8'd0,               "MANDEL 0+0+0=0");
        check_pixel(0*WIDTH+3, (9+0+3)  &8'hFF,    "MANDEL row0 col3=12");
        check_pixel(1*WIDTH+1, (1+1+1)  &8'hFF,    "MANDEL row1 col1=3");
        check_pixel(2*WIDTH+2, (4+4+2)  &8'hFF,    "MANDEL row2 col2=10");
        check_pixel(3*WIDTH+4, (16+9+4) &8'hFF,    "MANDEL row3 col4=29");
        check_pixel(5*WIDTH+3, (9+25+3) &8'hFF,    "MANDEL row5 col3=37");
        do_reset;

        // ════════════════════════════════════════════════════
        // TEST 18: Reset mid-render clears all outputs
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 18: Reset mid-render ---");
        prog_select = 2'b00;
        pulse_start;
        repeat(20) @(posedge clk);
        reset = 1;
        @(posedge clk); @(posedge clk);
        @(negedge clk);

        check_eq(load_en_bus,     8'h00, "reset load_en=0");
        check_eq(instr_valid_in,  1'b0,  "reset instr_valid=0");
        check_eq(fb_write_enable, 1'b0,  "reset fb_we=0");
        check_eq(fb_dump,         1'b0,  "reset fb_dump=0");
        check_eq(done,            1'b0,  "reset done=0");

        reset = 0;
        @(posedge clk);

        // ════════════════════════════════════════════════════
        // TEST 19: Renderer restarts cleanly after reset
        // After reset pulse_start should work again
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 19: Restart after reset ---");
        prog_select = 2'b00;
        pulse_start;
        @(posedge clk);
        @(negedge clk);
        check_eq(load_en_bus, 8'hFF, "restart load_en=FF");
        check_eq(load_addr,   4'd0,  "restart load_addr=R0");
        do_reset;

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
        $display("NOTE: Renderer isolation TB.");
        $display("      Full system TB needed for");
        $display("      renderer + warp_scheduler handshake.");

        $finish;
    end

endmodule