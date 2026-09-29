`timescale 1ns/1ps

// ============================================================
// Warp Scheduler
// Controls instruction dispatch to 8 parallel shader cores
//
// Responsibilities:
//   1. Accepts instruction stream from outside
//   2. Broadcasts same instruction to ALL 8 cores
//   3. Forwards acc_ctrl_in to all cores each cycle
//   4. Handles stalling for sequential operations (DIV)
//   5. Signals done as one-cycle pulse when complete
//
// acc_ctrl source:
//   External program controller sets acc_ctrl_in
//   per instruction — scheduler forwards it to all cores
//   This keeps accumulator control explicit and separate
//   from opcode decoding
//
// Data path:
//   instruction_in ──┐
//   instr_valid_in ──┤
//   acc_ctrl_in    ──┤─→ Warp Scheduler ──→ all 8 cores
//   div_done_bus   ──┘
//
// FSM states:
//   IDLE    → waiting for start signal
//   EXECUTE → broadcasting instruction to all cores
//   WAIT    → stalling for DIV completion on all cores
//   DONE    → one cycle pulse, then back to IDLE
// ============================================================

module warp_scheduler(
    input  wire        clk,
    input  wire        reset,

    // Program control
    input  wire        start,
    output reg         done,        // one-cycle pulse when complete

    // Instruction stream from external program controller
    input  wire [15:0] instruction_in,
    input  wire        instr_valid_in,
    input  wire [1:0]  acc_ctrl_in,  // acc mode for this instruction
    output reg         instr_advance, // request next instruction

    // Broadcast outputs to all 8 shader cores
    output reg  [15:0] instr_out,
    output reg         instr_valid_out,
    output reg  [1:0]  acc_ctrl,      // forwarded to all cores

    // Division synchronization
    input  wire [7:0]  div_done_bus,  // div_done from each core
    output reg         div_start      // starts division on all cores
);

    localparam IDLE    = 2'b00;
    localparam EXECUTE = 2'b01;
    localparam WAIT    = 2'b10;
    localparam DONE    = 2'b11;

    reg [1:0] state;

    // DIV instruction detection
    wire is_div = (instruction_in[15:12] == 4'b1100);

    // All 8 cores finished DIV
    // & reduction — true only when ALL bits are 1
    wire all_div_done = &div_done_bus;

    always @(posedge clk) begin
        if (reset) begin
            state           <= IDLE;
            done            <= 1'b0;
            instr_advance   <= 1'b0;
            instr_out       <= 16'b0;
            instr_valid_out <= 1'b0;
            acc_ctrl        <= 2'b00;
            div_start       <= 1'b0;
        end else begin
            // Default every cycle
            instr_advance   <= 1'b0;
            instr_valid_out <= 1'b0;
            div_start       <= 1'b0;
            done            <= 1'b0;
            acc_ctrl        <= 2'b00;  // default HOLD

            case (state)

                IDLE: begin
                    if (start)
                        state <= EXECUTE;
                end

                EXECUTE: begin
                    if (instr_valid_in) begin
                        // Broadcast instruction to all 8 cores
                        instr_out       <= instruction_in;
                        instr_valid_out <= 1'b1;

                        // Forward acc_ctrl from program controller
                        // This is the key fix — acc_ctrl_in drives acc_ctrl
                        acc_ctrl        <= acc_ctrl_in;

                        if (is_div) begin
                            // DIV takes 10 clock cycles
                            // Start all dividers simultaneously
                            // Then stall until all finish
                            div_start <= 1'b1;
                            state     <= WAIT;
                        end else begin
                            // Single cycle instruction
                            // Request next instruction immediately
                            instr_advance <= 1'b1;
                        end
                    end else begin
                        // No more valid instructions
                        state <= DONE;
                    end
                end

                WAIT: begin
                    // Hold until ALL 8 cores finish DIV
                    // No new instruction dispatched during wait
                    instr_valid_out <= 1'b0;
                    acc_ctrl        <= 2'b00;  // HOLD acc during wait

                    if (all_div_done) begin
                        instr_advance <= 1'b1;
                        state         <= EXECUTE;
                    end
                end

                DONE: begin
                    // One cycle pulse to signal completion
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule