"""
Double-precision floating-point reference model.
Validates algorithm correctness independent of quantization.
Use this to confirm the matched filter and inference pipeline are
mathematically correct before introducing fixed-point effects.
"""

import numpy as np


def run_matched_filter(samples: np.ndarray, chirp: np.ndarray) -> np.ndarray:
    """
    Pulse-compress a complex IQ frame against a reference chirp.

    Args:
        samples: Complex array of shape (N,) — received radar return.
        chirp:   Complex array of shape (N,) — reference chirp.

    Returns:
        x_compressed: Real-valued range profile of shape (N,), float64.
    """
    raise NotImplementedError


def run_inference(x_compressed: np.ndarray, weights: list, biases: list) -> np.ndarray:
    """
    Run neural network inference on a range-compressed profile.

    Args:
        x_compressed: Range profile of shape (N,).
        weights: List of weight matrices. One entry (one-layer) or two entries (two-layer).
        biases:  List of bias vectors matching weights.

    Returns:
        scores: Output class scores of shape (NUM_CLASSES,), float64.
    """
    raise NotImplementedError
