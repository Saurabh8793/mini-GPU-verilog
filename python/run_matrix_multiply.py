# ============================================================
# Matrix Multiplication Interactive Runner
# Generates a custom Verilog testbench based on user input,
# compiles + simulates it with iverilog/vvp, then compares
# the GPU result against a NumPy reference.
#
# Constraints enforced:
#   - Matrix elements must be 0..7  (8-bit accumulator safe)
#   - Shared memory is 64 locations (must fit A + B + C)
#   - K (shared dimension) <= 5    (7^2 * 5 = 245 < 255)
# ============================================================

import subprocess
import os
import sys
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import matplotlib.patches as mpatches


SHARED_MEM_SIZE = 64   # shared memory has 64 locations
MAX_ELEMENT     = 7    # framebuffer stores 8-bit values; > 7 can't be stored
MAX_K_SAFE      = 5    # 7^2 * K < 255 only when K <= 5


# ── Input helpers ─────────────────────────────────────────────────────────────

def validate_dimensions(M, K, N):
    """Check that A(MxK) x B(KxN) -> C(MxN) fits in shared memory."""
    mem_needed = M * K + K * N + M * N
    if mem_needed > SHARED_MEM_SIZE:
        return False, (
            f"Shared memory overflow: "
            f"A({M*K}) + B({K*N}) + C({M*N}) "
            f"= {mem_needed} > {SHARED_MEM_SIZE}")
    if K > MAX_K_SAFE:
        return False, (
            f"K={K} would overflow accumulator: "
            f"{MAX_ELEMENT}^2 x {K} = {MAX_ELEMENT**2*K} >= 255. "
            f"Max K is {MAX_K_SAFE}.")
    return True, "OK"


def print_valid_combinations():
    print("\nSome valid matrix size combinations:")
    print(f"  {'A':<8} x {'B':<8} -> {'C':<8}  Mem used")
    print("  " + "-" * 40)
    for M in range(2, 6):
        for K in range(2, MAX_K_SAFE + 1):
            for N in range(2, 6):
                valid, _ = validate_dimensions(M, K, N)
                if valid:
                    mem = M * K + K * N + M * N
                    print(f"  {M}x{K:<5}   {K}x{N:<5}   "
                          f"{M}x{N:<5}   {mem}/{SHARED_MEM_SIZE}")


def get_dimension(prompt, min_val, max_val):
    while True:
        try:
            val = int(input(prompt))
            if min_val <= val <= max_val:
                return val
            print(f"  Must be between {min_val} and {max_val}.")
        except ValueError:
            print("  Please enter a valid integer.")


def get_matrix(name, rows, cols):
    print(f"\nEnter Matrix {name} ({rows}x{cols}):")
    print(f"  Each element must be 0..{MAX_ELEMENT}. "
          f"Enter {cols} space-separated integers per row.")
    matrix = []
    for i in range(rows):
        while True:
            try:
                raw = input(f"  Row {i}: ").strip().split()
                if len(raw) != cols:
                    print(f"  Need exactly {cols} values.")
                    continue
                row = [int(x) for x in raw]
                if any(v < 0 or v > MAX_ELEMENT for v in row):
                    print(f"  Values must be 0..{MAX_ELEMENT} "
                          f"(framebuffer is 8-bit, values > {MAX_ELEMENT} "
                          f"cannot be reliably stored/displayed).")
                    continue
                matrix.append(row)
                break
            except ValueError:
                print("  Integers only.")
    return matrix


def print_matrix(name, matrix):
    print(f"\n  Matrix {name}:")
    for row in matrix:
        vals = "  ".join(f"{v:3d}" for v in row)
        print(f"    [ {vals} ]")


def compute_numpy_reference(A, B):
    """Multiply A x B using NumPy, mask to 8-bit (matching GPU behaviour)."""
    A_np = np.array(A, dtype=int)
    B_np = np.array(B, dtype=int)
    return (A_np @ B_np) & 0xFF


# ── Verilog generator ─────────────────────────────────────────────────────────

