`default_nettype none

import radar_pkg::*;

module control_fsm (
    input  logic clk,
    input  logic rst,

    // Host control
    input  logic [31:0] ctrl,
    input  logic [31:0] timeout,
    output logic [31:0] status,

    // Mode
    input  logic        frame_ready,   // from radar_input_interface (LVDS mode)

    // Matched filter handshake
    output logic        mf_start,
    input  logic        mf_done,

    // Systolic array control
    output logic        sa_load_weights,
    output logic        sa_compute,
    output logic        sa_clear,
    input  logic        sa_done,
    output logic [1:0]  tile_idx,

    // Activation unit strobe
    output logic        act_en,

    // Weight mux select (W1 vs W2 for two-layer)
    output logic        weight_sel
);

    // TODO: implement FSM with states:
    // IDLE → LOAD_WEIGHTS → LOAD_SAMPLES → RUN_FILTER → RUN_SYSTOLIC → ACTIVATE → DONE
    // See docs/architecture.md §2.5 for full state descriptions and transition rules.
    // Key invariants:
    //   - clear asserted on tile_idx == 0 only
    //   - weights_valid skips LOAD_WEIGHTS (W1 only)
    //   - LVDS mode skips LOAD_SAMPLES
    //   - timeout watchdog → ERROR state

endmodule

`default_nettype wire
