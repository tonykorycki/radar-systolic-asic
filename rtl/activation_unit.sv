`default_nettype none

import radar_pkg::*;

// Fully combinational. No clock or reset.
// Operations applied in order: bias addition → requantization → ReLU → INT8 clip.
module activation_unit (
    input  logic signed [ACC_WIDTH*ARRAY_DIM-1:0]   acc_in,
    input  logic signed [BIAS_WIDTH*ARRAY_DIM-1:0]  bias_in,
    input  logic        [SCALE_WIDTH-1:0]            scale,    // Q16.16

    output logic signed [WEIGHT_WIDTH*ARRAY_DIM-1:0] y_out    // INT8 output
);

    // TODO: implement bias addition, Q16.16 requantization, ReLU, INT8 clip
    // - sign-extend INT16 bias to INT32 before adding to INT32 accumulator
    // - multiply by scale (Q16.16) via arithmetic right shift
    // - ReLU: zero all negative values
    // - clip to [-128, 127]

endmodule

`default_nettype wire