def generate_verilog_demo(M, K, N, A, B, output_path):
    """
    Produce a fully self-contained SystemVerilog testbench that:
      - inlines the matrix values (no file I/O at simulation time)
      - uses all 8 GPU cores in parallel (SIMD)
        Cores 0-3 handle row r0, cores 4-7 handle row r1 of each batch
      - writes results to matrix_result.hex for the Python visualiser
    """

    a_base = 0
    b_base = M * K
    c_base = M * K + K * N

    # ── Helper: generate matrix-A assignments ─────────────────
    a_assigns = "\n".join(
        f"        mat_a[{i}][{j}] = {A[i][j]};"
        for i in range(M) for j in range(K))

    # ── Helper: generate matrix-B assignments ─────────────────
    b_assigns = "\n".join(
        f"        mat_b[{i}][{j}] = {B[i][j]};"
        for i in range(K) for j in range(N))

    # ── Helper: $display for matrix A ─────────────────────────
    disp_a = "\n".join(
        '        $display("  [' + " ".join(["%0d"] * K) + ']", '
        + ", ".join(f"mat_a[{i}][{j}]" for j in range(K)) + ');'
        for i in range(M))

    # ── Helper: $display for matrix B ─────────────────────────
    disp_b = "\n".join(
        '        $display("  [' + " ".join(["%0d"] * N) + ']", '
        + ", ".join(f"mat_b[{i}][{j}]" for j in range(N)) + ');'
        for i in range(K))

    # ── Helper: $display for matrix C ─────────────────────────
    disp_c = "\n".join(
        '        $display("  [' + " ".join(["%3d"] * N) + ']", '
        + ", ".join(f"mat_c[{i}][{j}]" for j in range(N)) + ');'
        for i in range(M))

    # ── Helper: load A into shared memory ─────────────────────
    load_a = "\n".join(
        f"        sm_write({a_base}+{i}*K+{j}, mat_a[{i}][{j}]);"
        for i in range(M) for j in range(K))

    # ── Helper: load B into shared memory ─────────────────────
    load_b = "\n".join(
        f"        sm_write({b_base}+{i}*N+{j}, mat_b[{i}][{j}]);"
        for i in range(K) for j in range(N))

    # ── Helper: compute_rows() batch calls ────────────────────
    batch_calls = []
    row = 0
    while row < M:
        r0 = row
        r1 = row + 1 if row + 1 < M else -1
        suffix = f" and {r1}" if r1 >= 0 else " only"
        batch_calls.append(
            f"        compute_rows({r0}, {r1});  // rows {r0}{suffix}")
        row += 2
    batch_calls_str = "\n".join(batch_calls)

    # ── Helper: read results from acc_bus into mat_c ──────────
    # Cores 0..N-1 hold C[r0][0..N-1]; cores 4..4+N-1 hold C[r1][0..N-1]
    # We clamp to 4 cores per row (GPU has 8 cores, 4 per row-group)
    read_r0 = "\n".join(
        f"                    {j}: mat_c[r0][{j}] = acc_bus[{j}];"
        for j in range(N))
    read_r1 = "\n".join(
        f"                        {j}: mat_c[r1][{j}] = acc_bus[{j + 4}];"
        for j in range(N))

    # ── Helper: write C rows back to shared memory ─────────────
    write_r0 = "\n".join(
        f"                    {j}: sm_write({c_base}+r0*{N}+{j}, mat_c[r0][{j}]);"
        for j in range(N))
    write_r1 = "\n".join(
        f"                        {j}: sm_write({c_base}+r1*{N}+{j}, mat_c[r1][{j}]);"
        for j in range(N))

    # ── Helper: fwrite for matrix A ───────────────────────────
    fwrite_a = "\n".join(
        '            $fwrite(file_handle, "' + ",".join(["%0d"] * K)
        + '\\n", ' + ",".join(f"mat_a[{i}][{j}]" for j in range(K)) + ');'
        for i in range(M))

    # ── Helper: fwrite for matrix B ───────────────────────────
    fwrite_b = "\n".join(
        '            $fwrite(file_handle, "' + ",".join(["%0d"] * N)
        + '\\n", ' + ",".join(f"mat_b[{i}][{j}]" for j in range(N)) + ');'
        for i in range(K))

    # ── Helper: fwrite for matrix C ───────────────────────────
    fwrite_c = "\n".join(
        '            $fwrite(file_handle, "' + ",".join(["%0d"] * N)
        + '\\n", ' + ",".join(f"mat_c[{i}][{j}]" for j in range(N)) + ');'
        for i in range(M))

    # ── Helper: fwrite for reference C ────────────────────────
    fwrite_ref = "\n".join(
        '            $fwrite(file_handle, "' + ",".join(["%0d"] * N)
        + '\\n", ' + ",".join(f"ref_c[{i}][{j}]" for j in range(N)) + ');'
        for i in range(M))

    # B column index per core (clamped so we never go out of range)
    # Cores 0-3 handle row r0; B col assigned by core index mod N
    b_col = [min(c, N - 1) for c in range(4)]

    # ── Assemble complete Verilog file ─────────────────────────
    sv = f"""`timescale 1ns/1ps

// ============================================================
// Matrix Multiplication Demo  —  Auto-generated by run_matrix_multiply.py
// C = A x B
// A: {M}x{K}   B: {K}x{N}   C: {M}x{N}
//
// Shared-memory layout:
//   A  :  addresses {a_base} .. {b_base - 1}
//   B  :  addresses {b_base} .. {c_base - 1}
//   C  :  addresses {c_base} .. {c_base + M * N - 1}
//
// Parallel execution:  8 GPU cores
//   Cores 0-3  compute one row of C  (row r0)
//   Cores 4-7  compute next row of C (row r1, if it exists)
//   Two rows are therefore computed simultaneously per batch.
// ============================================================

module matrix_multiply_demo;

    localparam M = {M};  // rows of A
    localparam K = {K};  // cols of A / rows of B
    localparam N = {N};  // cols of B

    localparam A_BASE = {a_base};
    localparam B_BASE = {b_base};
    localparam C_BASE = {c_base};

    reg clk, reset;
    initial clk = 0;
    always #5 clk = ~clk;

    // ── GPU top interface ─────────────────────────────────────
    reg        start;
    reg [15:0] instruction_in;
    reg        instr_valid_in;
    reg [1:0]  acc_ctrl_in;
    reg [7:0]  load_en_bus;
    reg [3:0]  load_addr;
    reg [7:0]  load_data_bus [0:7];

    wire        instr_advance;
    wire        gpu_done;
    wire [7:0]  result_bus   [0:7];
    wire [7:0]  acc_bus      [0:7];
    wire [7:0]  mul_high_bus [0:7];
    wire [7:0]  zero_bus, carry_bus;
    wire [7:0]  negative_bus, overflow_bus;
    wire [7:0]  div_done_bus, div_by_zero_bus;

    gpu_top dut(
        .clk(clk), .reset(reset),
        .start(start), .done(gpu_done),
        .instruction_in(instruction_in),
        .instr_valid_in(instr_valid_in),
        .acc_ctrl_in(acc_ctrl_in),
        .instr_advance(instr_advance),
        .load_en_bus(load_en_bus),
        .load_addr(load_addr),
        .load_data_bus(load_data_bus),
        .result_bus(result_bus),
        .acc_bus(acc_bus),
        .mul_high_bus(mul_high_bus),
        .zero_bus(zero_bus),
        .carry_bus(carry_bus),
        .negative_bus(negative_bus),
        .overflow_bus(overflow_bus),
        .div_done_bus(div_done_bus),
        .div_by_zero_bus(div_by_zero_bus)
    );

    // ── Shared memory ─────────────────────────────────────────
    reg [7:0]  sm_write_en_bus;
    reg [5:0]  sm_write_addr [0:7];
    reg [7:0]  sm_write_data [0:7];
    reg [5:0]  sm_read_addr  [0:7];
    wire [7:0] sm_read_data  [0:7];
    wire       sm_conflict;
    wire [2:0] sm_winner;

    shared_memory sm(
        .clk(clk), .reset(reset),
        .write_en_bus(sm_write_en_bus),
        .write_addr_bus(sm_write_addr),
        .write_data_bus(sm_write_data),
        .read_addr(sm_read_addr),
        .read_data(sm_read_data),
        .write_conflict(sm_conflict),
        .write_winner(sm_winner)
    );

    // ── Matrix storage ────────────────────────────────────────
    reg [7:0] mat_a [0:{M-1}][0:{K-1}];
    reg [7:0] mat_b [0:{K-1}][0:{N-1}];
    reg [7:0] mat_c [0:{M-1}][0:{N-1}];
    reg [7:0] ref_c [0:{M-1}][0:{N-1}];

    integer file_handle;
    integer i, j, k;
    integer t_start, t_end, total_cycles;

    // ── Task: load one value into every core's register ───────
    task load_all;
        input [3:0] addr;
        input [7:0] d0, d1, d2, d3, d4, d5, d6, d7;
        begin
            load_addr        = addr;
            load_data_bus[0] = d0; load_data_bus[1] = d1;
            load_data_bus[2] = d2; load_data_bus[3] = d3;
            load_data_bus[4] = d4; load_data_bus[5] = d5;
            load_data_bus[6] = d6; load_data_bus[7] = d7;
            load_en_bus      = 8'hFF;
            instr_valid_in   = 0;
            @(posedge clk);
            load_en_bus = 8'h00;
            @(posedge clk);
        end
    endtask

    // ── Task: dispatch one instruction to all cores ───────────
    task run_one_instr;
        input [15:0] instr;
        input [1:0]  acc_mode;
        begin
            instruction_in = instr;
            acc_ctrl_in    = acc_mode;
            instr_valid_in = 1;
            @(negedge clk); start = 1;
            @(negedge clk); start = 0;
            repeat(10000) begin
                @(negedge clk);
                if (instr_advance) begin
                    instr_valid_in = 0;
                    acc_ctrl_in    = 2'b00;
                end
                if (gpu_done) disable run_one_instr;
            end
        end
    endtask

    // ── Task: write one byte into shared memory via core 0 ────
    task sm_write;
        input [5:0] addr;
        input [7:0] data;
        begin
            sm_write_en_bus  = 8'h01;
            sm_write_addr[0] = addr;
            sm_write_data[0] = data;
            @(posedge clk);
            sm_write_en_bus = 8'h00;
            @(posedge clk);
        end
    endtask

    // ── Task: compute two rows of C in parallel ───────────────
    //
    // Cores 0-3 compute C[r0][0..N-1]
    // Cores 4-7 compute C[r1][0..N-1]  (skipped when r1 == -1)
    //
    // For each accumulation term k:
    //   1. Load A[r0][k] into reg-0 of cores 0-3
    //      Load A[r1][k] into reg-0 of cores 4-7  (or 0 if r1 invalid)
    //   2. Load B[k][col] into reg-1 of each core
    //      Core c gets B[k][ col(c) ] where col(c) = c mod N
    //   3. Execute MUL-ACC instruction
    //
    task compute_rows;
        input integer r0;
        input integer r1;   // pass -1 if no second row
        integer acc_term;
        integer ci;
        begin
            // Clear accumulators in all cores
            @(posedge clk);
            acc_ctrl_in = 2'b11;
            @(posedge clk);
            acc_ctrl_in = 2'b00;

            for (acc_term = 0; acc_term < {K}; acc_term = acc_term + 1) begin

                // ── Step 1: load A elements ───────────────────
                // All four cores in each group get the same A[row][k]
                sm_read_addr[0] = {a_base} + r0*{K} + acc_term;
                sm_read_addr[1] = {a_base} + r0*{K} + acc_term;
                sm_read_addr[2] = {a_base} + r0*{K} + acc_term;
                sm_read_addr[3] = {a_base} + r0*{K} + acc_term;

                if (r1 >= 0) begin
                    sm_read_addr[4] = {a_base} + r1*{K} + acc_term;
                    sm_read_addr[5] = {a_base} + r1*{K} + acc_term;
                    sm_read_addr[6] = {a_base} + r1*{K} + acc_term;
                    sm_read_addr[7] = {a_base} + r1*{K} + acc_term;
                end else begin
                    sm_read_addr[4] = 0;
                    sm_read_addr[5] = 0;
                    sm_read_addr[6] = 0;
                    sm_read_addr[7] = 0;
                end

                @(posedge clk); #1;
                load_all(4'd0,
                    sm_read_data[0], sm_read_data[1],
                    sm_read_data[2], sm_read_data[3],
                    sm_read_data[4], sm_read_data[5],
                    sm_read_data[6], sm_read_data[7]);

                // ── Step 2: load B elements ───────────────────
                // Each core picks its own column of B
                sm_read_addr[0] = {b_base} + acc_term*{N} + {b_col[0]};
                sm_read_addr[1] = {b_base} + acc_term*{N} + {b_col[1]};
                sm_read_addr[2] = {b_base} + acc_term*{N} + {b_col[2]};
                sm_read_addr[3] = {b_base} + acc_term*{N} + {b_col[3]};
                sm_read_addr[4] = {b_base} + acc_term*{N} + {b_col[0]};
                sm_read_addr[5] = {b_base} + acc_term*{N} + {b_col[1]};
                sm_read_addr[6] = {b_base} + acc_term*{N} + {b_col[2]};
                sm_read_addr[7] = {b_base} + acc_term*{N} + {b_col[3]};

                @(posedge clk); #1;
                load_all(4'd1,
                    sm_read_data[0], sm_read_data[1],
                    sm_read_data[2], sm_read_data[3],
                    sm_read_data[4], sm_read_data[5],
                    sm_read_data[6], sm_read_data[7]);

                // ── Step 3: multiply-accumulate ───────────────
                // acc_mode 01 = set (first term), 10 = accumulate
                if (acc_term == 0)
                    run_one_instr(16'b1011_0010_0000_0001, 2'b01);
                else
                    run_one_instr(16'b1011_0010_0000_0001, 2'b10);
                @(posedge clk); #1;
            end

            // ── Collect results from accumulators ────────────
            for (ci = 0; ci < {N}; ci = ci + 1) begin
                case (ci)
{read_r0}
                endcase
                if (r1 >= 0) begin
                    case (ci)
{read_r1}
                    endcase
                end
            end

            // ── Write C rows back to shared memory ───────────
            for (ci = 0; ci < {N}; ci = ci + 1) begin
                case (ci)
{write_r0}
                endcase
                if (r1 >= 0) begin
                    case (ci)
{write_r1}
                    endcase
                end
            end
        end
    endtask

    // ── Main test sequence ────────────────────────────────────
    initial begin
        $dumpfile("matrix_multiply.vcd");
        $dumpvars(0, matrix_multiply_demo);

        // Initialise all signals
        reset=1; start=0; instr_valid_in=0;
        acc_ctrl_in=2'b00; load_en_bus=8'h00;
        load_addr=0; instruction_in=0;
        sm_write_en_bus=8'h00;
        for (i=0; i<8; i=i+1) begin
            load_data_bus[i]=0;
            sm_write_addr[i]=0;
            sm_write_data[i]=0;
            sm_read_addr[i]=0;
        end

        repeat(4) @(posedge clk);
        reset=0; @(posedge clk);

        // ── Inline matrix values (generated by Python) ────────
        // Matrix A
{a_assigns}

        // Matrix B
{b_assigns}

        $display("============================================");
        $display("  Mini GPU  -  {M}x{K} x {K}x{N} Matrix Multiply");
        $display("  C = A x B  (parallel, 8 GPU cores)");
        $display("============================================");

        $display("\\nMatrix A ({M}x{K}):");
{disp_a}

        $display("\\nMatrix B ({K}x{N}):");
{disp_b}

        $display("--------------------------------------------");

        // ── Load A into shared memory ─────────────────────────
{load_a}

        // ── Load B into shared memory ─────────────────────────
{load_b}

        $display("Matrices loaded. Running GPU...");
        t_start = $time;

        // ── Dispatch computation batches ──────────────────────
{batch_calls_str}

        t_end = $time;
        total_cycles = (t_end - t_start) / 10;

        $display("\\nMatrix C = A x B ({M}x{N}):");
{disp_c}

        // ── Software verification (inline) ────────────────────
        begin : verify
            integer correct;
            integer exp;
            correct = 1;
            for (i=0; i<{M}; i=i+1) begin
                for (j=0; j<{N}; j=j+1) begin
                    exp = 0;
                    for (k=0; k<{K}; k=k+1)
                        exp = exp + mat_a[i][k] * mat_b[k][j];
                    ref_c[i][j] = exp[7:0];
                    if (mat_c[i][j] !== ref_c[i][j]) begin
                        $display("  MISMATCH C[%0d][%0d]: got=%0d expected=%0d",
                                 i, j, mat_c[i][j], ref_c[i][j]);
                        correct = 0;
                    end
                end
            end
            if (correct) $display("  ALL ELEMENTS MATCH  (GPU == Reference)");
        end

        $display("\\nGPU cycles: %0d", total_cycles);

        // ── Write result file ─────────────────────────────────
        file_handle = $fopen("matrix_result.hex", "w");
        if (file_handle != 0) begin
            $fwrite(file_handle, "# Matrix A\\n");
{fwrite_a}
            $fwrite(file_handle, "# Matrix B\\n");
{fwrite_b}
            $fwrite(file_handle, "# Matrix C\\n");
{fwrite_c}
            $fwrite(file_handle, "# Reference\\n");
{fwrite_ref}
            $fwrite(file_handle, "cycles,%0d\\n", total_cycles);
            $fwrite(file_handle, "# dims,{M},{K},{N}\\n");
            $fclose(file_handle);
        end

        $finish;
    end

endmodule
"""

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(sv)
    print(f"Generated: {output_path}")


