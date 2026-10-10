`timescale 1ns/1ps

// ============================================================
// Dot Product Demo — Full GPU Implementation
//
// Reduction is done BY THE GPU:
//   Phase 1: 8 cores multiply simultaneously (MUL)
//   Phase 2: Parallel reduction using ADD instructions
//            Round 1: 8 values → 4 sums
//            Round 2: 4 values → 2 sums
//            Round 3: 2 values → 1 final sum
//
// Reduction is done BY THE GPU using shader instructions
// Testbench only reads the final result
//
// Vectors:
//   A = [1, 2, 3, 4, 5, 6, 7, 8]
//   B = [8, 7, 6, 5, 4, 3, 2, 1]
//   Expected dot product = 120
// ============================================================

module dot_product_demo;

    reg clk, reset;
    initial clk = 0;
    always #5 clk = ~clk;

    // ── GPU top ports ─────────────────────────────────────────
    reg        start;
    reg [15:0] instruction_in;
    reg        instr_valid_in;
    reg [1:0]  acc_ctrl_in;
    reg [7:0]  load_en_bus;
    reg [3:0]  load_addr;
    reg [7:0]  load_data_bus [0:7];

    wire        instr_advance;
    wire        gpu_done;
    wire [7:0]  result_bus    [0:7];
    wire [7:0]  acc_bus       [0:7];
    wire [7:0]  mul_high_bus  [0:7];
    wire [7:0]  zero_bus;
    wire [7:0]  carry_bus;
    wire [7:0]  negative_bus;
    wire [7:0]  overflow_bus;
    wire [7:0]  div_done_bus;
    wire [7:0]  div_by_zero_bus;

    gpu_top dut(
        .clk(clk), .reset(reset),
        .start(start), .done(gpu_done),
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

    // ── Program memory ────────────────────────────────────────
    reg [15:0] prog_mem     [0:7];
    reg [1:0]  acc_ctrl_mem [0:7];
    integer    pc;
    integer    prog_len;

    // ── Timing ────────────────────────────────────────────────
    integer t_start;
    integer t_end;
    integer mul_cycles;
    integer reduce_cycles;
    integer total_cycles;

    // ── Results ───────────────────────────────────────────────
    reg [7:0]  partial [0:7];   // after MUL phase
    reg [7:0]  round1  [0:3];   // after reduction round 1
    reg [7:0]  round2  [0:1];   // after reduction round 2
    reg [7:0]  final_result;    // after reduction round 3

    integer file_handle;
    integer i;
    reg [7:0]  vec_a [0:7];
    reg [7:0]  vec_b [0:7];

    // ── Load values into specific cores ──────────────────────
    task load_core;
        input [2:0] core_id;
        input [3:0] reg_addr;
        input [7:0] data;
        begin
            load_addr                = reg_addr;
            load_data_bus[core_id]   = data;
            load_en_bus              = (8'h01 << core_id);
            instr_valid_in           = 0;
            @(posedge clk);
            load_en_bus = 8'h00;
            @(posedge clk);
        end
    endtask

    // ── Load value into ALL cores ─────────────────────────────
    task load_all;
        input [3:0] addr;
        input [7:0] d0,d1,d2,d3,d4,d5,d6,d7;
        begin
            load_addr        = addr;
            load_data_bus[0] = d0; load_data_bus[1] = d1;
            load_data_bus[2] = d2; load_data_bus[3] = d3;
            load_data_bus[4] = d4; load_data_bus[5] = d5;
            load_data_bus[6] = d6; load_data_bus[7] = d7;
            load_en_bus      = 8'hFF;
            instr_valid_in   = 0;
            @(posedge clk);
            load_en_bus = 8'h00;
            @(posedge clk);
        end
    endtask

    // ── Load value into selected cores only ───────────────────
    task load_selected;
        input [7:0] en_mask;  // which cores to load
        input [3:0] addr;
        input [7:0] d0,d1,d2,d3,d4,d5,d6,d7;
        begin
            load_addr        = addr;
            load_data_bus[0] = d0; load_data_bus[1] = d1;
            load_data_bus[2] = d2; load_data_bus[3] = d3;
            load_data_bus[4] = d4; load_data_bus[5] = d5;
            load_data_bus[6] = d6; load_data_bus[7] = d7;
            load_en_bus      = en_mask;
            instr_valid_in   = 0;
            @(posedge clk);
            load_en_bus = 8'h00;
            @(posedge clk);
        end
    endtask

    // ── Run one instruction on all cores ──────────────────────
    task run_one_instr;
        input [15:0] instr;
        input [1:0]  acc_mode;
        begin
            instruction_in = instr;
            acc_ctrl_in    = acc_mode;
            instr_valid_in = 1;

            @(negedge clk); start = 1;
            @(negedge clk); start = 0;

            repeat(1000) begin
                @(negedge clk);
                if (instr_advance) begin
                    instr_valid_in = 0;
                    acc_ctrl_in    = 2'b00;
                end
                if (gpu_done) disable run_one_instr;
            end
        end
    endtask

    initial begin
        $dumpfile("dot_product.vcd");
        $dumpvars(0, dot_product_demo);

        reset          = 1;
        start          = 0;
        instr_valid_in = 0;
        acc_ctrl_in    = 2'b00;
        load_en_bus    = 8'h00;
        load_addr      = 0;
        instruction_in = 0;
        for (i=0; i<8; i=i+1) load_data_bus[i] = 0;

        repeat(4) @(posedge clk);
        reset = 0;
        @(posedge clk);

        $display("============================================");
        $display("  Mini GPU — Dot Product Demo");
        $display("  Full GPU Reduction on Hardware");
        $display("============================================");
        // ── Read input vectors from file ──────────────────────
        // input.txt format (two lines, space separated):
        //   Line 1: 8 values for A
        //   Line 2: 8 values for B
        // Values clamped to 0-15 (max product 15x15=225 < 255)
        // If file missing, default vectors are used
        begin : read_input
            integer fh;
            integer scan_ok;
            integer k;
            fh = $fopen("input.txt", "r");
            if (fh == 0) begin
                $display("input.txt not found — using defaults");
                vec_a[0]=8'd1; vec_a[1]=8'd2;
                vec_a[2]=8'd3; vec_a[3]=8'd4;
                vec_a[4]=8'd5; vec_a[5]=8'd6;
                vec_a[6]=8'd7; vec_a[7]=8'd8;
                vec_b[0]=8'd8; vec_b[1]=8'd7;
                vec_b[2]=8'd6; vec_b[3]=8'd5;
                vec_b[4]=8'd4; vec_b[5]=8'd3;
                vec_b[6]=8'd2; vec_b[7]=8'd1;
            end else begin
                scan_ok = $fscanf(fh,
                    "%d %d %d %d %d %d %d %d",
                    vec_a[0],vec_a[1],vec_a[2],vec_a[3],
                    vec_a[4],vec_a[5],vec_a[6],vec_a[7]);
                scan_ok = $fscanf(fh,
                    "%d %d %d %d %d %d %d %d",
                    vec_b[0],vec_b[1],vec_b[2],vec_b[3],
                    vec_b[4],vec_b[5],vec_b[6],vec_b[7]);
                $fclose(fh);
                $display("Vectors loaded from input.txt");
                for (k=0; k<8; k=k+1) begin
                    if (vec_a[k] > 15) vec_a[k] = 15;
                    if (vec_b[k] > 15) vec_b[k] = 15;
                end
            end
        end

        $display("A = [%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
                  vec_a[0],vec_a[1],vec_a[2],vec_a[3],
                  vec_a[4],vec_a[5],vec_a[6],vec_a[7]);
        $display("B = [%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
                  vec_b[0],vec_b[1],vec_b[2],vec_b[3],
                  vec_b[4],vec_b[5],vec_b[6],vec_b[7]);
        $display("--------------------------------------------");

        // ════════════════════════════════════════════════════
        // PHASE 1: MUL — 8 cores compute simultaneously
        // ════════════════════════════════════════════════════
        $display("\nPHASE 1: Parallel multiply (all 8 cores)");

        // Load vector A into R0
        load_all(4'd0,
            vec_a[0], vec_a[1], vec_a[2], vec_a[3],
            vec_a[4], vec_a[5], vec_a[6], vec_a[7]);

        // Load vector B into R1
        load_all(4'd1,
            vec_b[0], vec_b[1], vec_b[2], vec_b[3],
            vec_b[4], vec_b[5], vec_b[6], vec_b[7]);
        t_start = $time;

        // MUL R2, R0, R1
        // opcode=1011 dest=0010 srcA=0000 srcB=0001
        run_one_instr(16'b1011_0010_0000_0001, 2'b00);
        @(posedge clk); #1;

        t_end     = $time;
        mul_cycles = (t_end - t_start) / 10;

        // Read partial products
        partial[0] = result_bus[0]; partial[1] = result_bus[1];
        partial[2] = result_bus[2]; partial[3] = result_bus[3];
        partial[4] = result_bus[4]; partial[5] = result_bus[5];
        partial[6] = result_bus[6]; partial[7] = result_bus[7];

        for (i=0; i<8; i=i+1)
            $display("  Core %0d: %0d x %0d = %0d",
                      i, vec_a[i], vec_b[i], partial[i]);
        for (i=0; i<8; i=i+1)
            $display("  Core %0d: %0d x %0d = %0d",
                      i, vec_a[i], vec_b[i], partial[i]);
        for (i=0; i<8; i=i+1)
            $display("  Core %0d: %0d x %0d = %0d",
                      i, vec_a[i], vec_b[i], partial[i]);
        for (i=0; i<8; i=i+1)
            $display("  Core %0d: %0d x %0d = %0d",
                      i, vec_a[i], vec_b[i], partial[i]);
        for (i=0; i<8; i=i+1)
            $display("  Core %0d: %0d x %0d = %0d",
                      i, vec_a[i], vec_b[i], partial[i]);
        for (i=0; i<8; i=i+1)
            $display("  Core %0d: %0d x %0d = %0d",
                      i, vec_a[i], vec_b[i], partial[i]);
        for (i=0; i<8; i=i+1)
            $display("  Core %0d: %0d x %0d = %0d",
                      i, vec_a[i], vec_b[i], partial[i]);
        for (i=0; i<8; i=i+1)
            $display("  Core %0d: %0d x %0d = %0d",
                      i, vec_a[i], vec_b[i], partial[i]);
        $display("  Phase 1 done in %0d cycles", mul_cycles);

        // ════════════════════════════════════════════════════
        // PHASE 2: Reduction Round 1
        // 8 values → 4 sums using 4 cores
        // Core 0: partial[0] + partial[1] → R3
        // Core 1: partial[2] + partial[3] → R3
        // Core 2: partial[4] + partial[5] → R3
        // Core 3: partial[6] + partial[7] → R3
        // ════════════════════════════════════════════════════
        $display("\nPHASE 2: Reduction Round 1 (8→4)");

        t_start = $time;

        // Load pairs into R0 and R1 of cores 0-3
        // Core 0: R0=partial[0] R1=partial[1]
        // Core 1: R0=partial[2] R1=partial[3]
        // Core 2: R0=partial[4] R1=partial[5]
        // Core 3: R0=partial[6] R1=partial[7]
        // Cores 4-7 disabled during this phase

        load_selected(8'b00001111, 4'd0,
            partial[0], partial[2], partial[4], partial[6],
            8'd0, 8'd0, 8'd0, 8'd0);

        load_selected(8'b00001111, 4'd1,
            partial[1], partial[3], partial[5], partial[7],
            8'd0, 8'd0, 8'd0, 8'd0);

        // ADD R3, R0, R1 on cores 0-3
        // opcode=0000 dest=0011 srcA=0000 srcB=0001
        run_one_instr(16'b0000_0011_0000_0001, 2'b00);
        @(posedge clk); #1;

        round1[0] = result_bus[0];  // partial[0]+partial[1]
        round1[1] = result_bus[1];  // partial[2]+partial[3]
        round1[2] = result_bus[2];  // partial[4]+partial[5]
        round1[3] = result_bus[3];  // partial[6]+partial[7]

        $display("  Core 0: %0d + %0d = %0d",
                  partial[0], partial[1], round1[0]);
        $display("  Core 1: %0d + %0d = %0d",
                  partial[2], partial[3], round1[1]);
        $display("  Core 2: %0d + %0d = %0d",
                  partial[4], partial[5], round1[2]);
        $display("  Core 3: %0d + %0d = %0d",
                  partial[6], partial[7], round1[3]);

        // ════════════════════════════════════════════════════
        // PHASE 2: Reduction Round 2
        // 4 values → 2 sums using 2 cores
        // Core 0: round1[0] + round1[1] → R4
        // Core 1: round1[2] + round1[3] → R4
        // ════════════════════════════════════════════════════
        $display("\nPHASE 2: Reduction Round 2 (4→2)");

        load_selected(8'b00000011, 4'd0,
            round1[0], round1[2], 8'd0, 8'd0,
            8'd0, 8'd0, 8'd0, 8'd0);

        load_selected(8'b00000011, 4'd1,
            round1[1], round1[3], 8'd0, 8'd0,
            8'd0, 8'd0, 8'd0, 8'd0);

        // ADD R4, R0, R1
        // opcode=0000 dest=0100 srcA=0000 srcB=0001
        run_one_instr(16'b0000_0100_0000_0001, 2'b00);
        @(posedge clk); #1;

        round2[0] = result_bus[0];  // round1[0]+round1[1]
        round2[1] = result_bus[1];  // round1[2]+round1[3]

        $display("  Core 0: %0d + %0d = %0d",
                  round1[0], round1[1], round2[0]);
        $display("  Core 1: %0d + %0d = %0d",
                  round1[2], round1[3], round2[1]);

        // ════════════════════════════════════════════════════
        // PHASE 2: Reduction Round 3
        // 2 values → 1 final sum
        // Core 0: round2[0] + round2[1] → final
        // ════════════════════════════════════════════════════
        $display("\nPHASE 2: Reduction Round 3 (2→1)");

        load_selected(8'b00000001, 4'd0,
            round2[0], 8'd0, 8'd0, 8'd0,
            8'd0, 8'd0, 8'd0, 8'd0);

        load_selected(8'b00000001, 4'd1,
            round2[1], 8'd0, 8'd0, 8'd0,
            8'd0, 8'd0, 8'd0, 8'd0);

        // ADD R5, R0, R1
        // opcode=0000 dest=0101 srcA=0000 srcB=0001
        run_one_instr(16'b0000_0101_0000_0001, 2'b00);
        @(posedge clk); #1;

        t_end          = $time;
        reduce_cycles  = (t_end - t_start) / 10;
        total_cycles   = mul_cycles + reduce_cycles;
        final_result   = result_bus[0];

        $display("  Core 0: %0d + %0d = %0d",
                  round2[0], round2[1], final_result);

        // ════════════════════════════════════════════════════
        // RESULT
        // ════════════════════════════════════════════════════
        $display("\n============================================");
        $display("  Results");
        $display("============================================");
        $display("Dot product = %0d", final_result);

            begin : verify
                integer expected_sum;
                integer k;
                expected_sum = 0;
                for (k=0; k<8; k=k+1)
                    expected_sum = expected_sum +
                                (vec_a[k] * vec_b[k]);

                $display("Expected sum = %0d", expected_sum);
                if (final_result == expected_sum[7:0])
                    $display("Status: CORRECT");
                else
                    $display("Status: WRONG (got %0d exp %0d)",
                            final_result, expected_sum);
            end

        $display("\nTiming (measured):");
        $display("  MUL phase:    %0d cycles", mul_cycles);
        $display("  Reduce phase: %0d cycles", reduce_cycles);
        $display("  Total GPU:    %0d cycles", total_cycles);
        $display("\nSequential comparison:");
        $display("  8 multiplies + 7 additions = 15 operations");
        $display("  GPU parallel phases = MUL(1) + 3 ADD rounds");
        $display("  Reduction is O(log N) = log2(8) = 3 rounds");
        $display("============================================");

        // ── Write output file ─────────────────────────────────
        file_handle = $fopen("dot_product.hex", "w");
        if (file_handle != 0) begin
            $fwrite(file_handle,
                    "# Mini GPU Dot Product Demo\n");
            $fwrite(file_handle,
                    "# Vector A: %0d %0d %0d %0d %0d %0d %0d %0d\n",
                    vec_a[0],vec_a[1],vec_a[2],vec_a[3],
                    vec_a[4],vec_a[5],vec_a[6],vec_a[7]);
            $fwrite(file_handle,
                    "# Vector B: %0d %0d %0d %0d %0d %0d %0d %0d\n",
                    vec_b[0],vec_b[1],vec_b[2],vec_b[3],
                    vec_b[4],vec_b[5],vec_b[6],vec_b[7]);
            // Partial products with actual vector values
            for (i=0; i<8; i=i+1)
                $fwrite(file_handle, "%0d,%0d,%0d,%0d\n",
                        i, vec_a[i], vec_b[i], partial[i]);
            begin : write_expected
                integer exp_sum;
                integer kk;
                exp_sum = 0;
                for (kk=0; kk<8; kk=kk+1)
                    exp_sum = exp_sum + vec_a[kk]*vec_b[kk];
                $fwrite(file_handle, "expected,%0d\n", exp_sum);
            end

            $fclose(file_handle);
            $display("\nOutput written to dot_product.hex");
            $display("Run: python python/dot_product_viz.py");
        end

        $finish;
    end

endmodule 