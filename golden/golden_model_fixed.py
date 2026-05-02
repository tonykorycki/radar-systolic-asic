"""
Fixed-point reference model mirroring exact RTL bit widths.
All RTL output checking uses this model — not the float model.

Bit widths implemented:
  - 16-bit complex input samples (16 real + 16 imaginary)
  - 32-bit internal FFT butterfly accumulation
  - 16-bit truncation after IFFT
  - INT8 quantization (8 MSBs of each 16-bit bin) at systolic array input
  - INT32 accumulation with four-pass tiling
  - INT16 bias addition (sign-extended to INT32 before addition)
  - Q16.16 requantization scale factor
"""

import numpy as np

N           = 64
ARRAY_DIM   = 16
DATA_WIDTH  = 16
ACC_WIDTH   = 32
WEIGHT_WIDTH = 8
BIAS_WIDTH  = 16
NUM_CLASSES = 8


def run_matched_filter(samples: np.ndarray, chirp: np.ndarray) -> np.ndarray:
    """
    Fixed-point matched filter: FFT → complex multiply → IFFT.
    Implements 32-bit butterfly accumulation and 16-bit truncation after IFFT.

    Args:
        samples: Complex int16 array of shape (N,).
        chirp:   Complex int16 array of shape (N,).

    Returns:
        x_compressed: int16 array of shape (N,) — range-compressed profile.
    """
    raise NotImplementedError


def quantize_to_int8(x_compressed: np.ndarray) -> np.ndarray:
    """
    Quantize 16-bit range profile to INT8 by extracting the 8 MSBs of each bin.

    Args:
        x_compressed: int16 array of shape (N,).

    Returns:
        x_int8: int8 array of shape (N,).
    """
    raise NotImplementedError


def run_systolic_tiling(x_int8: np.ndarray, weights: np.ndarray) -> np.ndarray:
    """
    Four-pass tiling through the 16×16 systolic array.
    clear is asserted on tile 0 only. Accumulates INT32 partial sums.

    Args:
        x_int8:  int8 array of shape (N,) — quantized range profile.
        weights: int8 array of shape (ARRAY_DIM, N) — weight matrix.

    Returns:
        acc: int32 array of shape (ARRAY_DIM,) — final accumulator values.
    """
    raise NotImplementedError


def run_activation(acc: np.ndarray, bias: np.ndarray, scale: int) -> np.ndarray:
    """
    Activation unit: bias addition → requantization → ReLU → INT8 clip.

    Args:
        acc:   int32 array of shape (ARRAY_DIM,).
        bias:  int16 array of shape (ARRAY_DIM,).
        scale: int32 Q16.16 scale factor.

    Returns:
        y_out: int8 array of shape (ARRAY_DIM,).
    """
    raise NotImplementedError


def run_inference(x_compressed: np.ndarray, weights: list, biases: list, scale: int) -> np.ndarray:
    """
    Full fixed-point inference pipeline from range profile to class scores.

    Args:
        x_compressed: int16 array of shape (N,).
        weights: List of int8 weight matrices. One or two entries.
        biases:  List of int16 bias vectors matching weights.
        scale:   Q16.16 requantization scale factor (int32).

    Returns:
        scores: int8 array of shape (NUM_CLASSES,).
    """
    raise NotImplementedError