# ── Simulation runner ─────────────────────────────────────────────────────────

def run_simulation(rtl_dir, demo_path):
    """Compile and simulate the generated demo with iverilog + vvp."""
    print("\nCompiling...")

    compile_files = [
        r"gate\gates.v",
        r"adder\adder.v",
        r"adder\ripple_carry_adder.v",
        r"adder\carry_look_ahead.v",
        r"adder\ripple_carry_adder_16bit.v",
        r"subtractor\subtractor.v",
        r"logic_unit\logic.v",
        r"shifter\LR_shifter.v",
        r"multiplier\multiplier.v",
        r"multiplier\divider.v",
        r"sel_alu\alu.v",
        r"register_file\dff.v",
        r"register_file\register_8bit.v",
        r"register_file\register_file_16x8.v",
        r"register_file\accumulator.v",
        r"shader_core\instruction_decoder.v",
        r"shader_core\shader_core.v",
        r"gpu_core\gpu_core_array.sv",
        r"gpu_core\warp_scheduler.v",
        r"gpu_core\gpu_top.sv",
        r"shared_memory\priority_encoder_8.v",
        r"shared_memory\mux_64to1_8bit.v",
        r"shared_memory\shared_memory.sv",
        os.path.relpath(demo_path, rtl_dir),
    ]

    compile_cmd = ["iverilog", "-g2012", "-o", "matmul_demo"] + compile_files
    result = subprocess.run(
        compile_cmd, cwd=rtl_dir, capture_output=True, text=True)

    if result.returncode != 0:
        print("Compile FAILED:")
        print(result.stderr)
        return False
    print("Compile OK")

    result = subprocess.run(
        ["vvp", "matmul_demo"],
        cwd=rtl_dir, capture_output=True, text=True)

    print(result.stdout)
    if result.returncode != 0:
        print("Simulation FAILED:")
        print(result.stderr)
        return False
    return True


