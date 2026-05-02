`default_nettype none

import radar_pkg::*;

module matched_filter (
    input  logic                          clk,
    input  logic                          rst,

    // Radar input samples and reference chirp
    input  logic [COMPLEX_WIDTH*N-1:0]    samples_in,
    input  logic [COMPLEX_WIDTH*N-1:0]    chirp_reg,

    // Control
    input  logic                          start,
    output logic                          done,

    // Range-compressed output (16-bit per bin)
    output logic [DATA_WIDTH*N-1:0]       x_compressed
);

    // TODO: implement FFT → complex multiply → IFFT pipeline
    // - Decimation-in-time Cooley-Tukey butterfly, N=64 points
    // - 32-bit internal accumulation (ACC_WIDTH), truncate to DATA_WIDTH after IFFT
    // - Butterfly hardware shared between forward and inverse FFT (direction control bit)

endmodule

`default_nettype wire
