`timescale 1ns/1ps

// ============================================================
// 8-input Priority Encoder
// Structural implementation using gates
//
// Inputs:  req[7:0] — request from each core
// Outputs: grant[2:0] — ID of winning core
//          valid      — at least one request active
//          conflict   — more than one request active
//
// Priority: req[0] highest, req[7] lowest
//
// Logic:
//   grant[0] = req1 & ~req0
//            | req3 & ~req2 & ~req1 & ~req0
//            | req5 & ~req4 & ~req3 & ~req2 & ~req1 & ~req0
//            | req7 & ~req6 & ~req5 & ~req4 & ~req3 & ~req2
//                  & ~req1 & ~req0
//
// Built from AND OR NOT gates using our existing gate modules
// ============================================================

module priority_encoder_8(
    input  wire [7:0] req,
    output wire [2:0] grant,
    output wire       valid,
    output wire       conflict
);

    // ── Intermediate suppress signals ─────────────────────────
    // suppress[i] = 1 if any req[j] with j<i is active
    // Used to mask lower priority requests

    wire s1, s2, s3, s4, s5, s6, s7;

    // s1 = req[0]
    assign s1 = req[0];

    // s2 = req[0] | req[1]
    wire s2_or;
    or_gate or_s2(.a(req[0]), .b(req[1]), .y(s2));

    // s3 = req[0] | req[1] | req[2]
    wire s3a;
    or_gate or_s3a(.a(req[0]),  .b(req[1]), .y(s3a));
    or_gate or_s3 (.a(s3a),     .b(req[2]), .y(s3));

    // s4 = req[0..3]
    wire s4a, s4b;
    or_gate or_s4a(.a(req[0]), .b(req[1]), .y(s4a));
    or_gate or_s4b(.a(req[2]), .b(req[3]), .y(s4b));
    or_gate or_s4 (.a(s4a),   .b(s4b),    .y(s4));

    // s5 = req[0..4]
    wire s5a;
    or_gate or_s5a(.a(s4),    .b(req[4]), .y(s5));

    // s6 = req[0..5]
    or_gate or_s6 (.a(s5),    .b(req[5]), .y(s6));

    // s7 = req[0..6]
    or_gate or_s7 (.a(s6),    .b(req[6]), .y(s7));

    // ── Grant logic ───────────────────────────────────────────
    // grant[i] = 1 for the highest-priority active request
    // Implemented as one-hot then encoded to binary

    wire g0, g1, g2, g3, g4, g5, g6, g7;
    wire ns1, ns2, ns3, ns4, ns5, ns6, ns7;

    not_gate n1(.a(s1), .y(ns1));
    not_gate n2(.a(s2), .y(ns2));
    not_gate n3(.a(s3), .y(ns3));
    not_gate n4(.a(s4), .y(ns4));
    not_gate n5(.a(s5), .y(ns5));
    not_gate n6(.a(s6), .y(ns6));
    not_gate n7(.a(s7), .y(ns7));

    // g0 = req[0]
    assign g0 = req[0];

    // g1 = req[1] & ~req[0]
    and_gate ag1(.a(req[1]), .b(ns1), .y(g1));

    // g2 = req[2] & ~s2
    and_gate ag2(.a(req[2]), .b(ns2), .y(g2));

    // g3 = req[3] & ~s3
    and_gate ag3(.a(req[3]), .b(ns3), .y(g3));

    // g4 = req[4] & ~s4
    and_gate ag4(.a(req[4]), .b(ns4), .y(g4));

    // g5 = req[5] & ~s5
    and_gate ag5(.a(req[5]), .b(ns5), .y(g5));

    // g6 = req[6] & ~s6
    and_gate ag6(.a(req[6]), .b(ns6), .y(g6));

    // g7 = req[7] & ~s7
    and_gate ag7(.a(req[7]), .b(ns7), .y(g7));

    // ── Encode one-hot to binary ──────────────────────────────
    // grant[0] = g1 | g3 | g5 | g7  (odd IDs)
    // grant[1] = g2 | g3 | g6 | g7  (IDs 2,3,6,7)
    // grant[2] = g4 | g5 | g6 | g7  (IDs 4,5,6,7)

    wire enc0a, enc0b;
    wire enc1a, enc1b;
    wire enc2a, enc2b;

    or_gate enc_0a(.a(g1),    .b(g3),    .y(enc0a));
    or_gate enc_0b(.a(g5),    .b(g7),    .y(enc0b));
    or_gate enc_g0(.a(enc0a), .b(enc0b), .y(grant[0]));

    or_gate enc_1a(.a(g2),    .b(g3),    .y(enc1a));
    or_gate enc_1b(.a(g6),    .b(g7),    .y(enc1b));
    or_gate enc_g1(.a(enc1a), .b(enc1b), .y(grant[1]));

    or_gate enc_2a(.a(g4),    .b(g5),    .y(enc2a));
    or_gate enc_2b(.a(g6),    .b(g7),    .y(enc2b));
    or_gate enc_g2(.a(enc2a), .b(enc2b), .y(grant[2]));

    // ── Valid: any request active ─────────────────────────────
    wire va, vb, vc, vd;
    or_gate v_ab(.a(req[0]), .b(req[1]), .y(va));
    or_gate v_cd(.a(req[2]), .b(req[3]), .y(vb));
    or_gate v_ef(.a(req[4]), .b(req[5]), .y(vc));
    or_gate v_gh(.a(req[6]), .b(req[7]), .y(vd));
    wire vab, vcd;
    or_gate v_abc(.a(va),  .b(vb),  .y(vab));
    or_gate v_cde(.a(vc),  .b(vd),  .y(vcd));
    or_gate v_all(.a(vab), .b(vcd), .y(valid));

    // ── Conflict: more than one request ──────────────────────
    // conflict = valid AND NOT(exactly one request)
    // exactly one = g0|g1|g2|g3|g4|g5|g6|g7 with only one high
    // Simpler: conflict = any pair both active

    wire ca, cb, cc, cd, ce, cf, cg;
    wire ch, ci, cj, ck, cl, cm, cn;
    wire co, cp, cq, cr, cs, ct, cu;
    wire cv, cw, cx;

    // All 28 pairs
    and_gate c01(.a(req[0]),.b(req[1]),.y(ca));
    and_gate c02(.a(req[0]),.b(req[2]),.y(cb));
    and_gate c03(.a(req[0]),.b(req[3]),.y(cc));
    and_gate c04(.a(req[0]),.b(req[4]),.y(cd));
    and_gate c05(.a(req[0]),.b(req[5]),.y(ce));
    and_gate c06(.a(req[0]),.b(req[6]),.y(cf));
    and_gate c07(.a(req[0]),.b(req[7]),.y(cg));
    and_gate c12(.a(req[1]),.b(req[2]),.y(ch));
    and_gate c13(.a(req[1]),.b(req[3]),.y(ci));
    and_gate c14(.a(req[1]),.b(req[4]),.y(cj));
    and_gate c15(.a(req[1]),.b(req[5]),.y(ck));
    and_gate c16(.a(req[1]),.b(req[6]),.y(cl));
    and_gate c17(.a(req[1]),.b(req[7]),.y(cm));
    and_gate c23(.a(req[2]),.b(req[3]),.y(cn));
    and_gate c24(.a(req[2]),.b(req[4]),.y(co));
    and_gate c25(.a(req[2]),.b(req[5]),.y(cp));
    and_gate c26(.a(req[2]),.b(req[6]),.y(cq));
    and_gate c27(.a(req[2]),.b(req[7]),.y(cr));
    and_gate c34(.a(req[3]),.b(req[4]),.y(cs));
    and_gate c35(.a(req[3]),.b(req[5]),.y(ct));
    and_gate c36(.a(req[3]),.b(req[6]),.y(cu));
    and_gate c37(.a(req[3]),.b(req[7]),.y(cv));
    and_gate c45(.a(req[4]),.b(req[5]),.y(cw));
    and_gate c46(.a(req[4]),.b(req[6]),.y(cx));

    wire cy, cz, czz;
    and_gate c47(.a(req[4]),.b(req[7]),.y(cy));

    wire d56, d57, d67;
    and_gate c56(.a(req[5]),.b(req[6]),.y(d56));
    and_gate c57(.a(req[5]),.b(req[7]),.y(d57));
    and_gate c67(.a(req[6]),.b(req[7]),.y(d67));

    // OR all pairs together
    wire conf_a, conf_b, conf_c, conf_d;
    wire conf_e, conf_f, conf_g;

    or_gate oc1(.a(ca),   .b(cb),   .y(conf_a));
    or_gate oc2(.a(cc),   .b(cd),   .y(conf_b));
    or_gate oc3(.a(ce),   .b(cf),   .y(conf_c));
    or_gate oc4(.a(cg),   .b(ch),   .y(conf_d));
    or_gate oc5(.a(ci),   .b(cj),   .y(conf_e));
    or_gate oc6(.a(ck),   .b(cl),   .y(conf_f));
    or_gate oc7(.a(cm),   .b(cn),   .y(conf_g));

    wire conf_h, conf_i, conf_j, conf_k;
    or_gate oc8 (.a(conf_a), .b(conf_b), .y(conf_h));
    or_gate oc9 (.a(conf_c), .b(conf_d), .y(conf_i));
    or_gate oc10(.a(conf_e), .b(conf_f), .y(conf_j));
    or_gate oc11(.a(conf_g), .b(co),     .y(conf_k));

    wire conf_l, conf_m, conf_n;
    or_gate oc12(.a(conf_h), .b(conf_i), .y(conf_l));
    or_gate oc13(.a(conf_j), .b(conf_k), .y(conf_m));

    wire conf_o, conf_p, conf_q;
    or_gate oc14(.a(cp),    .b(cq),     .y(conf_n));
    or_gate oc15(.a(cr),    .b(cs),     .y(conf_o));
    or_gate oc16(.a(ct),    .b(cu),     .y(conf_p));
    or_gate oc17(.a(cv),    .b(cw),     .y(conf_q));

    wire conf_r, conf_s;
    or_gate oc18(.a(conf_n), .b(conf_o), .y(conf_r));
    or_gate oc19(.a(conf_p), .b(conf_q), .y(conf_s));

    wire conf_t, conf_u;
    or_gate oc20(.a(cx),    .b(cy),     .y(conf_t));
    or_gate oc21(.a(d56),   .b(d57),    .y(conf_u));

    wire conf_v, conf_w;
    or_gate oc22(.a(conf_t), .b(conf_u), .y(conf_v));
    or_gate oc23(.a(d67),    .b(conf_v), .y(conf_w));

    wire conf_x, conf_y;
    or_gate oc24(.a(conf_l), .b(conf_m), .y(conf_x));
    or_gate oc25(.a(conf_r), .b(conf_s), .y(conf_y));

    wire conf_z;
    or_gate oc26(.a(conf_x), .b(conf_y), .y(conf_z));
    or_gate oc27(.a(conf_z), .b(conf_w), .y(conflict));

endmodule