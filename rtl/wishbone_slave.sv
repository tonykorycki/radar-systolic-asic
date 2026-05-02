`default_nettype none

import radar_pkg::*;

module wishbone_slave (
    input  logic        clk,
    input  logic        rst,

    // Wishbone B4 slave interface
    input  logic        wb_cyc_i,
    input  logic        wb_stb_i,
    input  logic        wb_we_i,
    input  logic [31:0] wb_adr_i,
    input  logic [31:0] wb_dat_i,
    input  logic [3:0]  wb_sel_i,
    output logic        wb_ack_o,
    output logic [31:0] wb_dat_o,

    // Register outputs to datapath
    output logic [31:0] ctrl,
    output logic [31:0] timeout,
    output logic [31:0] scale,
    output logic signed [BIAS_WIDTH*ARRAY_DIM-1:0]              bias,
    output logic [WEIGHT_WIDTH*ARRAY_DIM*ARRAY_DIM-1:0]         weight_w1,
    output logic [WEIGHT_WIDTH*ARRAY_DIM*NUM_CLASSES-1:0]       weight_w2,
    output logic [COMPLEX_WIDTH*N-1:0]                          sample_data,
    output logic [COMPLEX_WIDTH*N-1:0]                          chirp_data,

    // Status inputs from datapath
    input  logic [31:0] status,
    input  logic signed [WEIGHT_WIDTH*NUM_CLASSES-1:0] result
);

    // TODO: implement Wishbone B4 register file
    // See docs/register_map.md for full register layout and offsets

endmodule

`default_nettype wire
