`timescale 1ns/1ps

module shared_memory_tb;

    reg        clk, reset;
    reg [7:0]  write_en_bus;
    reg [5:0]  write_addr_bus [0:7];
    reg [7:0]  write_data_bus [0:7];
    reg [5:0]  read_addr      [0:7];

    wire [7:0] read_data     [0:7];
    wire       write_conflict;
    wire [2:0] write_winner;

    shared_memory uut(
        .clk(clk), .reset(reset),
        .write_en_bus(write_en_bus),
        .write_addr_bus(write_addr_bus),
        .write_data_bus(write_data_bus),
        .read_addr(read_addr),
        .read_data(read_data),
        .write_conflict(write_conflict),
        .write_winner(write_winner)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count;
    integer fail_count;
    integer i;

    task check8;
        input [7:0]   actual;
        input [7:0]   expected;
        input [127:0] label;
        begin
            if (actual === expected) begin
                $display("PASS | %-40s | %0d",
                          label, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | %-40s | got=%0d exp=%0d",
                          label, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check1;
        input         actual;
        input         expected;
        input [127:0] label;
        begin
            if (actual === expected) begin
                $display("PASS | %-40s | %0b",
                          label, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | %-40s | got=%0b exp=%0b",
                          label, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check3;
        input [2:0]   actual;
        input [2:0]   expected;
        input [127:0] label;
        begin
            if (actual === expected) begin
                $display("PASS | %-40s | %0d",
                          label, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL | %-40s | got=%0d exp=%0d",
                          label, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task core_write;
        input [2:0] core;
        input [5:0] addr;
        input [7:0] data;
        begin
            write_en_bus         = (8'h01 << core);
            write_addr_bus[core] = addr;
            write_data_bus[core] = data;
            @(posedge clk);
            write_en_bus = 8'h00;
            @(posedge clk);
        end
    endtask

    task read_check;
        input [2:0]   core;
        input [5:0]   addr;
        input [7:0]   expected;
        input [127:0] label;
        reg [7:0] actual;
        begin
            read_addr[core] = addr;
            #1;
            case (core)
                0: actual = read_data[0];
                1: actual = read_data[1];
                2: actual = read_data[2];
                3: actual = read_data[3];
                4: actual = read_data[4];
                5: actual = read_data[5];
                6: actual = read_data[6];
                7: actual = read_data[7];
                default: actual = 8'hXX;
            endcase
            check8(actual, expected, label);
        end
    endtask

    initial begin
        $dumpfile("shared_memory.vcd");
        $dumpvars(0, shared_memory_tb);

        pass_count   = 0;
        fail_count   = 0;
        write_en_bus = 0;
        reset        = 1;
        for (i=0; i<8; i=i+1) begin
            write_addr_bus[i] = 0;
            write_data_bus[i] = 0;
            read_addr[i]      = 0;
        end
        repeat(3) @(posedge clk);
        reset = 0;
        @(posedge clk);

        // ════════════════════════════════════════════════════
        // TEST 1: Reset — all zero
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 1: Reset ---");
        for (i=0; i<8; i=i+1) read_addr[i] = i;
        #1;
        for (i=0; i<8; i=i+1)
            check8(read_data[i], 8'd0, "reset all zero");

        // ════════════════════════════════════════════════════
        // TEST 2: Per-core independent writes
        // Each core writes its own address and data
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 2: Per-core independent writes ---");
        for (i=0; i<8; i=i+1)
            core_write(i, i, i*10);

        for (i=0; i<8; i=i+1)
            read_check(0, i, i*10, "per-core write");

        // ════════════════════════════════════════════════════
        // TEST 3: 8 simultaneous reads
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 3: 8 simultaneous reads ---");
        for (i=0; i<8; i=i+1) read_addr[i] = i;
        #1;
        for (i=0; i<8; i=i+1)
            check8(read_data[i], i*10, "simul read");

        // ════════════════════════════════════════════════════
        // TEST 4: Priority arbitration — winner ID correct
        // Core 2 and Core 5 both request
        // Core 2 should win (lower ID)
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 4: Priority arbitration ---");
        write_en_bus         = 8'b00100100;
        write_addr_bus[2]    = 6'd20;
        write_data_bus[2]    = 8'd222;
        write_addr_bus[5]    = 6'd50;
        write_data_bus[5]    = 8'd55;
        @(negedge clk);
        check1(write_conflict, 1'b1, "conflict detected");
        check3(write_winner,   3'd2, "winner=core2");
        @(posedge clk);
        write_en_bus = 8'h00;
        @(posedge clk);

        // Verify core 2 won
        read_check(0, 6'd20, 8'd222, "core2 data at addr20");
        // Core 5 dropped — addr 50 untouched
        read_check(0, 6'd50, 8'd0, "core5 dropped addr50=0");

        // ════════════════════════════════════════════════════
        // TEST 5: Lowest ID wins among all combinations
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 5: Lowest ID always wins ---");

        // Cores 3,5,7 all request
        write_en_bus         = 8'b10101000;
        write_addr_bus[3]    = 6'd33;
        write_data_bus[3]    = 8'd33;
        write_addr_bus[5]    = 6'd55;
        write_data_bus[5]    = 8'd55;
        write_addr_bus[7]    = 6'd77 & 6'h3F;
        write_data_bus[7]    = 8'd77;
        @(negedge clk);
        check3(write_winner, 3'd3, "winner=core3 (lowest)");
        @(posedge clk);
        write_en_bus = 8'h00;
        @(posedge clk);
        read_check(0, 6'd33, 8'd33, "core3 data written");

        // ════════════════════════════════════════════════════
        // TEST 6: Cross-core communication
        // Core 0 writes, all others read same location
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 6: Cross-core communication ---");
        core_write(0, 6'd30, 8'd123);
        for (i=0; i<8; i=i+1) read_addr[i] = 6'd30;
        #1;
        for (i=0; i<8; i=i+1)
            check8(read_data[i], 8'd123,
                   "all cores read core0 data");

        // ════════════════════════════════════════════════════
        // TEST 7: Parallel reads from different addresses
        // Eight read ports access eight different addresses simultaneously
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 7: Parallel reads different addr ---");
        for (i=0; i<8; i=i+1)
            core_write(0, i*2, i*5);

        for (i=0; i<8; i=i+1)
            read_addr[i] = i*2;
        #1;
        for (i=0; i<8; i=i+1)
            check8(read_data[i], i*5, "parallel read");

        // ════════════════════════════════════════════════════
        // TEST 8: Boundary addresses 0 and 63
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 8: Boundary addresses ---");
        core_write(0, 6'd0,  8'd255);
        core_write(0, 6'd63, 8'd128);
        read_check(0, 6'd0,  8'd255, "addr 0 boundary");
        read_check(0, 6'd63, 8'd128, "addr 63 boundary");

        // ════════════════════════════════════════════════════
        // TEST 9: Overwrite same address
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 9: Overwrite ---");
        core_write(0, 6'd55, 8'd100);
        read_check(0, 6'd55, 8'd100, "first write");
        core_write(0, 6'd55, 8'd200);
        read_check(0, 6'd55, 8'd200, "overwrite");

        // ════════════════════════════════════════════════════
        // TEST 10: Matrix tile load
        // Cores load rows, all cores read elements
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 10: Matrix tile load ---");
        for (i=0; i<4; i=i+1)
            core_write(0, i, i+1);      // row 0: 1,2,3,4
        for (i=0; i<4; i=i+1)
            core_write(1, 4+i, 4+i+1); // row 1: 5,6,7,8

        read_check(0, 6'd0, 8'd1, "mat[0][0]=1");
        read_check(0, 6'd3, 8'd4, "mat[0][3]=4");
        read_check(1, 6'd4, 8'd5, "mat[1][0]=5");
        read_check(1, 6'd7, 8'd8, "mat[1][3]=8");

        // All cores read same element simultaneously
        for (i=0; i<8; i=i+1) read_addr[i] = 6'd2;
        #1;
        for (i=0; i<8; i=i+1)
            check8(read_data[i], 8'd3,
                   "all cores same element=3");

        // ════════════════════════════════════════════════════
        // TEST 11: Single requester — no conflict
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 11: No conflict single request ---");
        write_en_bus         = 8'b00000100; // only core 2
        write_addr_bus[2]    = 6'd40;
        write_data_bus[2]    = 8'd42;
        @(negedge clk);
        check1(write_conflict, 1'b0, "no conflict single");
        check3(write_winner,   3'd2, "winner=core2");
        @(posedge clk);
        write_en_bus = 8'h00;
        @(posedge clk);

        // ════════════════════════════════════════════════════
        // TEST 12: Reset clears memory
        // ════════════════════════════════════════════════════
        $display("\n--- TEST 12: Reset clears memory ---");
        core_write(0, 6'd10, 8'd42);
        reset = 1; repeat(2) @(posedge clk);
        reset = 0; @(posedge clk);
        read_check(0, 6'd10, 8'd0, "reset clears");

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