"""
Export INT8 weights in the row/column order the systolic array PE grid expects.
Writes binary files that PicoRV32 firmware loads via Wishbone WEIGHT registers.
Row index = output neuron, column index = input feature (row-major).
"""

import numpy as np


def export_one_layer(model, output_path: str = "golden/weights_int8.bin"):
    """Export weights for single-layer model (16×16 → 256 bytes)."""
    raise NotImplementedError


def export_two_layer(model, w1_path: str = "golden/weights_int8_w1.bin",
                     w2_path: str = "golden/weights_int8_w2.bin"):
    """
    Export weights for two-layer model.
    W1: 16×16 = 256 bytes. W2: 16×8 = 128 bytes.
    """
    raise NotImplementedError
