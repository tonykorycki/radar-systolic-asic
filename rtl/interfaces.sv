// Shared parameters for the radar inference accelerator.
// All RTL modules import this package. Do not hardcode widths or dimensions
// in module files — reference these parameters exclusively.
// Frozen at Milestone 0. Changes require full team sign-off.

package radar_pkg;

  // FFT and input dimensions
  parameter int N           = 64;   // FFT size / number of range bins
  parameter int DATA_WIDTH  = 16;   // Bits per I or Q component of a complex sample

  // Systolic array
  parameter int ARRAY_DIM   = 16;   // Array rows and columns (square)
  parameter int WEIGHT_WIDTH = 8;   // INT8 weights
  parameter int ACC_WIDTH   = 32;   // INT32 accumulators (output of systolic array)

  // Activation unit
  parameter int BIAS_WIDTH  = 16;   // INT16 per-output bias
  parameter int SCALE_WIDTH = 32;   // Q16.16 requantization scale factor

  // Output
  parameter int NUM_CLASSES = 8;    // Classification output classes

  // Derived: complex sample packed width (I + Q)
  parameter int COMPLEX_WIDTH = 2 * DATA_WIDTH;

  // Derived: quantized input to systolic array (8 MSBs of each 16-bit bin)
  parameter int QUANT_WIDTH  = 8;   // INT8 — extracted from DATA_WIDTH MSBs

endpackage
