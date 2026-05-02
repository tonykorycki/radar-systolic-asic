"""
Precision sweep — Milestone 0 first task.
Runs the fixed-point model at Q8.8, Q12.4, Q16.16 input widths on synthetic
chirps with 40 dB dynamic range. Measures classification accuracy at each
precision. Results committed to results/precision_sweep/.
Justifies the 16-bit input width decision before interfaces.sv is frozen.
"""

import numpy as np


def sweep(input_widths: list = [8, 12, 16], snr_db: float = 40.0):
    """
    Args:
        input_widths: List of total input bit widths to evaluate.
        snr_db:       Signal-to-noise ratio for synthetic chirps.
    """
    raise NotImplementedError


if __name__ == "__main__":
    sweep()
