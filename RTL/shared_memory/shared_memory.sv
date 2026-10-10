`timescale 1ns/1ps

// ============================================================
// Shared Memory — Structural Implementation
// 64 locations × 8-bit
//
// Write: One write port per cycle (bank conflict model)
//   - 8 cores submit requests with their own addr/data
//   - Priority encoder selects winning core (lowest ID)
//   - 6-to-64 decoder enables exactly one register_8bit
//   - Documented limitation: one write per cycle
//     One write per cycle.
//     Multiple simultaneous write requests are detected as a conflict.
//     Lowest-numbered requesting core wins.
//
// Read: 8 simultaneous read ports
//   - Each core has a dedicated 64-to-1 mux
//   - All 8 reads happen in same cycle combinationally
//
// Built from:
//   register_8bit    → storage (DFF based)
//   mux_64to1_8bit   → read ports
//   priority_encoder_8 → write arbitration
// ============================================================

module shared_memory(
    input  wire       clk,
    input  wire       reset,

    // Write interface — per-core address and data
    input  wire [7:0] write_en_bus,
    input  wire [5:0] write_addr_bus [0:7],
    input  wire [7:0] write_data_bus [0:7],

    // Read interface — 8 simultaneous combinational reads
    input  wire [5:0] read_addr [0:7],
    output wire [7:0] read_data [0:7],

    // Status outputs
    output wire       write_conflict,
    output wire [2:0] write_winner
);

    // ── Priority encoder selects winning write request ─────────
    wire       any_write;
    wire [2:0] winner_id;

    priority_encoder_8 arbiter(
        .req(write_en_bus),
        .grant(winner_id),
        .valid(any_write),
        .conflict(write_conflict)
    );

    assign write_winner = winner_id;

    // ── Select winner's address and data ──────────────────────
    // 8-to-1 mux on address and data using winner_id
    // Built using cascaded mux logic

    wire [5:0] sel_addr;
    wire [7:0] sel_data;

    // Address mux: select from 8 cores based on winner_id
    // Using generate with behavioral select for clarity
    // (winner_id comes from structural priority encoder)
    assign sel_addr = (winner_id == 3'd0) ? write_addr_bus[0] :
                      (winner_id == 3'd1) ? write_addr_bus[1] :
                      (winner_id == 3'd2) ? write_addr_bus[2] :
                      (winner_id == 3'd3) ? write_addr_bus[3] :
                      (winner_id == 3'd4) ? write_addr_bus[4] :
                      (winner_id == 3'd5) ? write_addr_bus[5] :
                      (winner_id == 3'd6) ? write_addr_bus[6] :
                                            write_addr_bus[7];

    assign sel_data = (winner_id == 3'd0) ? write_data_bus[0] :
                      (winner_id == 3'd1) ? write_data_bus[1] :
                      (winner_id == 3'd2) ? write_data_bus[2] :
                      (winner_id == 3'd3) ? write_data_bus[3] :
                      (winner_id == 3'd4) ? write_data_bus[4] :
                      (winner_id == 3'd5) ? write_data_bus[5] :
                      (winner_id == 3'd6) ? write_data_bus[6] :
                                            write_data_bus[7];

    // ── 6-to-64 write decoder ─────────────────────────────────
    // Produces one-hot enable for selected register
    wire [63:0] reg_enable;

    genvar i;
    generate
        for (i = 0; i < 64; i = i + 1) begin : decoder
            assign reg_enable[i] = any_write &
                                   (sel_addr == i[5:0]);
        end
    endgenerate

    // ── 64 × register_8bit storage ────────────────────────────
    wire [7:0] mem_out [0:63];

    generate
        for (i = 0; i < 64; i = i + 1) begin : storage
            register_8bit reg_i(
                .clk(clk),
                .reset(reset),
                .enable(reg_enable[i]),
                .d(sel_data),
                .q(mem_out[i])
            );
        end
    endgenerate

    // ── 8 read ports via 64-to-1 muxes ───────────────────────
    // All 8 read simultaneously and combinationally
    generate
        for (i = 0; i < 8; i = i + 1) begin : read_ports
            mux_64to1_8bit read_mux(
                .in(mem_out),
                .sel(read_addr[i]),
                .out(read_data[i])
            );
        end
    endgenerate

endmodule