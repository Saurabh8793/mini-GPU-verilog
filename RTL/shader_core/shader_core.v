`timescale 1ns/1ps

// ============================================================
// Shader Core v1
// One complete GPU compute unit
//
// Connects:
//   instruction_decoder → field extraction and control signals
//   register_file_16x8  → 16 x 8-bit register storage
//   alu                 → all arithmetic and logic operations
//   accumulator         → explicit accumulation control
//
// Architectural notes:
//
// 1. Accumulator control is EXPLICIT via acc_ctrl input
//    acc_ctrl = 2'b00 HOLD  → accumulator unchanged
//    acc_ctrl = 2'b01 LOAD  → load current ALU result into acc
//    acc_ctrl = 2'b10 ADD   → acc = acc + current ALU result
//    acc_ctrl = 2'b11 CLEAR → acc = 0
//    The warp scheduler or testbench controls acc_ctrl directly
//    This prevents unintended accumulation during normal ops
//
// 2. MUL produces 16-bit result
//    Lower 8 bits → written to dest register and available on result_out
//    Upper 8 bits → available on mul_result_high output
//    Upper bits are NOT written to register file in v1
//
// 3. DIV writeback not implemented in v1
//    div_done pulses high when division completes
//    Quotient available on result_out when div_done=1
//    Future work: latch dest at div_start, write on div_done
//
// 4. load_en takes priority over instruction writeback
//    Used to initialize register file before shader program runs
// ============================================================

module shader_core #(
    parameter CORE_ID = 0
)(
    input  wire        clk,
    input  wire        reset,

    // Instruction interface
    input  wire        instr_valid,
    input  wire [15:0] instruction,

    // Explicit accumulator control
    // Controlled externally by warp scheduler or testbench
    input  wire [1:0]  acc_ctrl,

    // Direct register load interface
    // Used to initialize registers before execution
    input  wire        load_en,
    input  wire [3:0]  load_addr,
    input  wire [7:0]  load_data,

    // Division control
    input  wire        div_start,
    output wire        div_done,
    output wire        div_by_zero,

    // Outputs
    output wire [7:0]  result_out,       // ALU result lower 8 bits
    output wire [7:0]  mul_result_high,  // MUL upper 8 bits
    output wire [7:0]  acc_out,          // accumulator value
    output wire        zero_flag,
    output wire        carry_flag,
    output wire        negative_flag,
    output wire        overflow_flag
);

    // ── Decoded fields ───────────────────────────────────────
    wire [3:0] opcode;
    wire [3:0] dest;
    wire [3:0] src_a;
    wire [3:0] src_b;
    wire       dec_write_enable;
    wire       dec_is_mul;
    wire       dec_is_div;
    wire       dec_use_cla;

    instruction_decoder decoder(
        .instruction(instruction),
        .opcode(opcode),
        .dest(dest),
        .src_a(src_a),
        .src_b(src_b),
        .write_enable(dec_write_enable),
        .is_mul(dec_is_mul),
        .is_div(dec_is_div),
        .use_cla(dec_use_cla)
    );

    // ── ALU output wires ─────────────────────────────────────
    wire [7:0] alu_result;
    wire [7:0] alu_mul_high;
    wire [7:0] unused_div_remainder;  // div remainder, unused in v1
    wire       alu_zero;
    wire       alu_carry;
    wire       alu_negative;
    wire       alu_overflow;

    // ── Register file write control ──────────────────────────
    // Priority: load_en > instruction writeback
    // load_en used for initialization before shader runs
    wire rf_write_enable;
    wire [3:0] rf_write_addr;
    wire [7:0] rf_write_data;
    wire [7:0] rf_read_a;
    wire [7:0] rf_read_b;

    assign rf_write_enable = load_en |
                             (instr_valid & dec_write_enable);
    assign rf_write_addr   = load_en ? load_addr : dest;
    assign rf_write_data   = load_en ? load_data : alu_result;

    register_file_16x8 rf(
        .clk(clk),
        .reset(reset),
        .write_enable(rf_write_enable),
        .write_addr(rf_write_addr),
        .write_data(rf_write_data),
        .read_addr_a(src_a),
        .read_data_a(rf_read_a),
        .read_addr_b(src_b),
        .read_data_b(rf_read_b)
    );

    // ── ALU ──────────────────────────────────────────────────
    // div_start gated with opcode check
    // Divider only starts for actual DIV instructions
    alu alu_unit(
        .clk(clk),
        .reset(reset),
        .opcode(opcode),
        .use_cla(dec_use_cla),
        .a(rf_read_a),
        .b(rf_read_b),
        .start(div_start & instr_valid & dec_is_div),
        .done(div_done),
        .div_by_zero(div_by_zero),
        .result(alu_result),
        .mul_result_high(alu_mul_high),
        .div_remainder(unused_div_remainder),
        .zero_flag(alu_zero),
        .carry_flag(alu_carry),
        .negative_flag(alu_negative),
        .overflow_flag(alu_overflow)
    );

    // ── Accumulator ──────────────────────────────────────────
    // acc_ctrl comes directly from outside
    // No automatic opcode-based triggering
    // Caller decides exactly when and how to update accumulator
    wire acc_zero;
    wire acc_carry_out;

    // Gate acc_ctrl with instr_valid
    // When no instruction is executing, accumulator always HOLDs
    // This prevents accidental accumulation between instructions
    // External controller only needs to assert acc_ctrl during
    // valid instruction cycles
    wire [1:0] effective_acc_ctrl;
    assign effective_acc_ctrl = instr_valid ? acc_ctrl : 2'b00;

    // Unused signal declarations
    // These outputs exist in hardware but not needed at shader
    // core level in v1 — retained for future use
    wire       unused_acc_zero;
    wire       unused_acc_carry;
    

    accumulator acc(
        .clk(clk),
        .reset(reset),
        .acc_mode(effective_acc_ctrl),
        .data_in(alu_result),
        .acc_out(acc_out),
        .zero_flag(unused_acc_zero),
        .carry_out(unused_acc_carry)
    );

    // ── Output assignments ───────────────────────────────────
    assign result_out      = alu_result;
    assign mul_result_high = alu_mul_high;
    assign zero_flag       = alu_zero;
    assign carry_flag      = alu_carry;
    assign negative_flag   = alu_negative;
    assign overflow_flag   = alu_overflow;

endmodule