"""
PyTorch QAT training script.
Trains Model A (Linear 64→8) and Model B (Linear 64→16 → ReLU → Linear 16→8)
for the Milestone 0 topology comparison. Exports INT8 weights via export_weights.py.
Results committed to results/m0_layer_decision/.
"""

import numpy as np


def train_model_a(dataset_dir: str, output_dir: str):
    """Train single-layer model: Linear(64→8) with bias."""
    raise NotImplementedError


def train_model_b(dataset_dir: str, output_dir: str):
    """Train two-layer model: Linear(64→16) → ReLU → Linear(16→8) with bias."""
    raise NotImplementedError


def compare_models(results_dir: str):
    """
    Apply the 5% decision rule at low SNR (5–10 dB).
    If Model A low-SNR accuracy is within 5% of Model B, choose one layer.
    Prints decision and writes justification to results_dir.
    """
    raise NotImplementedError


if __name__ == "__main__":
    train_model_a("data/synthetic", "results/m0_layer_decision")
    train_model_b("data/synthetic", "results/m0_layer_decision")
    compare_models("results/m0_layer_decision")