# ── Result parser & comparison printer ───────────────────────────────────────

def parse_result_hex(path, M, K, N):
    """Read matrix_result.hex and return A, B, C_gpu, C_ref, cycles.

    Parses section-header comments the same way matrix_viz.py does,
    so both tools read the identical file without conflict.
    """
    sections = {'A': [], 'B': [], 'C': [], 'Reference': []}
    current  = None
    cycles   = 0

    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line == '# Matrix A':
                current = 'A'
            elif line == '# Matrix B':
                current = 'B'
            elif line == '# Matrix C':
                current = 'C'
            elif line == '# Reference':
                current = 'Reference'
            elif line.startswith('cycles,'):
                cycles = int(line.split(',')[1])
            elif line.startswith('#'):
                pass          # skip # dims,... and any future comments
            elif current:
                sections[current].append(
                    list(map(int, line.split(','))))

    return (sections['A'], sections['B'],
            sections['C'], sections['Reference'], cycles)


def print_comparison(A, B, C_gpu, C_ref, C_numpy, M, K, N, cycles):
    """Pretty-print a side-by-side comparison table."""
    sep = "=" * 60
    print(f"\n{sep}")
    print("  RESULT COMPARISON")
    print(sep)

    print(f"\n  Matrix A ({M}x{K}):")
    for row in A:
        print("    [ " + "  ".join(f"{v:3d}" for v in row) + " ]")

    print(f"\n  Matrix B ({K}x{N}):")
    for row in B:
        print("    [ " + "  ".join(f"{v:3d}" for v in row) + " ]")

    print(f"\n  C = A x B  ({M}x{N})")
    print(f"  {'GPU Result':<22}  {'NumPy Reference':<22}  Match?")
    print("  " + "-" * 54)

    all_match = True
    for i in range(M):
        gpu_row  = "[ " + "  ".join(f"{v:3d}" for v in C_gpu[i])   + " ]"
        ref_row  = "[ " + "  ".join(f"{v:3d}" for v in C_numpy[i]) + " ]"
        match    = all(C_gpu[i][j] == int(C_numpy[i][j]) for j in range(N))
        mark     = "✓" if match else "✗"
        if not match:
            all_match = False
        print(f"  {gpu_row:<22}  {ref_row:<22}  {mark}")

    print()
    if all_match:
        print("  ✓  GPU output matches NumPy reference perfectly!")
    else:
        print("  ✗  MISMATCH detected — check GPU computation.")
    print(f"\n  GPU simulation cycles: {cycles}")
    print(sep)


