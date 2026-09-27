    `timescale 1ns/1ps

    // ============================================================
    // Mini GPU — Arithmetic Logic Unit
    // ============================================================
    // Supported operations (opcode):
    //   0000 → ADD
    //   0001 → SUB
    //   0010 → INC       (a + 1)
    //   0011 → DEC       (a - 1)
    //   0100 → NEG       (two's complement of a)
    //   0101 → AND
    //   0110 → OR
    //   0111 → XOR
    //   1000 → NOT
    //   1001 → SHL       (shift left)
    //   1010 → SHR       (shift right)
    //   1011 → MUL       (8x8 → 16-bit result)
    //   1100 → DIV       (sequential, done signal required)
    //   1101 → CMP       (compare, flags only, result discarded)
    //
    // use_cla:
    //   0 → use Ripple Carry Adder (smaller, slower)
    //   1 → use Carry Lookahead Adder (larger, faster)
    //
    // For DIV: assert start=1 for one cycle, wait for done=1
    // MUL result is 16-bit, upper 8 bits on mul_result_high
    // ============================================================

    module alu(
        input  wire        clk,
        input  wire        reset,

        // Operation select
        input  wire [3:0]  opcode,
        input  wire        use_cla,     // 0=RCA  1=CLA

        // Operands
        input  wire [7:0]  a,
        input  wire [7:0]  b,

        // Division control
        input  wire        start,       // pulse high for one cycle to start DIV
        output wire        done,        // pulses high when DIV is complete
        output wire        div_by_zero, // high if divisor is zero

        // Outputs
        output reg  [7:0]  result,          // main 8-bit result
        output wire [7:0]  mul_result_high, // upper 8 bits of MUL only
        output wire [7:0]  div_remainder,
        // Flags
        output wire        zero_flag,
        output wire        carry_flag,
        output wire        negative_flag,
        output wire        overflow_flag
    );

        // ── Opcode definitions ───────────────────────────────────
        localparam ADD = 4'b0000;
        localparam SUB = 4'b0001;
        localparam INC = 4'b0010;
        localparam DEC = 4'b0011;
        localparam NEG = 4'b0100;
        localparam AND = 4'b0101;
        localparam OR  = 4'b0110;
        localparam XOR = 4'b0111;
        localparam NOT = 4'b1000;
        localparam SHL = 4'b1001;
        localparam SHR = 4'b1010;
        localparam MUL = 4'b1011;
        localparam DIV = 4'b1100;
        localparam CMP = 4'b1101;

        // ── B input mux ──────────────────────────────────────────
        // Different operations need different values on B port
        // INC → b=0, cin=1  (a + 0 + 1 = a+1)
        // DEC → b=1111_1111, cin=0 (a + 0xFF = a-1)
        // NEG → b=0, b_invert on a side — handled differently
        // CMP → same as SUB

    wire [7:0] adder_a_in;
    wire [7:0] adder_b_in;
    wire       b_invert;
    wire       cin;

    // For NEG: a goes into B port so b_invert inverts it
    // A port gets 0
    // Result = 0 + ~a + 1 = -a (two's complement)
    assign adder_a_in = (opcode == NEG) ? 8'b0 : a;

    assign adder_b_in = (opcode == INC) ? 8'b0  :
                        (opcode == DEC) ? 8'hFF  :
                        (opcode == NEG) ? a       :
                                        b;

    assign b_invert = (opcode == SUB) ? 1'b1 :
                    (opcode == NEG) ? 1'b1 :
                    (opcode == CMP) ? 1'b1 :
                                        1'b0;

    assign cin      = (opcode == SUB) ? 1'b1 :
                    (opcode == INC) ? 1'b1 :
                    (opcode == NEG) ? 1'b1 :
                    (opcode == CMP) ? 1'b1 :
                                        1'b0;

        // ── RCA output wires ─────────────────────────────────────
        wire [7:0] rca_result;
        wire       rca_cout;
        wire       rca_zero;
        wire       rca_negative;
        wire       rca_overflow;

        ripple_carry_adder rca(
            .a(adder_a_in),
            .b(adder_b_in),
            .b_invert(b_invert),
            .cin(cin),
            .result(rca_result),
            .cout(rca_cout),
            .zero_flag(rca_zero),
            .negative_flag(rca_negative),
            .overflow_flag(rca_overflow)
        );

        // ── CLA output wires ─────────────────────────────────────
        wire [7:0] cla_result;
        wire       cla_cout;
        wire       cla_zero;
        wire       cla_negative;
        wire       cla_overflow;

        carry_lookahead_adder cla(
            .a(adder_a_in),
            .b(adder_b_in),
            .b_invert(b_invert),
            .cin(cin),
            .result(cla_result),
            .cout(cla_cout),
            .zero_flag(cla_zero),
            .negative_flag(cla_negative),
            .overflow_flag(cla_overflow)
        );

        // ── Select between RCA and CLA ───────────────────────────
        wire [7:0] adder_result;
        wire       adder_cout;
        wire       adder_zero;
        wire       adder_negative;
        wire       adder_overflow;

        assign adder_result   = use_cla ? cla_result   : rca_result;
        assign adder_cout     = use_cla ? cla_cout     : rca_cout;
        assign adder_zero     = use_cla ? cla_zero     : rca_zero;
        assign adder_negative = use_cla ? cla_negative : rca_negative;
        assign adder_overflow = use_cla ? cla_overflow : rca_overflow;

        // ── Logic unit ───────────────────────────────────────────
        // op: 00=AND  01=OR  10=XOR  11=NOT
        wire [1:0] logic_op = (opcode == AND) ? 2'b00 :
                            (opcode == OR)  ? 2'b01 :
                            (opcode == XOR) ? 2'b10 :
                            (opcode == NOT) ? 2'b11 :
                                                2'b00;

        wire [7:0] logic_result;

        logic_unit lu(
            .a(a),
            .b(b),
            .op(logic_op),
            .result(logic_result)
        );

        // ── Shifter ──────────────────────────────────────────────
        // dir: 0=SHL  1=SHR
        wire shift_dir = (opcode == SHR) ? 1'b1 : 1'b0;

        wire [7:0] shift_result;

        LR_shifter shifter(
            .a(a),
            .dir(shift_dir),
            .result(shift_result)
        );

        // ── Multiplier ───────────────────────────────────────────
        wire [15:0] mul_product;

        multiplier mul(
            .a(a),
            .b(b),
            .product(mul_product)
        );

        assign mul_result_high = mul_product[15:8];

        // ── Divider ──────────────────────────────────────────────
        wire [7:0] div_quotient;
        

        divider div(
            .clk(clk),
            .reset(reset),
            .start(start & (opcode == DIV)),
            .dividend(a),
            .divisor(b),
            .quotient(div_quotient),
            .remainder(div_remainder),
            .done(done),
            .div_by_zero(div_by_zero)
        );

        // ── Output MUX ───────────────────────────────────────────
        // Selects which unit's result goes to output
        always @(*) begin
            case (opcode)
                ADD: result = adder_result;
                SUB: result = adder_result;
                INC: result = adder_result;
                DEC: result = adder_result;
                NEG: result = adder_result;
                CMP: result = adder_result;   // flags only, result ignored
                AND: result = logic_result;
                OR:  result = logic_result;
                XOR: result = logic_result;
                NOT: result = logic_result;
                SHL: result = shift_result;
                SHR: result = shift_result;
                MUL: result = mul_product[7:0];  // lower 8 bits
                DIV: result = div_quotient;
                default: result = 8'b0;
            endcase
        end

        // ── Flags ────────────────────────────────────────────────
        assign zero_flag     = (result == 8'b0);
        assign negative_flag = result[7];
        assign carry_flag    = (opcode == ADD || opcode == INC ||
                                opcode == SUB || opcode == DEC ||
                                opcode == CMP) ? adder_cout : 1'b0;
        assign overflow_flag = (opcode == ADD || opcode == INC ||
                                opcode == SUB || opcode == DEC ||
                                opcode == CMP) ? adder_overflow : 1'b0;

    endmodule