# Parameter Choices

**Status:** Frozen at Milestone 0. Do not modify without full team sign-off.

This document records the values chosen for all compile-time parameters and the justification for each. Parameters are defined in `rtl/interfaces.sv` and referenced across all RTL modules and testbenches.

---

## Parameter table

| Parameter | Value | Justification |
|---|---|---|
| `N` | 64 | FFT size. Matches IWR6843 chirp decimation (128 ADC samples → 64 after 2× decimation). Range resolution ~3.75 cm/bin at 4 GHz bandwidth. Maximum unambiguous range ~15m. Reducible to 32 if area is constrained — decision at M0. |
| `ARRAY_DIM` | 16 | Systolic array rows and columns. Chosen to tile the 64-element range profile in exactly 4 passes (64 / 16 = 4). Also matches Layer 1 output width for two-layer config (64→16). Reducible to 8 if area is constrained — decision at M0. |
| `DATA_WIDTH` | 16 | Bits per real or imaginary component of a complex input sample. 16-bit provides sufficient dynamic range (~96 dB theoretical) for radar returns with ~40 dB target RCS variation. Justified empirically by `golden/precision_sweep.py` at M0. |
| `ACC_WIDTH` | 32 | Internal FFT butterfly accumulator width. Required to cover 6 stages of bit growth for N=64 (log2(64) = 6 stages, each potentially adding 1 bit). 8-bit accumulation overflows — non-negotiable. Truncated back to 16-bit after IFFT. |
| `WEIGHT_WIDTH` | 8 | Systolic array weight precision (INT8). Standard quantization target for inference accelerators. Chosen to keep weight storage under SRAM macro threshold (256 B for W1, 128 B for W2 — synthesized register file is sufficient). |
| `BIAS_WIDTH` | 16 | Per-output bias precision (INT16). Sign-extended to INT32 before addition with INT32 accumulator. 16-bit provides sufficient range for biases after QAT. |
| `ACC_OUT_WIDTH` | 32 | Systolic array output accumulator width (INT32). Required to accumulate 16 products of INT8 × INT8 across 4 tile passes (16 × 4 = 64 multiply-accumulate operations per output). |
| `NUM_CLASSES` | 8 | Output classification classes: pedestrian, cyclist, car, drone, bird, corner reflector, clutter, noise. Fixed by the target application. |
| `SCALE_WIDTH` | 32 | Requantization scale factor width. Q16.16 fixed-point format — 16 integer bits, 16 fractional bits. Runtime-configurable via Wishbone `SCALE` register. |

---

## Clock target

| Target | Value | Notes |
|---|---|---|
| Official | 25 MHz (40 ns period) | Designed to this target. All STA sign-off at 25 MHz. |
| Stretch goal | 50 MHz | If synthesis closes without changes, update target. Do not design to 50 MHz as the primary target. |

Expected critical path: INT8 multiplier chain in the systolic PE on sky130_fd_sc_hd standard cells. If synthesis fails at 25 MHz, pipeline the PE multiplier (adds one latency cycle per accumulation step, functionally correct).

---

## IWR6843 chirp configuration

| Parameter | Value |
|---|---|
| Center frequency | 60 GHz |
| Bandwidth | 4 GHz |
| Ramp time | 40 μs |
| ADC samples per chirp | 128 |
| Decimation | 2× → 64 samples (matches N) |
| Range resolution | ~3.75 cm/bin |
| Maximum unambiguous range | ~15 m |

---

## Tiling

The 64-element range profile is processed in four sequential passes through the 16×16 array. Each pass feeds one 16-element slice of the quantized range profile. The FSM holds a 2-bit tile counter. `clear` is asserted only on tile 0 — asserting it on tiles 1–3 zeros partial sums and produces a wrong result.

For the two-layer config, Layer 2 (16→8) requires only one pass (16 inputs fit in one 16-wide array column).