# ── Heatmap visualiser ───────────────────────────────────────────────────────

def _draw_matrix_heatmap(ax, data, title, cmap, vmin, vmax,
                         fmt='.0f', annot_color_thresh=0.5):
    """Draw a single annotated heatmap on *ax*."""
    arr = np.array(data, dtype=float)
    im  = ax.imshow(arr, cmap=cmap, vmin=vmin, vmax=vmax, aspect='auto')

    rows, cols = arr.shape
    for r in range(rows):
        for c in range(cols):
            val = arr[r, c]
            # White text on dark cells, black on bright cells
            brightness = (val - vmin) / max(vmax - vmin, 1)
            color = 'white' if brightness < annot_color_thresh else 'black'
            ax.text(c, r, f'{int(val)}',
                    ha='center', va='center',
                    fontsize=11, fontweight='bold', color=color)

    ax.set_xticks(range(cols))
    ax.set_yticks(range(rows))
    ax.set_xticklabels([f'col {i}' for i in range(cols)], fontsize=8)
    ax.set_yticklabels([f'row {i}' for i in range(rows)], fontsize=8)
    ax.set_title(title, fontsize=12, fontweight='bold', pad=8)
    ax.tick_params(length=0)
    for spine in ax.spines.values():
        spine.set_visible(False)
    return im


