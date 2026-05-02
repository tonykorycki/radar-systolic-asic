`default_nettype none

import radar_pkg::*;

module systolic_array (
    input  logic                                clk,
    input  logic                                rst,

    // Weight loading
    input  logic [WEIGHT_WIDTH*ARRAY_DIM*ARRAY_DIM-1:0] weight_in,
    input  logic                                load_weights,

    // Tile input (one 16-element slice of the quantized range profile)
    input  logic signed [QUANT_WIDTH*ARRAY_DIM-1:0] x_in,

    // Control
    input  logic                                compute,
    input  logic                                clear,    // assert on tile 0 only
    output logic                                done,

    // INT32 accumulator outputs (after all tile passes)
    output logic signed [ACC_WIDTH*ARRAY_DIM-1:0] y_out
);

    // TODO: implement 16×16 weight-stationary systolic array
    // - 256 PEs, each: one INT8 weight register, one INT32 accumulator
    // - clear resets accumulators only (not weights) — assert on tile 0 only
    // - rst resets everything including stored weights
    // - inputs enter from left edge, partial sums accumulate rightward

endmodule

`default_nettype wire
