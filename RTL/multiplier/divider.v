`timescale 1ns/1ps

// 8-bit Restoring Division Unit
// Sequential implementation running over 8 compute cycles.
// Computes: dividend / divisor = quotient with remainder.

module divider(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [7:0]  dividend,
    input  wire [7:0]  divisor,
    output reg  [7:0]  quotient,
    output reg  [7:0]  remainder,
    output reg         done,
    output reg         div_by_zero
);

localparam IDLE    = 2'b00;
localparam COMPUTE = 2'b01;
localparam FINISH  = 2'b10;

reg [1:0] state;
reg [7:0] D;
reg [7:0] V;
reg [7:0] Q;
reg [7:0] R;
reg [2:0] step;

wire [7:0] R_shifted = {R[6:0], D[7]};
wire [7:0] sub_result;
wire       borrow;

subtractor sub_unit(
    .a(R_shifted),
    .b(V),
    .result(sub_result),
    .bout(borrow)
);

always @(posedge clk) begin
    if (reset) begin
        state       <= IDLE;
        quotient    <= 8'd0;
        remainder   <= 8'd0;
        done        <= 1'b0;
        div_by_zero <= 1'b0;
        D           <= 8'd0;
        V           <= 8'd0;
        Q           <= 8'd0;
        R           <= 8'd0;
        step        <= 3'd0;
    end else case (state)
        IDLE: begin
            done <= 1'b0;
            if (start && divisor == 8'b0) begin
                div_by_zero <= 1'b1;
                quotient    <= 8'hFF;
                remainder   <= 8'hFF;
                done        <= 1'b1;
                state       <= IDLE;
            end else if (start) begin
                div_by_zero <= 1'b0;
                D           <= dividend;
                V           <= divisor;
                Q           <= 8'd0;
                R           <= 8'd0;
                step        <= 3'd0;
                state       <= COMPUTE;
            end
        end

        COMPUTE: begin
            R <= (!borrow) ? sub_result : R_shifted;
            Q <= (!borrow) ? {Q[6:0], 1'b1} : {Q[6:0], 1'b0};
            D <= {D[6:0], 1'b0};

            if (step == 3'd7) state <= FINISH;
            else step <= step + 1'b1;
        end

        FINISH: begin
            quotient  <= Q;
            remainder <= R;
            done      <= 1'b1;
            state     <= IDLE;
        end

        default: state <= IDLE;
    endcase
end

endmodule