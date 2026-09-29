`timescale 1ns/1ps

module gpu_core_array_tb;

    reg        clk, reset;
    reg        instr_valid;
    reg [15:0] instruction;
    reg [1:0]  acc_ctrl;
    reg [7:0]  load_en_bus;
    reg [3:0]  load_addr;
    reg [7:0]  load_data_bus [0:7];
    reg        div_start;
    reg [7:0] div_done_latched;
    reg [7:0] div_by_zero_latched;    


    wire [7:0]  div_done_bus;
    wire [7:0]  div_by_zero_bus;
    wire [7:0]  result_bus   [0:7];
    wire [7:0]  acc_bus      [0:7];
    wire [7:0]  mul_high_bus [0:7];
    wire [7:0]  zero_bus;
    wire [7:0]  carry_bus;
    wire [7:0]  negative_bus;
    wire [7:0]  overflow_bus;


    gpu_core_array uut(
        .clk(clk), .reset(reset),
        .instr_valid(instr_valid),
        .instruction(instruction),
        .acc_ctrl(acc_ctrl),
        .load_en_bus(load_en_bus),
        .load_addr(load_addr),
        .load_data_bus(load_data_bus),
        .div_start(div_start),
        .div_done_bus(div_done_bus),
        .div_by_zero_bus(div_by_zero_bus),
        .result_bus(result_bus),
        .acc_bus(acc_bus),
        .mul_high_bus(mul_high_bus),
        .zero_bus(zero_bus),
        .carry_bus(carry_bus),
        .negative_bus(negative_bus),
        .overflow_bus(overflow_bus)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Latch div_done_bus and div_by_zero_bus
    // when they pulse high — they are one cycle pulses
    // so we must capture them immediately
    always @(posedge clk) begin
        if (div_done_bus != 8'h00)
            div_done_latched = div_done_bus;
        if (div_by_zero_bus != 8'h00)
            div_by_zero_latched = div_by_zero_bus;
    end

    integer pass_count;
    integer fail_count;
    integer j;

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
            instr_valid      = 0;
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

    task broadcast;
        input [15:0] instr;
        input [1:0]  ctrl;
        begin
            instruction = instr;
            instr_valid = 1;
            acc_ctrl    = ctrl;
            @(posedge clk);
            instr_valid = 0;
            acc_ctrl    = 2'b00;
            @(posedge clk); #1;
        end
    endtask

    // Check one core result
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
                $display("PASS | Core%0d=%0d", core_id, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | Core%0d got=%0d expected=%0d",
                          core_id, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Check one acc value
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
                $display("FAIL | acc[%0d] got=%0d expected=%0d",
                          core_id, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Check flag bus
    task check_flag;
        input [7:0]  actual;
        input [7:0]  expected;
        input [127:0] label;
        begin
            if (actual === expected) begin
                $display("PASS | %-20s flags=%08b",
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
        $dumpfile("gpu_core_array.vcd");
        $dumpvars(0, gpu_core_array_tb);

        pass_count = 0;
        fail_count = 0;

        reset=1; instr_valid=0; load_en_bus=0;
        div_start=0; acc_ctrl=2'b00;
        instruction=0; load_addr=0;
        for (j=0; j<8; j=j+1) load_data_bus[j]=0;
        repeat(3) @(posedge clk);
        reset=0;

        // ════════════════════════════════════════════════════
        // TEST 1: Parallel ADD
        // R1[i]=i*10  R2[i]=i*5  result[i]=i*15
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 1: Parallel ADD ---");
        load_all_cores(4'd1,
            8'd0,  8'd10, 8'd20, 8'd30,
            8'd40, 8'd50, 8'd60, 8'd70);
        load_all_cores(4'd2,
            8'd0,  8'd5,  8'd10, 8'd15,
            8'd20, 8'd25, 8'd30, 8'd35);
        // ADD R3,R1,R2 opcode=0000 dest=3 srcA=1 srcB=2
        broadcast(16'b0000_0011_0001_0010, 2'b00);

        check_core(0, 8'd0,   "ADD");
        check_core(1, 8'd15,  "ADD");
        check_core(2, 8'd30,  "ADD");
        check_core(3, 8'd45,  "ADD");
        check_core(4, 8'd60,  "ADD");
        check_core(5, 8'd75,  "ADD");
        check_core(6, 8'd90,  "ADD");
        check_core(7, 8'd105, "ADD");

        // ════════════════════════════════════════════════════
        // TEST 2: Parallel SUB
        // R1[i]=100-i*10  R2=10  result[i]=90-i*10
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 2: Parallel SUB ---");
        load_all_cores(4'd1,
            8'd100, 8'd90, 8'd80, 8'd70,
            8'd60,  8'd50, 8'd40, 8'd30);
        load_all_same(4'd2, 8'd10);
        // SUB R3,R1,R2 opcode=0001 dest=3 srcA=1 srcB=2
        broadcast(16'b0001_0011_0001_0010, 2'b00);

        check_core(0, 8'd90, "SUB");
        check_core(1, 8'd80, "SUB");
        check_core(2, 8'd70, "SUB");
        check_core(3, 8'd60, "SUB");
        check_core(4, 8'd50, "SUB");
        check_core(5, 8'd40, "SUB");
        check_core(6, 8'd30, "SUB");
        check_core(7, 8'd20, "SUB");

        // ════════════════════════════════════════════════════
        // TEST 3: Parallel MUL + mul_high_bus
        // 200x2=400=0x0190 low=0x90=144 high=0x01=1
        // 120x2=240=0x00F0 low=0xF0=240 high=0x00=0
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 3: Parallel MUL + mul_high_bus ---");
        load_all_cores(4'd1,
            8'd200, 8'd180, 8'd160, 8'd140,
            8'd120, 8'd100, 8'd80,  8'd60);
        load_all_same(4'd2, 8'd2);
        // MUL R3,R1,R2 opcode=1011 dest=3 srcA=1 srcB=2
        broadcast(16'b1011_0011_0001_0010, 2'b00);

        // Low bytes
        check_core(0, 8'd144, "MUL low");  // 400%256
        check_core(1, 8'd104, "MUL low");  // 360%256
        check_core(2, 8'd64,  "MUL low");  // 320%256
        check_core(3, 8'd24,  "MUL low");  // 280%256
        check_core(4, 8'd240, "MUL low");  // 240%256
        check_core(5, 8'd200, "MUL low");  // 200%256
        check_core(6, 8'd160, "MUL low");  // 160%256
        check_core(7, 8'd120, "MUL low");  // 120%256

        // High bytes — cores 0-3 should be 1, cores 4-7 should be 0
        if (mul_high_bus[0]===8'd1 && mul_high_bus[1]===8'd1 &&
            mul_high_bus[2]===8'd1 && mul_high_bus[3]===8'd1) begin
            $display("PASS | mul_high cores 0-3 = 1");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL | mul_high cores 0-3 wrong");
            fail_count = fail_count + 1;
        end
        if (mul_high_bus[4]===8'd0 && mul_high_bus[5]===8'd0 &&
            mul_high_bus[6]===8'd0 && mul_high_bus[7]===8'd0) begin
            $display("PASS | mul_high cores 4-7 = 0");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL | mul_high cores 4-7 wrong");
            fail_count = fail_count + 1;
        end

        // ════════════════════════════════════════════════════
        // TEST 4: Parallel DIV with div_start
        // R1[i]=100-i*10  R2=10  quotient[i]=(100-i*10)/10
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 4: Parallel DIV ---");
        load_all_cores(4'd1,
            8'd100, 8'd90, 8'd80, 8'd70,
            8'd60,  8'd50, 8'd40, 8'd30);
        load_all_same(4'd2, 8'd10);

        // DIV R3,R1,R2 opcode=1100 dest=3 srcA=1 srcB=2
        instruction = 16'b1100_0011_0001_0010;
        instr_valid = 1;
        acc_ctrl    = 2'b00;
        div_start   = 1;
        @(posedge clk);
        instr_valid = 0;
        div_start   = 0;
        acc_ctrl    = 2'b00;

        // Wait for all 8 cores to complete
        $display("Waiting for div_done_bus...");
       // Reset latch before waiting
        div_done_latched = 8'h00;
        wait(div_done_bus == 8'hFF);
        @(posedge clk); #1; 

        // Check latched value — not live signal which may have dropped
        if (div_done_latched === 8'hFF) begin
            $display("PASS | div_done_bus latched=11111111 all cores done");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL | div_done_latched=%08b (missed pulse)",div_done_latched);
            fail_count = fail_count + 1;
end

        check_core(0, 8'd10, "DIV");
        check_core(1, 8'd9,  "DIV");
        check_core(2, 8'd8,  "DIV");
        check_core(3, 8'd7,  "DIV");
        check_core(4, 8'd6,  "DIV");
        check_core(5, 8'd5,  "DIV");
        check_core(6, 8'd4,  "DIV");
        check_core(7, 8'd3,  "DIV");

        // ════════════════════════════════════════════════════
        // TEST 5: Divide by zero
        // R2 = [2,0,3,0,5,0,7,0]
        // Cores 1,3,5,7 get div by zero
        // div_by_zero_bus expected = 10101010
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 5: Divide by zero ---");
        load_all_cores(4'd1,
            8'd10, 8'd20, 8'd30, 8'd40,
            8'd50, 8'd60, 8'd70, 8'd80);
        load_all_cores(4'd2,
            8'd2, 8'd0, 8'd3, 8'd0,
            8'd5, 8'd0, 8'd7, 8'd0);

        instruction = 16'b1100_0011_0001_0010;
        instr_valid = 1;
        div_start   = 1;
        @(posedge clk);
        instr_valid = 0;
        div_start   = 0;

        // Reset latches before waiting
        div_done_latched    = 8'h00;
        div_by_zero_latched = 8'h00;    
        wait(div_done_bus == 8'hFF);    
        @(posedge clk); #1;

        // Check latched div_by_zero — it pulses same cycle as div_done
        check_flag(div_by_zero_latched, 8'b10101010, "div_by_zero");

        // ════════════════════════════════════════════════════
        // TEST 6: Zero flag bus
        // All cores SUB equal values → all zero
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 6: Zero flag bus ---");
        load_all_cores(4'd1,
            8'd5,  8'd10, 8'd15, 8'd20,
            8'd25, 8'd30, 8'd35, 8'd40);
        load_all_cores(4'd2,
            8'd5,  8'd10, 8'd15, 8'd20,
            8'd25, 8'd30, 8'd35, 8'd40);
        broadcast(16'b0001_0011_0001_0010, 2'b00);
        check_flag(zero_bus, 8'hFF, "zero_bus");

        // ════════════════════════════════════════════════════
        // TEST 7: Negative flag bus
        // All cores SUB 3-10 → result negative
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 7: Negative flag bus ---");
        load_all_same(4'd1, 8'd3);
        load_all_same(4'd2, 8'd10);
        broadcast(16'b0001_0011_0001_0010, 2'b00);
        check_flag(negative_bus, 8'hFF, "negative_bus");

        // ════════════════════════════════════════════════════
        // TEST 8: Carry flag bus
        // All cores ADD 200+100=300 overflow carry=1
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 8: Carry flag bus ---");
        load_all_same(4'd1, 8'd200);
        load_all_same(4'd2, 8'd100);
        broadcast(16'b0000_0011_0001_0010, 2'b00);
        check_flag(carry_bus, 8'hFF, "carry_bus");

        // ════════════════════════════════════════════════════
        // TEST 9: Overflow flag bus
        // All cores ADD 100+100=200 signed overflow
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 9: Overflow flag bus ---");
        load_all_same(4'd1, 8'd100);
        load_all_same(4'd2, 8'd100);
        broadcast(16'b0000_0011_0001_0010, 2'b00);
        check_flag(overflow_bus, 8'hFF, "overflow_bus");

        // ════════════════════════════════════════════════════
        // TEST 10: Parallel dot product
        // A=[1,2,3,4,5,6,7,8] B=[8,7,6,5,4,3,2,1]
        // products: 8,14,18,20,20,18,14,8
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 10: Parallel dot product ---");

        // Clear accumulators
        instr_valid=0; acc_ctrl=2'b11;
        @(posedge clk);
        acc_ctrl=2'b00;
        @(posedge clk);

        load_all_cores(4'd0,
            8'd1, 8'd2, 8'd3, 8'd4,
            8'd5, 8'd6, 8'd7, 8'd8);
        load_all_cores(4'd1,
            8'd8, 8'd7, 8'd6, 8'd5,
            8'd4, 8'd3, 8'd2, 8'd1);

        // MUL R2,R0,R1 acc LOAD
        broadcast(16'b1011_0010_0000_0001, 2'b01);

        // Check results
        check_core(0, 8'd8,  "DOT MUL");
        check_core(1, 8'd14, "DOT MUL");
        check_core(2, 8'd18, "DOT MUL");
        check_core(3, 8'd20, "DOT MUL");
        check_core(4, 8'd20, "DOT MUL");
        check_core(5, 8'd18, "DOT MUL");
        check_core(6, 8'd14, "DOT MUL");
        check_core(7, 8'd8,  "DOT MUL");

        // Check accumulators loaded correctly
        check_acc(0, 8'd8);
        check_acc(1, 8'd14);
        check_acc(2, 8'd18);
        check_acc(3, 8'd20);
        check_acc(4, 8'd20);
        check_acc(5, 8'd18);
        check_acc(6, 8'd14);
        check_acc(7, 8'd8);

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