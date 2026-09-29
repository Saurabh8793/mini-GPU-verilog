`timescale 1ns/1ps

// ============================================================
// GPU Top Level
// Connects warp_scheduler and gpu_core_array
//
// Data flow:
//   External program → warp_scheduler → gpu_core_array
//
// warp_scheduler responsibilities:
//   → receives instruction stream one by one
//   → broadcasts same instruction to all 8 cores
//   → forwards acc_ctrl to all cores
//   → stalls on DIV until all cores finish
//   → pulses done when program complete
//
// gpu_core_array responsibilities:
//   → 8 shader cores running in parallel
//   → each core has own register file and ALU
//   → all cores execute same instruction
//   → each core has different data
//
// External controller responsibilities:
//   → loads data into each core before execution
//   → feeds instructions one by one
//   → sets acc_ctrl per instruction
//   → monitors done signal
// ============================================================

module gpu_top(
    input  wire        clk,
    input  wire        reset,

    // Program control
    input  wire        start,        // pulse to begin execution
    output wire        done,         // pulses when program complete

    // Instruction stream
    // External memory feeds these each cycle
    input  wire [15:0] instruction_in,
    input  wire        instr_valid_in,
    input  wire [1:0]  acc_ctrl_in,  // accumulator mode per instruction
    output wire        instr_advance, // request next instruction

    // Data loading interface
    // Load different data into each core before execution
    input  wire [7:0]  load_en_bus,
    input  wire [3:0]  load_addr,
    input  wire [7:0]  load_data_bus [0:7],

    // Outputs from all 8 cores
    output wire [7:0]  result_bus    [0:7],
    output wire [7:0]  acc_bus       [0:7],
    output wire [7:0]  mul_high_bus  [0:7],

    // Flag buses
    output wire [7:0]  zero_bus,
    output wire [7:0]  carry_bus,
    output wire [7:0]  negative_bus,
    output wire [7:0]  overflow_bus,

    // Division status
    output wire [7:0]  div_done_bus,
    output wire [7:0]  div_by_zero_bus
);

    // ── Internal wires between scheduler and core array ──────

    // Warp scheduler → core array
    wire [15:0] sched_instr;        // broadcast instruction
    wire        sched_instr_valid;  // instruction valid flag
    wire [1:0]  sched_acc_ctrl;     // accumulator control
    wire        sched_div_start;    // start division on all cores

    // Core array → warp scheduler
    // div_done_bus already an output, feed back to scheduler
    // for WAIT state exit condition

    // ── Warp Scheduler ───────────────────────────────────────
    warp_scheduler scheduler(
        .clk(clk),
        .reset(reset),

        // Program control
        .start(start),
        .done(done),

        // Instruction stream from external
        .instruction_in(instruction_in),
        .instr_valid_in(instr_valid_in),
        .acc_ctrl_in(acc_ctrl_in),
        .instr_advance(instr_advance),

        // Broadcast to core array
        .instr_out(sched_instr),
        .instr_valid_out(sched_instr_valid),
        .acc_ctrl(sched_acc_ctrl),

        // Division synchronization
        // div_done_bus from core array feeds back here
        // scheduler stalls in WAIT until all cores done
        .div_done_bus(div_done_bus),
        .div_start(sched_div_start)
    );

    // ── GPU Core Array ───────────────────────────────────────
    gpu_core_array core_array(
        .clk(clk),
        .reset(reset),

        // Instruction from warp scheduler
        .instr_valid(sched_instr_valid),
        .instruction(sched_instr),
        .acc_ctrl(sched_acc_ctrl),

        // Data loading — direct from external
        // Bypasses scheduler, used before execution starts
        .load_en_bus(load_en_bus),
        .load_addr(load_addr),
        .load_data_bus(load_data_bus),

        // Division control
        // div_start from scheduler
        // div_done_bus goes back to scheduler AND out as output
        .div_start(sched_div_start),
        .div_done_bus(div_done_bus),
        .div_by_zero_bus(div_by_zero_bus),

        // Results
        .result_bus(result_bus),
        .acc_bus(acc_bus),
        .mul_high_bus(mul_high_bus),

        // Flags
        .zero_bus(zero_bus),
        .carry_bus(carry_bus),
        .negative_bus(negative_bus),
        .overflow_bus(overflow_bus)
    );

endmodule