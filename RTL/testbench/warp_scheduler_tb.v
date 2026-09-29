`timescale 1ns/1ps

module warp_scheduler_tb;

    reg        clk, reset, start;
    reg [15:0] instruction_in;
    reg        instr_valid_in;
    reg [1:0]  acc_ctrl_in;
    reg [7:0]  div_done_bus;

    wire [15:0] instr_out;
    wire        instr_valid_out;
    wire [1:0]  acc_ctrl;
    wire        instr_advance;
    wire        div_start;
    wire        done;

    warp_scheduler uut(
        .clk(clk), .reset(reset),
        .start(start),
        .done(done),
        .instruction_in(instruction_in),
        .instr_valid_in(instr_valid_in),
        .acc_ctrl_in(acc_ctrl_in),
        .instr_advance(instr_advance),
        .instr_out(instr_out),
        .instr_valid_out(instr_valid_out),
        .acc_ctrl(acc_ctrl),
        .div_done_bus(div_done_bus),
        .div_start(div_start)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg [15:0] prog_mem     [0:5];
    reg [1:0]  acc_ctrl_mem [0:5];
    integer    pc;
    integer    cycle_count;
    integer    div_countdown;
    reg        div_done_just_set;  // prevents same-cycle clear

    initial begin
        $dumpfile("warp_scheduler.vcd");
        $dumpvars(0, warp_scheduler_tb);

        prog_mem[0] = 16'b0000_0011_0001_0010; // ADD
        prog_mem[1] = 16'b1011_0100_0001_0010; // MUL acc LOAD
        prog_mem[2] = 16'b1011_0101_0011_0010; // MUL acc ADD
        prog_mem[3] = 16'b1100_0110_0100_0010; // DIV
        prog_mem[4] = 16'b0001_0111_0011_0001; // SUB
        prog_mem[5] = 16'b0101_1000_0001_0010; // AND

        acc_ctrl_mem[0] = 2'b00;
        acc_ctrl_mem[1] = 2'b01;
        acc_ctrl_mem[2] = 2'b10;
        acc_ctrl_mem[3] = 2'b00;
        acc_ctrl_mem[4] = 2'b00;
        acc_ctrl_mem[5] = 2'b00;

        reset             = 1;
        start             = 0;
        pc                = 0;
        cycle_count       = 0;
        div_countdown     = 0;
        div_done_just_set = 0;
        instruction_in    = prog_mem[0];
        acc_ctrl_in       = acc_ctrl_mem[0];
        instr_valid_in    = 0;
        div_done_bus      = 8'h00;

        repeat(3) @(posedge clk);
        reset = 0;

        @(posedge clk);
        start          = 1;
        instr_valid_in = 1;
        @(posedge clk);
        start = 0;

        repeat(60) begin
            @(negedge clk);
            cycle_count       = cycle_count + 1;
            div_done_just_set = 0;

            // Monitor dispatch
            if (instr_valid_out)
                $display("Cycle %0d | DISPATCH instr=%016b acc_ctrl=%02b",
                          cycle_count, instr_out, acc_ctrl);

            // Monitor div_start
            if (div_start) begin
                $display("Cycle %0d | DIV_START on all cores",
                          cycle_count);
                div_countdown = 10;
            end

            // Count down DIV latency
            if (div_countdown > 0) begin
                div_countdown = div_countdown - 1;
                if (div_countdown == 0) begin
                    div_done_bus      = 8'hFF;
                    div_done_just_set = 1;
                    $display("Cycle %0d | All cores DIV complete",
                              cycle_count);
                end
            end

            // Clear div_done_bus only AFTER scheduler has seen it
            // div_done_just_set prevents clearing on same negedge
            // it was set — guarantees at least one full posedge
            // where all_div_done = 1 inside the scheduler
            if (div_done_bus == 8'hFF && !div_done_just_set) begin
                div_done_bus = 8'h00;
                $display("Cycle %0d | div_done_bus cleared",
                          cycle_count);
            end

            // Monitor done pulse
            if (done)
                $display("Cycle %0d | DONE pulse", cycle_count);

            // Advance PC — stable on negedge
            if (instr_advance) begin
                pc = pc + 1;
                $display("Cycle %0d | ADVANCE to PC=%0d",
                          cycle_count, pc);
                if (pc < 6) begin
                    instruction_in = prog_mem[pc];
                    acc_ctrl_in    = acc_ctrl_mem[pc];
                    instr_valid_in = 1;
                end else begin
                    instruction_in = 16'b0;
                    instr_valid_in = 0;
                    acc_ctrl_in    = 2'b00;
                end
            end
        end

        $display("Warp scheduler testbench complete");
        $finish;
    end

endmodule