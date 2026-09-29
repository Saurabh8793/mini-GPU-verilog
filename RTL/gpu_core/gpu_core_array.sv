`timescale 1ns/1ps

// ============================================================
// GPU Core Array
// 8 parallel shader cores running simultaneously
//
// This is the heart of the GPU.
// All 8 cores receive the SAME instruction every cycle
// Each core has its OWN register file with DIFFERENT data
// All 8 cores compute in PARALLEL
//
// This implements SIMD:
//   Single Instruction → broadcast from warp scheduler
//   Multiple Data      → different values in each core
//
// Data loading:
//   Before execution, each core loaded with different data
//   load_en_bus[i] enables loading into core i
//   load_addr and load_data are shared (same address/data)
//   OR each core can have individual load data via load_data_bus
//
// Output:
//   result_bus[i] = 8-bit result from core i
//   acc_bus[i]    = accumulator value from core i
// ============================================================

module gpu_core_array(
    input  wire        clk,
    input  wire        reset,

    // Instruction broadcast — same to all cores
    input  wire        instr_valid,
    input  wire [15:0] instruction,
    input  wire [1:0]  acc_ctrl,

    // Individual data loading for each core
    // Each core gets its own data but same address
    input  wire [7:0]  load_en_bus,          // one bit per core
    input  wire [3:0]  load_addr,            // same address all cores
    input  wire [7:0]  load_data_bus [0:7],  // individual data per core

    // Division control
    input  wire        div_start,
    output wire [7:0]  div_done_bus,         // done signal from each core
    output wire [7:0]  div_by_zero_bus,

    // Results from each core
    output wire [7:0]  result_bus    [0:7],
    output wire [7:0]  acc_bus       [0:7],
    output wire [7:0]  mul_high_bus  [0:7],

    // Flags from each core
    output wire [7:0]  zero_bus,
    output wire [7:0]  carry_bus,
    output wire [7:0]  negative_bus,
    output wire [7:0]  overflow_bus
);

    // Generate 8 shader cores
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : core_gen

            shader_core #(.CORE_ID(i)) core(
                .clk(clk),
                .reset(reset),

                // Same instruction to all cores
                .instr_valid(instr_valid),
                .instruction(instruction),
                .acc_ctrl(acc_ctrl),

                // Individual data loading
                .load_en(load_en_bus[i]),
                .load_addr(load_addr),
                .load_data(load_data_bus[i]),

                // Division
                .div_start(div_start),
                .div_done(div_done_bus[i]),
                .div_by_zero(div_by_zero_bus[i]),

                // Outputs
                .result_out(result_bus[i]),
                .mul_result_high(mul_high_bus[i]),
                .acc_out(acc_bus[i]),

                // Flags
                .zero_flag(zero_bus[i]),
                .carry_flag(carry_bus[i]),
                .negative_flag(negative_bus[i]),
                .overflow_flag(overflow_bus[i])
            );

        end
    endgenerate

endmodule