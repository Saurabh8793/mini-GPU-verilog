`timescale 1ns/1ps

// Instruction Decoder
// Pure combinational circuit
// Splits 16-bit instruction into fields and control signals
//
// Instruction format:
//   [15:12] opcode — ALU operation select
//   [11:8]  dest   — destination register address
//   [7:4]   src_a  — source register A address
//   [3:0]   src_b  — source register B address
//
// Architectural decisions documented here:
//
// 1. write_enable:
//    CMP does not write (flags only)
//    DIV does not write in v1 (sequential completion not yet handled)
//    All other operations write result to dest register
//
// 2. Accumulator:
//    Accumulator is NOT automatically controlled by opcode
//    acc_ctrl is a separate input to shader core
//    This gives explicit control over when accumulator updates
//    prevents accidental accumulation during normal ADD operations
//
// 3. MUL result:
//    16-bit product produced internally by multiplier
//    Lower 8 bits written to register file
//    Upper 8 bits exposed on mul_result_high output
//    Documented 8-bit architecture limitation
//
// 4. DIV future work:
//    When DIV writeback implemented, need to:
//    - latch dest address at div_start
//    - enable write when div_done pulses high

module instruction_decoder(
    input  wire [15:0] instruction,

    // Decoded fields
    output wire [3:0]  opcode,
    output wire [3:0]  dest,
    output wire [3:0]  src_a,
    output wire [3:0]  src_b,

    // Register file write control
    output wire        write_enable,

    // Operation type flags
    // Used by shader core for special handling
    output wire        is_mul,    // MUL instruction
    output wire        is_div,    // DIV instruction

    // Adder selection
    output wire        use_cla    // 1=CLA 0=RCA
);
    assign opcode = instruction[15:12];
    assign dest   = instruction[11:8];
    assign src_a  = instruction[7:4];
    assign src_b  = instruction[3:0];

    // Write enable
    // CMP (1101) → flags only, no writeback
    // DIV (1100) → sequential, writeback not implemented in v1
    assign write_enable = (opcode != 4'b1101) &
                          (opcode != 4'b1100);

    // Operation type flags
    assign is_mul = (opcode == 4'b1011);
    assign is_div = (opcode == 4'b1100);

    // CLA for ADD and SUB — most frequent shader operations
    assign use_cla = (opcode == 4'b0000) |
                     (opcode == 4'b0001);

endmodule