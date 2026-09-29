`timescale 1ns/1ps

module gpu_top_tb;

    reg        clk, reset;
    reg        start;
    reg [15:0] instruction_in;
    reg        instr_valid_in;
    reg [1:0]  acc_ctrl_in;
    reg [7:0]  load_en_bus;
    reg [3:0]  load_addr;
    reg [7:0]  load_data_bus [0:7];

    wire        done;
    wire        instr_advance;
    wire [7:0]  result_bus    [0:7];
    wire [7:0]  acc_bus       [0:7];
    wire [7:0]  mul_high_bus  [0:7];
    wire [7:0]  zero_bus;
    wire [7:0]  carry_bus;
    wire [7:0]  negative_bus;
    wire [7:0]  overflow_bus;
    wire [7:0]  div_done_bus;
    wire [7:0]  div_by_zero_bus;

    gpu_top uut(
        .clk(clk), .reset(reset),
        .start(start),
        .done(done),
        .instruction_in(instruction_in),
        .instr_valid_in(instr_valid_in),
        .acc_ctrl_in(acc_ctrl_in),
        .instr_advance(instr_advance),
        .load_en_bus(load_en_bus),
        .load_addr(load_addr),
        .load_data_bus(load_data_bus),
        .result_bus(result_bus),
        .acc_bus(acc_bus),
        .mul_high_bus(mul_high_bus),
        .zero_bus(zero_bus),
        .carry_bus(carry_bus),
        .negative_bus(negative_bus),
        .overflow_bus(overflow_bus),
        .div_done_bus(div_done_bus),
        .div_by_zero_bus(div_by_zero_bus)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Test counters
    integer pass_count;
    integer fail_count;
    integer j;

    // Latched division signals
    reg [7:0] div_done_latched;
    reg [7:0] div_by_zero_latched;

    // Counters for done-pulse and instr_advance tests
    integer done_count;   // total done pulses observed
    integer adv_count;    // instr_advance pulses during one run
    reg     counting_adv; // gate: enable advance counting

    always @(posedge clk) begin
        if (div_done_bus != 8'h00)
            div_done_latched = div_done_bus;
        if (div_by_zero_bus != 8'h00)
            div_by_zero_latched = div_by_zero_bus;
    end

    // Count done pulses (one per completed program)
    // Count instr_advance pulses (gated by counting_adv flag)
    always @(posedge clk) begin
        if (done)
            done_count = done_count + 1;
        if (instr_advance && counting_adv)
            adv_count = adv_count + 1;
    end

    // ── Program memory ────────────────────────────────────────
    reg [15:0] prog_mem     [0:7];
    reg [1:0]  acc_ctrl_mem [0:7];
    integer    pc;
    integer    prog_len;

    // ── Helper tasks ──────────────────────────────────────────

    task load_all_cores;
        input [3:0] addr;
        input [7:0] d0,d1,d2,d3,d4,d5,d6,d7;
        begin
            load_addr        = addr;
            load_data_bus[0] = d0;
            load_data_bus[1] = d1;
            load_data_bus[2] = d2;
            load_data_bus[3] = d3;
            load_data_bus[4] = d4;
            load_data_bus[5] = d5;
            load_data_bus[6] = d6;
            load_data_bus[7] = d7;
            load_en_bus      = 8'hFF;
            instr_valid_in   = 0;
            start            = 0;
            @(posedge clk);
            load_en_bus = 8'h00;
            @(posedge clk);
        end
    endtask

    task load_all_same;
        input [3:0] addr;
        input [7:0] data;
        begin
            load_all_cores(addr,
                data,data,data,data,
                data,data,data,data);
        end
    endtask

    // Run a program through the warp scheduler
    // Program must be loaded into prog_mem and acc_ctrl_mem
    // prog_len tells how many instructions
    task run_program;
        input integer len;
        begin
            pc       = 0;
            prog_len = len;

            // Present first instruction
            instruction_in = prog_mem[0];
            acc_ctrl_in    = acc_ctrl_mem[0];
            instr_valid_in = 1;

            // Pulse start
            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            // Feed instructions as scheduler requests
            repeat(100) begin
                @(negedge clk);

                if (instr_advance) begin
                    pc = pc + 1;
                    if (pc < prog_len) begin
                        instruction_in = prog_mem[pc];
                        acc_ctrl_in    = acc_ctrl_mem[pc];
                        instr_valid_in = 1;
                    end else begin
                        instruction_in = 16'b0;
                        instr_valid_in = 0;
                        acc_ctrl_in    = 2'b00;
                    end
                end

                if (done) disable run_program;
            end
        end
    endtask

    // Check result of one core
    task check_core;
        input integer core_id;
        input [7:0]   expected;
        input [63:0]  label;
        reg [7:0] actual;
        begin
            case (core_id)
                0: actual = result_bus[0];
                1: actual = result_bus[1];
                2: actual = result_bus[2];
                3: actual = result_bus[3];
                4: actual = result_bus[4];
                5: actual = result_bus[5];
                6: actual = result_bus[6];
                7: actual = result_bus[7];
                default: actual = 8'hXX;
            endcase
            if (actual === expected) begin
                $display("PASS | %-15s Core%0d=%0d",
                          label, core_id, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | %-15s Core%0d got=%0d exp=%0d",
                          label, core_id, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Check accumulator of one core
    task check_acc;
        input integer core_id;
        input [7:0]   expected;
        reg [7:0] actual;
        begin
            case (core_id)
                0: actual = acc_bus[0];
                1: actual = acc_bus[1];
                2: actual = acc_bus[2];
                3: actual = acc_bus[3];
                4: actual = acc_bus[4];
                5: actual = acc_bus[5];
                6: actual = acc_bus[6];
                7: actual = acc_bus[7];
                default: actual = 8'hXX;
            endcase
            if (actual === expected) begin
                $display("PASS | acc[%0d]=%0d", core_id, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | acc[%0d] got=%0d exp=%0d",
                          core_id, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Check flag bus
    task check_flag;
        input [7:0]   actual;
        input [7:0]   expected;
        input [127:0] label;
        begin
            if (actual === expected) begin
                $display("PASS | %-20s %08b",
                          label, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | %-20s got=%08b exp=%08b",
                          label, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("gpu_top.vcd");
        $dumpvars(0, gpu_top_tb);

        pass_count          = 0;
        fail_count          = 0;
        div_done_latched    = 8'h00;
        div_by_zero_latched = 8'h00;
        done_count          = 0;
        adv_count           = 0;
        counting_adv        = 1'b0;

        reset=1; start=0;
        instruction_in=0; instr_valid_in=0;
        acc_ctrl_in=0; load_en_bus=0;
        load_addr=0;
        for (j=0; j<8; j=j+1) load_data_bus[j]=0;
        repeat(3) @(posedge clk);
        reset=0;
        @(posedge clk);

        // ════════════════════════════════════════════════════
        // TEST 1: Single ADD instruction through full pipeline
        // Verifies warp scheduler dispatches to all 8 cores
        // R1[i]=i*10  R2[i]=i*5  expected result[i]=i*15
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 1: ADD through full GPU pipeline ---");

        load_all_cores(4'd1,
            8'd0,  8'd10, 8'd20, 8'd30,
            8'd40, 8'd50, 8'd60, 8'd70);
        load_all_cores(4'd2,
            8'd0,  8'd5,  8'd10, 8'd15,
            8'd20, 8'd25, 8'd30, 8'd35);

        // Program: one ADD instruction
        prog_mem[0]     = 16'b0000_0011_0001_0010; // ADD R3,R1,R2
        acc_ctrl_mem[0] = 2'b00;

        run_program(1);
        @(posedge clk); #1;

        check_core(0, 8'd0,   "ADD");
        check_core(1, 8'd15,  "ADD");
        check_core(2, 8'd30,  "ADD");
        check_core(3, 8'd45,  "ADD");
        check_core(4, 8'd60,  "ADD");
        check_core(5, 8'd75,  "ADD");
        check_core(6, 8'd90,  "ADD");
        check_core(7, 8'd105, "ADD");

        // ════════════════════════════════════════════════════
        // TEST 2: Multi-instruction program
        // ADD then SUB through scheduler sequencing
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 2: Multi-instruction program ---");

        load_all_same(4'd1, 8'd50);
        load_all_same(4'd2, 8'd20);

        // Program:
        // Instr 0: ADD R3,R1,R2  → R3 = 50+20 = 70
        // Instr 1: SUB R4,R3,R2  → R4 = 70-20 = 50
        prog_mem[0]     = 16'b0000_0011_0001_0010; // ADD R3,R1,R2
        prog_mem[1]     = 16'b0001_0100_0011_0010; // SUB R4,R3,R2
        acc_ctrl_mem[0] = 2'b00;
        acc_ctrl_mem[1] = 2'b00;

        run_program(2);
        @(posedge clk); #1;

        // All 8 cores should have R4=50
        check_core(0, 8'd50, "SUB after ADD");
        check_core(3, 8'd50, "SUB after ADD");
        check_core(7, 8'd50, "SUB after ADD");

        // ════════════════════════════════════════════════════
        // TEST 3: Dot product through full pipeline
        // A=[1,2,3,4,5,6,7,8] B=[8,7,6,5,4,3,2,1]
        // Each core computes one product simultaneously
        // products: 8,14,18,20,20,18,14,8
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 3: Dot product through pipeline ---");

        // Clear accumulators
        instr_valid_in=0; acc_ctrl_in=2'b11;
        @(posedge clk);
        acc_ctrl_in=2'b00;
        @(posedge clk);

        load_all_cores(4'd0,
            8'd1, 8'd2, 8'd3, 8'd4,
            8'd5, 8'd6, 8'd7, 8'd8);
        load_all_cores(4'd1,
            8'd8, 8'd7, 8'd6, 8'd5,
            8'd4, 8'd3, 8'd2, 8'd1);

        // Program: MUL with acc LOAD
        prog_mem[0]     = 16'b1011_0010_0000_0001; // MUL R2,R0,R1
        acc_ctrl_mem[0] = 2'b01;                   // LOAD acc

        run_program(1);
        @(posedge clk); #1;

        check_core(0, 8'd8,  "DOT MUL");
        check_core(1, 8'd14, "DOT MUL");
        check_core(2, 8'd18, "DOT MUL");
        check_core(3, 8'd20, "DOT MUL");
        check_core(4, 8'd20, "DOT MUL");
        check_core(5, 8'd18, "DOT MUL");
        check_core(6, 8'd14, "DOT MUL");
        check_core(7, 8'd8,  "DOT MUL");

        check_acc(0, 8'd8);
        check_acc(1, 8'd14);
        check_acc(2, 8'd18);
        check_acc(3, 8'd20);
        check_acc(4, 8'd20);
        check_acc(5, 8'd18);
        check_acc(6, 8'd14);
        check_acc(7, 8'd8);


        // ════════════════════════════════════════════════════
        // TEST 4: DIV through scheduler WAIT state
        // Verifies scheduler correctly stalls during DIV
        // and resumes execution after all cores finish
        //
        // NOTE: DIV writeback not implemented in v1
        // We verify:
        //   1. div_done_bus pulses FF on all cores
        //   2. Scheduler resumes after DIV (ADD executes after)
        //   3. ADD uses pre-loaded register values correctly
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 4: DIV through WAIT state ---");

        div_done_latched    = 8'h00;
        div_by_zero_latched = 8'h00;

        // Load R1 and R2 for DIV
        // DIV result will NOT write to R3 (documented v1 limitation)
        load_all_cores(4'd1,
            8'd100, 8'd90, 8'd80, 8'd70,
            8'd60,  8'd50, 8'd40, 8'd30);
        load_all_same(4'd2, 8'd10);

        // Pre-load R3 with known values for the ADD after DIV
        // Since DIV does not writeback, ADD will use these values
        // R3[i] = i*5 so ADD R4,R3,R3 gives R4[i] = i*10
        load_all_cores(4'd3,
            8'd0,  8'd5,  8'd10, 8'd15,
            8'd20, 8'd25, 8'd30, 8'd35);

        // Program:
        // Instr 0: DIV R3,R1,R2 → scheduler enters WAIT state
        //          R3 NOT written (v1 limitation)
        //          div_done_bus pulses FF when all cores done
        // Instr 1: ADD R4,R3,R3 → uses pre-loaded R3 values
        //          verifies scheduler resumed after WAIT
        prog_mem[0]     = 16'b1100_0011_0001_0010; // DIV R3,R1,R2
        prog_mem[1]     = 16'b0000_0100_0011_0011; // ADD R4,R3,R3
        acc_ctrl_mem[0] = 2'b00;
        acc_ctrl_mem[1] = 2'b00;

        run_program(2);
        @(posedge clk); #1;

        // Verify div_done pulsed on all cores
        if (div_done_latched === 8'hFF) begin
            $display("PASS | div_done_bus latched FF all cores");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL | div_done_bus latched=%08b",
                    div_done_latched);
            fail_count = fail_count + 1;
        end

        // Verify ADD executed correctly after WAIT
        // ADD R4,R3,R3 using pre-loaded R3 values
        // R3[i] = i*5 so R4[i] = i*10
        check_core(0, 8'd0,  "DIV WAIT then ADD");
        check_core(1, 8'd10, "DIV WAIT then ADD");
        check_core(2, 8'd20, "DIV WAIT then ADD");
        check_core(3, 8'd30, "DIV WAIT then ADD");
        check_core(4, 8'd40, "DIV WAIT then ADD");
        check_core(5, 8'd50, "DIV WAIT then ADD");
        check_core(6, 8'd60, "DIV WAIT then ADD");
        check_core(7, 8'd70, "DIV WAIT then ADD");

        $display("NOTE: DIV writeback is v1 documented limitation");
        $display("      Scheduler WAIT state verified via div_done latch");
        $display("      ADD after DIV confirms scheduler resumed correctly");

        // ════════════════════════════════════════════════════
        // TEST 5: Flag buses through pipeline
        // Zero, Negative, Carry, Overflow
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 5: Flag buses ---");

        // Zero flag — all cores SUB equal values
        load_all_cores(4'd1,
            8'd5,  8'd10, 8'd15, 8'd20,
            8'd25, 8'd30, 8'd35, 8'd40);
        load_all_cores(4'd2,
            8'd5,  8'd10, 8'd15, 8'd20,
            8'd25, 8'd30, 8'd35, 8'd40);
        prog_mem[0]     = 16'b0001_0011_0001_0010; // SUB R3,R1,R2
        acc_ctrl_mem[0] = 2'b00;
        run_program(1);
        @(posedge clk); #1;
        check_flag(zero_bus, 8'hFF, "zero_bus");

        // Negative flag — all cores SUB 3-10
        load_all_same(4'd1, 8'd3);
        load_all_same(4'd2, 8'd10);
        prog_mem[0]     = 16'b0001_0011_0001_0010; // SUB R3,R1,R2
        acc_ctrl_mem[0] = 2'b00;
        run_program(1);
        @(posedge clk); #1;
        check_flag(negative_bus, 8'hFF, "negative_bus");

        // Carry flag — all cores ADD 200+100=300 overflow
        load_all_same(4'd1, 8'd200);
        load_all_same(4'd2, 8'd100);
        prog_mem[0]     = 16'b0000_0011_0001_0010; // ADD R3,R1,R2
        acc_ctrl_mem[0] = 2'b00;
        run_program(1);
        @(posedge clk); #1;
        check_flag(carry_bus, 8'hFF, "carry_bus");

        // Overflow flag — all cores ADD 100+100=200 signed overflow
        load_all_same(4'd1, 8'd100);
        load_all_same(4'd2, 8'd100);
        prog_mem[0]     = 16'b0000_0011_0001_0010; // ADD R3,R1,R2
        acc_ctrl_mem[0] = 2'b00;
        run_program(1);
        @(posedge clk); #1;
        check_flag(overflow_bus, 8'hFF, "overflow_bus");

        // ════════════════════════════════════════════════════
        // TEST 6: Full dot product with accumulation
        // 2x3 + 4x5 + 1x7 = 6+20+7 = 33 on all cores
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 6: Full dot product accumulation ---");

        // Clear accumulators
        instr_valid_in=0; acc_ctrl_in=2'b11;
        @(posedge clk);
        acc_ctrl_in=2'b00;
        @(posedge clk);

        // Step 1: MUL 2x3=6, LOAD into acc
        load_all_same(4'd0, 8'd2);
        load_all_same(4'd1, 8'd3);
        prog_mem[0]     = 16'b1011_0010_0000_0001; // MUL R2,R0,R1
        acc_ctrl_mem[0] = 2'b01; // LOAD
        run_program(1);
        @(posedge clk); #1;
        $display("After MUL 2x3: acc should be 6");
        check_acc(0, 8'd6);

        // Step 2: MUL 4x5=20, ADD to acc
        load_all_same(4'd0, 8'd4);
        load_all_same(4'd1, 8'd5);
        prog_mem[0]     = 16'b1011_0010_0000_0001; // MUL R2,R0,R1
        acc_ctrl_mem[0] = 2'b10; // ADD
        run_program(1);
        @(posedge clk); #1;
        $display("After MUL 4x5: acc should be 26");
        check_acc(0, 8'd26);

        // Step 3: MUL 1x7=7, ADD to acc
        load_all_same(4'd0, 8'd1);
        load_all_same(4'd1, 8'd7);
        prog_mem[0]     = 16'b1011_0010_0000_0001; // MUL R2,R0,R1
        acc_ctrl_mem[0] = 2'b10; // ADD
        run_program(1);
        @(posedge clk); #1;
        $display("After MUL 1x7: acc should be 33");
        check_acc(0, 8'd33);

        if (acc_bus[0] === 8'd33) begin
            $display("PASS | Full dot product = 33");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL | Full dot product got %0d expected 33",
                      acc_bus[0]);
            fail_count = fail_count + 1;
        end

        // ════════════════════════════════════════════════════
        // TEST 7: Divide-by-zero bus test
        // Set divisor = 0 on all cores, issue DIV.
        // Every core must raise div_by_zero → latched bus = 0xFF
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 7: Divide-by-zero bus ---");

        div_done_latched    = 8'h00;
        div_by_zero_latched = 8'h00;

        load_all_same(4'd1, 8'd50);   // dividend = 50
        load_all_same(4'd2, 8'd0);    // divisor  =  0  ← triggers /0

        // DIV R3,R1,R2  (opcode=1100 dest=R3 s1=R1 s2=R2)
        prog_mem[0]     = 16'b1100_0011_0001_0010;
        acc_ctrl_mem[0] = 2'b00;

        run_program(1);
        @(posedge clk); #1;

        if (div_by_zero_latched === 8'hFF) begin
            $display("PASS | div_by_zero_bus latched=FF (all 8 cores detected /0)");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL | div_by_zero_bus latched=%08b  exp=11111111",
                      div_by_zero_latched);
            fail_count = fail_count + 1;
        end

        // ════════════════════════════════════════════════════
        // TEST 8: mul_high_bus — upper byte of 16-bit product
        // 200 × 200 = 40 000 = 0x9C40
        //   result_bus   (low  byte) = 0x40 = 64
        //   mul_high_bus (high byte) = 0x9C = 156
        // All 8 cores receive the same operands → same result
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 8: mul_high_bus (16-bit product upper byte) ---");

        load_all_same(4'd0, 8'd200);
        load_all_same(4'd1, 8'd200);

        // MUL R2,R0,R1  (opcode=1011 dest=R2 s1=R0 s2=R1)
        prog_mem[0]     = 16'b1011_0010_0000_0001;
        acc_ctrl_mem[0] = 2'b00;

        run_program(1);
        @(posedge clk); #1;

        // Low byte lands in result_bus
        check_core(0, 8'd64, "MUL_LOW");
        check_core(4, 8'd64, "MUL_LOW");
        check_core(7, 8'd64, "MUL_LOW");

        // High byte must be 0x9C (156) in mul_high_bus for every core
        for (j = 0; j < 8; j = j + 1) begin
            if (mul_high_bus[j] === 8'd156) begin
                $display("PASS | mul_high_bus[%0d]=0x%02h (%0d)",
                          j, mul_high_bus[j], mul_high_bus[j]);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | mul_high_bus[%0d] got=0x%02h (%0d)  exp=0x9C (156)",
                          j, mul_high_bus[j], mul_high_bus[j]);
                fail_count = fail_count + 1;
            end
        end

        // ════════════════════════════════════════════════════
        // TEST 9: Explicit done one-cycle pulse check
        // The warp scheduler FSM must assert done for EXACTLY
        // one clock cycle.  After run_program exits (negedge),
        // done must be low on the very next posedge.
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 9: done one-cycle pulse check ---");

        done_count = 0;   // reset — counts only pulses in this test

        load_all_same(4'd1, 8'd10);
        load_all_same(4'd2, 8'd5);

        prog_mem[0]     = 16'b0000_0011_0001_0010; // ADD R3,R1,R2
        acc_ctrl_mem[0] = 2'b00;

        run_program(1);
        // run_program exits at the negedge where done is high.
        // Advance one full clock: done should de-assert this cycle,
        // and the always block increments done_count.
        @(posedge clk); #1;

        if (done === 1'b0) begin
            $display("PASS | done de-asserted after one-cycle pulse");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL | done still high — not a one-cycle pulse");
            fail_count = fail_count + 1;
        end

        if (done_count >= 1) begin
            $display("PASS | done pulsed %0d time(s) during this test", done_count);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL | done never observed high (done_count=%0d)", done_count);
            fail_count = fail_count + 1;
        end

        // ════════════════════════════════════════════════════
        // TEST 10: instr_advance count and timing
        // For an N non-DIV instruction program the scheduler
        // must assert instr_advance exactly N times —
        // one pulse per instruction dispatched.
        // Program: ADD → SUB → ADD (3 instructions)
        //   R3 = R1+R2 = 30+10 = 40
        //   R4 = R3-R2 = 40-10 = 30
        //   R5 = R4+R2 = 30+10 = 40
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 10: instr_advance pulse count (3-instruction program) ---");

        load_all_same(4'd1, 8'd30);
        load_all_same(4'd2, 8'd10);

        prog_mem[0]     = 16'b0000_0011_0001_0010; // ADD R3,R1,R2
        prog_mem[1]     = 16'b0001_0100_0011_0010; // SUB R4,R3,R2
        prog_mem[2]     = 16'b0000_0101_0100_0010; // ADD R5,R4,R2
        acc_ctrl_mem[0] = 2'b00;
        acc_ctrl_mem[1] = 2'b00;
        acc_ctrl_mem[2] = 2'b00;

        adv_count    = 0;     // reset pulse counter
        counting_adv = 1'b1;  // arm the counter
        run_program(3);
        @(posedge clk); #1;
        counting_adv = 1'b0;  // disarm before checking

        if (adv_count === 3) begin
            $display("PASS | instr_advance pulsed %0d times for 3-instr program",
                      adv_count);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL | instr_advance count got=%0d  exp=3", adv_count);
            fail_count = fail_count + 1;
        end

        // Sanity-check the arithmetic results of the 3-step program
        check_core(0, 8'd40, "ADV_FINAL");
        check_core(7, 8'd40, "ADV_FINAL");

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