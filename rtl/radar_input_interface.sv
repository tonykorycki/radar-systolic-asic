`default_nettype none

import radar_pkg::*;

module radar_input_interface (
    // Internal clock domain
    input  logic                        clk,
    input  logic                        rst,

    // LVDS input (async domain — from SN65LVDS1 line receivers on carrier PCB)
    input  logic [1:0]                  lvds_data,   // data lanes 0 and 1
    input  logic                        lvds_bclk,   // bit clock, async
    input  logic                        lvds_fclk,   // frame clock, async

    // Mode select (from CTRL register)
    input  logic                        mode,        // 0=idle, 1=streaming active

    // Output to matched filter
    output logic                        frame_ready,
    output logic [COMPLEX_WIDTH*N-1:0]  samples_out
);

    // TODO: implement LVDS deserializer + async FIFO CDC + chirp buffer
    // - deserialize IWR6843 LVDS protocol (2 data lanes, bit clock, frame clock)
    // - async FIFO at lvds_bclk → clk boundary
    // - buffer one complete chirp (N=64 complex samples)
    // - assert frame_ready to FSM when chirp is complete

endmodule

`default_nettype wire
