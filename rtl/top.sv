`default_nettype none

import radar_pkg::*;

module top (
`ifdef USE_POWER_PINS
    inout  vccd1,
    inout  vssd1,
`endif

    // Caravel harness interface
    input  logic        wb_clk_i,
    input  logic        wb_rst_i,
    input  logic        wbs_stb_i,
    input  logic        wbs_cyc_i,
    input  logic        wbs_we_i,
    input  logic [3:0]  wbs_sel_i,
    input  logic [31:0] wbs_dat_i,
    input  logic [31:0] wbs_adr_i,
    output logic        wbs_ack_o,
    output logic [31:0] wbs_dat_o,

    // GPIO
    input  logic [37:0] io_in,
    output logic [37:0] io_out,
    output logic [37:0] io_oeb
);

    // Internal signals
    // TODO: wire all submodule interconnects

    // Submodule instantiations
    // TODO: instantiate radar_input_interface, matched_filter, systolic_array,
    //       activation_unit, wishbone_slave, control_fsm
    // See docs/architecture.md §2.7 for connection map

endmodule

`default_nettype wire
