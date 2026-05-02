"""
Synthetic training data generator.
Generates range profiles for all 8 classes with randomized range,
RCS drawn from per-class distributions, and SNR varied from 5 dB to 40 dB.
Outputs to data/synthetic/.
"""

import numpy as np

CLASSES = [
    "pedestrian", "cyclist", "car", "drone",
    "bird", "corner_reflector", "clutter", "noise"
]
SAMPLES_PER_CLASS = 2000


def generate_class(class_name: str, n_samples: int) -> np.ndarray:
    """
    Generate synthetic range profiles for a single class.

    Returns:
        Array of shape (n_samples, N) — int16 range profiles.
    """
    raise NotImplementedError


def generate_dataset(output_dir: str = "data/synthetic"):
    """Generate all classes and save to output_dir."""
    raise NotImplementedError


if __name__ == "__main__":
    generate_dataset()