def visualize_results(A, B, C_gpu, C_numpy, M, K, N, cycles):
    """
    Show a 5-panel heatmap figure:
      [A]  [B]  |  [GPU C]  [NumPy C]  [Match grid]
    Saves to matrix_result_heatmap.png and displays interactively.
    Works for any M×K and K×N dimensions.
    """
    A_arr   = np.array(A,          dtype=float)
    B_arr   = np.array(B,          dtype=float)
    C_gpu_a = np.array(C_gpu,      dtype=float)
    C_ref_a = np.array(C_numpy,    dtype=float)
    match_a = (C_gpu_a == C_ref_a).astype(float)   # 1 = match, 0 = mismatch

    all_match = bool(match_a.all())
    vmax_input  = max(A_arr.max(), B_arr.max(), 1)
    vmax_output = max(C_gpu_a.max(), C_ref_a.max(), 1)

    # ── Layout: 2 rows of sub-plots ─────────────────────────────
    # Row 0: A  (M×K)  |  B  (K×N)
    # Row 1: GPU C  (M×N)  |  NumPy C  (M×N)  |  Match  (M×N)
    BG = '#0D1117'
    fig = plt.figure(figsize=(16, 9), facecolor=BG)
    fig.patch.set_facecolor(BG)

    status_str = '✓  ALL MATCH' if all_match else '✗  MISMATCH'
    status_col = '#39d353'       if all_match else '#f85149'

    fig.suptitle(
        f'Mini GPU — Matrix Multiplication  '
        f'({M}×{K}) × ({K}×{N}) = ({M}×{N})\n'
        f'8 Shader Cores (SIMD) | Shared Memory | '
        f'{cycles} simulation cycles | {status_str}',
        fontsize=13, fontweight='bold',
        color='white', y=0.98)

    # GridSpec: 2 rows, 3 cols.  Row 0 spans cols 0-1 (A) and col 2 (B).
    # Row 1 has GPU-C, NumPy-C, Match.
    gs = gridspec.GridSpec(
        2, 3,
        hspace=0.55, wspace=0.35,
        left=0.06, right=0.97,
        top=0.88,  bottom=0.08)

    ax_a     = fig.add_subplot(gs[0, 0])
    ax_b     = fig.add_subplot(gs[0, 1])
    ax_info  = fig.add_subplot(gs[0, 2])   # architecture info panel
    ax_gpu   = fig.add_subplot(gs[1, 0])
    ax_ref   = fig.add_subplot(gs[1, 1])
    ax_match = fig.add_subplot(gs[1, 2])

    dark_axes = [ax_a, ax_b, ax_info, ax_gpu, ax_ref, ax_match]
    for ax in dark_axes:
        ax.set_facecolor('#161b22')

    # ── Input matrices ────────────────────────────────────────
    _draw_matrix_heatmap(ax_a, A_arr,
                         f'Matrix A  ({M}×{K})  [input]',
                         'Blues', 0, vmax_input)
    _draw_matrix_heatmap(ax_b, B_arr,
                         f'Matrix B  ({K}×{N})  [input]',
                         'Purples', 0, vmax_input)

    # ── Output matrices ───────────────────────────────────────
    _draw_matrix_heatmap(ax_gpu, C_gpu_a,
                         f'C = A×B  ({M}×{N})  — GPU result',
                         'YlOrRd', 0, vmax_output,
                         annot_color_thresh=0.6)
    _draw_matrix_heatmap(ax_ref, C_ref_a,
                         f'C = A×B  ({M}×{N})  — NumPy reference',
                         'YlGn', 0, vmax_output,
                         annot_color_thresh=0.6)

    # ── Match grid ────────────────────────────────────────────
    match_cmap = plt.cm.colors.ListedColormap(['#f85149', '#39d353']) \
        if hasattr(plt.cm, 'colors') else 'RdYlGn'
    # Build a two-colour map manually (red=0, green=1)
    from matplotlib.colors import ListedColormap
    match_cmap = ListedColormap(['#f85149', '#39d353'])
    ax_match.imshow(match_a, cmap=match_cmap, vmin=0, vmax=1, aspect='auto')
    rows, cols = match_a.shape
    for r in range(rows):
        for c in range(cols):
            sym = '✓' if match_a[r, c] else '✗'
            col = 'white'
            ax_match.text(c, r, sym,
                          ha='center', va='center',
                          fontsize=14, fontweight='bold', color=col)
    ax_match.set_xticks(range(cols))
    ax_match.set_yticks(range(rows))
    ax_match.set_xticklabels([f'col {i}' for i in range(cols)], fontsize=8)
    ax_match.set_yticklabels([f'row {i}' for i in range(rows)], fontsize=8)
    ax_match.set_title('GPU vs NumPy — element match', fontsize=12,
                       fontweight='bold', pad=8)
    ax_match.tick_params(length=0)
    for spine in ax_match.spines.values():
        spine.set_visible(False)

    # ── Architecture info panel ───────────────────────────────
    ax_info.axis('off')
    info_lines = [
        ('GPU Architecture', '#58a6ff', 13),
        ('', 'white', 10),
        (f'  Cores      :  8 shader cores (SIMD)', 'white', 10),
        (f'  Each core  :  ALU + 16×8-bit reg file', 'white', 10),
        (f'  Each core  :  8-bit accumulator', 'white', 10),
        (f'  Batches    :  {(M+1)//2} × 2-row batches', 'white', 10),
        (f'  K terms    :  {K} accumulation steps', 'white', 10),
        ('', 'white', 10),
        ('Data path', '#58a6ff', 12),
        ('', 'white', 10),
        ('  Shared mem → reg-file → ALU', 'white', 10),
        ('  MUL → ACC (per core, parallel)', 'white', 10),
        ('  ACC → shared mem → hex file', 'white', 10),
        ('', 'white', 10),
        (f'  Sim cycles :  {cycles}', '#39d353' if all_match else '#f85149', 11),
        (f'  Result     :  {status_str}', '#39d353' if all_match else '#f85149', 11),
    ]
    y = 0.97
    for text, color, size in info_lines:
        ax_info.text(0.05, y, text, transform=ax_info.transAxes,
                     color=color, fontsize=size,
                     verticalalignment='top',
                     fontfamily='monospace')
        y -= 0.065

    # ── Colour all tick labels white ──────────────────────────
    for ax in [ax_a, ax_b, ax_gpu, ax_ref, ax_match]:
        ax.tick_params(colors='#8b949e')
        ax.title.set_color('white')

    # ── Save & show ───────────────────────────────────────────
    out_png = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        '..', 'RTL', 'matrix_result_heatmap.png')
    out_png = os.path.abspath(out_png)
    plt.savefig(out_png, dpi=120, bbox_inches='tight',
                facecolor=BG, edgecolor='none')
    print(f"\n  Heatmap saved -> {out_png}")
    plt.show()


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    script_dir  = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.join(script_dir, '..')
    rtl_dir     = os.path.abspath(os.path.join(project_dir, 'RTL'))
    demos_dir   = os.path.join(rtl_dir, 'demos')

    print("=" * 56)
    print("  Mini GPU — Interactive Matrix Multiplication")
    print("=" * 56)
    print(f"\nHardware constraints:")
    print(f"  Shared memory : {SHARED_MEM_SIZE} locations (8-bit each)")
    print(f"  Element range : 0 .. {MAX_ELEMENT}  "
          f"(framebuffer is 8-bit; values > {MAX_ELEMENT} cannot be stored)")
    print(f"  Max K         : {MAX_K_SAFE}  "
          f"(prevents accumulator overflow: {MAX_ELEMENT}^2 x K < 255)")
    print(f"  Parallelism   : 8 GPU shader cores (SIMD)")

    # ── Step 1: Choose dimensions ──────────────────────────────
    print("\n" + "─" * 56)
    print("Step 1: Matrix dimensions  (C = A × B,  A is M×K,  B is K×N)")
    print("─" * 56)
    print_valid_combinations()

    while True:
        print("\nEnter dimensions:")
        M = get_dimension("  M (rows of A)  : ", 2, 5)
        K = get_dimension("  K (shared dim) : ", 2, MAX_K_SAFE)
        N = get_dimension("  N (cols of B)  : ", 2, 5)
        valid, reason = validate_dimensions(M, K, N)
        if valid:
            mem = M * K + K * N + M * N
            print(f"\n  ✓  {M}×{K} × {K}×{N}  →  {M}×{N}")
            print(f"     Memory used: {M*K} + {K*N} + {M*N} "
                  f"= {mem} / {SHARED_MEM_SIZE}")
            break
        print(f"\n  ✗  {reason}")

    # ── Step 2: Enter matrix values ────────────────────────────
    print("\n" + "─" * 56)
    print("Step 2: Enter matrix values  (0 .. 7 per element)")
    print("─" * 56)

    A = get_matrix('A', M, K)
    B = get_matrix('B', K, N)

    # ── Step 3: Preview & confirm ──────────────────────────────
    print("\n" + "─" * 56)
    print("Step 3: Preview")
    print("─" * 56)
    print_matrix('A', A)
    print_matrix('B', B)

    C_numpy = compute_numpy_reference(A, B)
    print(f"\n  NumPy reference  C = A × B  ({M}×{N}):")
    for row in C_numpy.tolist():
        vals = "  ".join(f"{v:3d}" for v in row)
        print(f"    [ {vals} ]")

    confirm = input("\nRun GPU simulation? (y/n): ").strip().lower()
    if confirm != 'y':
        print("Cancelled.")
        return

    # ── Step 4: Generate Verilog & simulate ────────────────────
    print("\n" + "─" * 56)
    print("Step 4: Generating Verilog and running simulation")
    print("─" * 56)

    hex_file  = os.path.join(rtl_dir, 'matrix_result.hex')
    demo_path = os.path.join(demos_dir, 'matrix_multiply_demo.sv')

    if os.path.exists(hex_file):
        os.remove(hex_file)
        print("Removed stale matrix_result.hex")

    generate_verilog_demo(M, K, N, A, B, demo_path)

    success = run_simulation(rtl_dir, demo_path)
    if not success:
        print("\nSimulation failed — see errors above.")
        return

    # ── Step 5: Compare results ────────────────────────────────
    print("\n" + "─" * 56)
    print("Step 5: Result comparison")
    print("─" * 56)

    if not os.path.exists(hex_file):
        print(f"ERROR: {hex_file} not found after simulation.")
        return

    gpu_a, gpu_b, C_gpu, C_ref, cycles = parse_result_hex(
        hex_file, M, K, N)

    print_comparison(gpu_a, gpu_b, C_gpu, C_ref, C_numpy, M, K, N, cycles)

    # ── Step 6: Heatmap visualisation ─────────────────────────
    print("\n" + "─" * 56)
    print("Step 6: Heatmap visualisation")
    print("─" * 56)
    try:
        visualize_results(gpu_a, gpu_b, C_gpu, C_numpy,
                          M, K, N, cycles)
    except Exception as exc:
        print(f"  [!] Visualisation error: {exc}")


if __name__ == '__main__':
    main()