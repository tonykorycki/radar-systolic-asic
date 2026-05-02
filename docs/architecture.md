# Architecture and IP Definition

## 1. IP Definition

### What the chip does

This chip is a complete radar signal processing pipeline on a single Sky130 die. Raw complex IQ radar samples enter, get pulse-compressed by a matched filter front end into a feature vector, and feed directly into a 16×16 systolic array running quantized INT8 neural network inference. The output is a discrete target classification produced in real time with no off-chip compute.

The chip complements the IWR6843 radar front end rather than competing with it. The IWR6843's onboard DSP runs purely classical signal processing — range FFT, Doppler FFT, CFAR, beamforming — with no neural inference capability. This chip replaces the hand-engineered CFAR and heuristic classifier at the end of that pipeline with a learned neural network running on custom silicon. No existing open-source tapeout combines a matched filter front end with a systolic array inference engine on one die.

An on-chip RISC-V host (PicoRV32), provided by the Efabless Caravel harness, orchestrates the pipeline over a Wishbone bus. No external processor is required for inference.

### The two-stage computation

**Stage 1 — Matched filter (pulse compression)**

```
x_compressed = IFFT( FFT(received_signal) .* conj(FFT(reference_chirp)) )
```

The received radar return is transformed to the frequency domain. Each bin is multiplied pointwise against the conjugate of a stored reference chirp spectrum. The result is transformed back via IFFT producing a range-compressed profile whose peak position encodes target range. This compressed profile is the feature vector for Stage 2.

FFT size: `N = 64` (compile-time parameter, reducible to 32 if area is constrained). Fixed-point arithmetic throughout: 16-bit real + 16-bit imaginary input samples, 32-bit internal butterfly accumulation (required to cover 6 stages of bit growth for N=64), truncated back to 16-bit after IFFT. The 32-bit accumulation width is non-negotiable — radar signals have ~40dB dynamic range between strong and weak targets in the same range profile and 8-bit accumulation overflows.

**Stage 2 — Neural network inference**

```
y = ReLU( W * x + b )
```

`W` is a quantized INT8 weight matrix. `b` is a per-output INT16 bias vector, Wishbone-writable. The 16×16 systolic array computes the matrix-vector product through four sequential tiling passes (see Section 2.2). The activation unit adds bias, applies requantization, and applies ReLU. The argmax of the output vector is the predicted target class.

**Neural network topology — locked at Milestone 0.** Two candidate architectures are evaluated empirically before any RTL is written:

- **Model A — Single layer:** `Linear(64→8)` with bias, 520 parameters. Eight output classes directly. The array runs four tile passes per inference.
- **Model B — Two layers:** `Linear(64→16) → ReLU → Linear(16→8)` with bias at each layer, 1168 parameters. The array runs four tile passes for Layer 1 (64→16), then one pass for Layer 2 (16→8). The FSM reloads W2 between layers.

Decision rule: train both in float32, apply QAT, compare classification accuracy at both 40 dB and 5–10 dB SNR on the synthetic dataset. If Model A is within 5% of Model B at low SNR, choose one layer and keep the hardware simpler. If Model B is meaningfully better at low SNR, choose two layers — the second pass reuses the same array with W2 loaded from the register file. Both weight matrices live in the Wishbone register file simultaneously. The decision is locked before `interfaces.sv` is frozen. See `docs/verification.md` for the full test procedure.

Array dimensions: `ARRAY_DIM = 16` (compile-time parameter, reducible to 8×8 if area is constrained). Number of output classes: 8. Weight matrices are synthesized register files — no SRAM macro required.

### Hardware/software boundary

The boundary is the Wishbone slave register file. Everything on the host side is firmware running on PicoRV32; everything on the user side is RTL.

In Wishbone-preload mode: PicoRV32 loads weights, writes radar samples, asserts start, polls done, reads result. In LVDS streaming mode: the `radar_input_interface` module receives frames directly from the IWR6843 via external line receivers, buffers one chirp, and triggers the FSM automatically — the host only reads the result.

Once weights are loaded, `STATUS.weights_valid` is set. Subsequent inferences skip weight loading entirely until the host asserts `CTRL.clear_weights_valid` or resets the chip. This makes back-to-back inference with the same model efficient.

### Interface summary

| Interface | Type | Direction | Purpose |
|---|---|---|---|
| Wishbone slave | Memory-mapped registers | Host ↔ IP | Weight load, sample load, chirp load, control, result read |
| LVDS input (io_in[15:18]) | Digital GPIO | External → IP | Streaming IQ samples from IWR6843 after line receivers |
| Weight register file | Internal registers | FSM → Systolic array | Weight storage and feed |
| Matched filter → systolic | Internal wire bus | Filter → Array | 64 × INT8 quantized range profile (quantized from 16-bit at input boundary) |
| Systolic → activation | Internal wire bus | Array → Activation | INT32 accumulator outputs after all tile passes |
| Activation → output reg | Internal wire bus | Activation → Wishbone | INT8 result vector |

### Pin assignment

| Function | Direction | Pin | Notes |
|---|---|---|---|
| LVDS data lane 0 | IN | io_in[15] | North edge. After SN65LVDS1 line receiver |
| LVDS data lane 1 | IN | io_in[16] | North edge. After SN65LVDS1 line receiver |
| LVDS bit clock | IN | io_in[17] | North edge. After SN65LVDS1 line receiver |
| LVDS frame clock | IN | io_in[18] | North edge. After SN65LVDS1 line receiver |
| UART TX | OUT | io_out[6] | Caravel management UART |
| UART RX | IN | io_in[5] | Caravel management UART |
| SPI (PYNQ-Z2 debug path) | IN/OUT | io_in/out[23:26] | Optional host interface via PYNQ-Z2 Pmod |
| Debug status | OUT | io_out[19:22] | Bringup visibility |

Pins io_in[15:18] are all on the North die edge per the Caravel pin order config — 4 consecutive pads, minimal internal routing to the `radar_input_interface` module placed in the northern floorplan region.

---

## 2. Architecture

### Block diagram (dataflow)

```
IWR6843 eval board
    │  LVDS (4 diff pairs) → SN65LVDS1×4 on carrier PCB
    │
    ▼
io_in[15:18]
    │
    ▼
radar_input_interface
    │  deserialize + buffer one chirp (N=64 complex samples)
    │  assert frame_ready to FSM
    │
    ▼
Control FSM
    │
    ├── LOAD_WEIGHTS ──► weight register file ──────────────────┐
    │   (skipped if weights_valid)                              │
    │                                                           │
    ├── LOAD_SAMPLES (Wishbone mode only; skipped in LVDS mode) │
    │         │                                                 │
    │         ▼                                                 ▼
    └── RUN_FILTER ──► Matched Filter Front End           16×16 Systolic Array
                       (FFT → cmul → IFFT)                (4 tiling passes)
                       outputs 64 × 16-bit          ──►   quantize 16→8 INT8 at input
                                                          clear asserted on tile 0 only
                                                                │
                                                                ▼
                                                     Nonlinear Activation Unit
                                                     (bias + requantize + ReLU + clip)
                                                     [two-layer: FSM reloads W2, loops]
                                                                │
                                                                ▼
                                                         Output register
                                                                │
                                                                ▼
                                            PicoRV32 reads result via Wishbone
                                            → UART → laptop
```

### Module descriptions

#### 2.1 Matched Filter Front End

**Owner:** DSP Group  
**File:** `rtl/matched_filter.sv`

Implements FFT → pointwise complex multiply → IFFT in fixed-point hardware. Produces a range-compressed profile from raw IQ input samples.

**Sub-stages:**

Forward FFT: decimation-in-time Cooley-Tukey butterfly, N=64 points, complex fixed-point input (16-bit real + 16-bit imaginary), 32-bit internal accumulation. Butterfly hardware is shared with the IFFT stage via a direction control bit (twiddle factor conjugation) — both stages cannot run simultaneously so sharing is clean and saves area.

Complex multiply stage: N parallel complex multipliers (4 real multiplies + 2 adds each, one per frequency bin). Reference chirp spectrum stored in a Wishbone-writable register file — runtime reconfigurability lets you test different waveforms on real silicon without re-spin.

Inverse FFT: same butterfly hardware, direction-reversed. Output truncated from 32-bit accumulation back to 16-bit before feeding the systolic array.

**Port table:**

| Port | Direction | Width | Description |
|---|---|---|---|
| `samples_in` | IN | `2*16*N` | Complex IQ radar samples, packed 16+16 per sample |
| `chirp_reg[N]` | IN | `2*16*N` | Reference chirp spectrum from Wishbone register file |
| `start` | IN | 1 | Begin matched filter computation |
| `done` | OUT | 1 | Compressed output valid |
| `x_compressed` | OUT | `16*N` | Range profile, 16-bit per bin (64 bins total) |
| `clk`, `rst` | IN | 1 | |

#### 2.2 16×16 Systolic Array

**Owner:** Accelerator Group  
**File:** `rtl/systolic_array.sv`

Computes one tile of `y += W * x_tile`. The full matrix-vector product over a 64-element input is built up across four sequential passes driven by the control FSM. 256 processing elements (PEs), each with one INT8 multiplier and one INT32 accumulator.

**Tiling for 64-element input:**

The matched filter outputs 64 × 16-bit range bins. Before entering the array, each 16-bit value is quantized to INT8 by extracting the 8 most significant bits. The resulting 64 INT8 values are split into four groups of 16. The FSM runs four RUN_SYSTOLIC passes with a 2-bit tile counter `t`:

| Pass | tile counter | `clear` asserted? | Input slice |
|---|---|---|---|
| 0 | t=0 | **Yes** — resets accumulators for this inference | x_compressed[0:15] |
| 1 | t=1 | No — partial sums must survive | x_compressed[16:31] |
| 2 | t=2 | No | x_compressed[32:47] |
| 3 | t=3 | No | x_compressed[48:63] |

After pass 3 the INT32 accumulators hold the complete result and the FSM transitions to ACTIVATE. **Never assert `clear` on passes 1–3** — doing so zeros accumulated partial sums from earlier passes and produces a wrong result.

If two-layer is chosen at M0: after ACTIVATE (Layer 1), the FSM loads W2 from the Wishbone register file into the PE registers (overwriting W1), resets the tile counter to 0, and runs one pass (tile=0, `clear` asserted) for the 16-element Layer 2 computation.

**One-layer output row mapping (Model A):** For `Linear(64→8)`, only 8 output classes are needed from a 16-row array. Rows 0–7 map to output classes 0–7. Rows 8–15 must be loaded with zero weights and their accumulator outputs are ignored — not written to RESULT. The activation unit passes `y_out[0:7]` to the output register; `y_out[8:15]` is unused.

**Dataflow:** Weight-stationary. Weights are preloaded into PEs once and remain fixed across successive chirps. Input feature vector elements enter from the left edge, one per cycle per row. Partial sums accumulate rightward. Output vector emerges from the right edge after `ARRAY_DIM` cycles.

**PE internals:** Each PE holds one INT8 weight register. On each cycle: multiply incoming INT8 activation by stored weight, add to INT32 accumulator, pass activation to the right. Two separate reset inputs:
- `rst` — resets everything including stored weights (full reset)
- `clear` — resets accumulators only, weights survive. Used between inferences and at the start of tile 0.

**Port table:**

| Port | Direction | Width | Description |
|---|---|---|---|
| `weight_in[i][j]` | IN | `8 * ARRAY_DIM^2` | Preloaded INT8 weight matrix |
| `x_in[i]` | IN | `8 * ARRAY_DIM` | INT8 inputs for current tile, one element/cycle per row |
| `load_weights` | IN | 1 | Weight load enable |
| `compute` | IN | 1 | Begin matrix-vector multiply for this tile |
| `clear` | IN | 1 | Reset accumulators only (not weights). Assert on tile 0 only. |
| `y_out[i]` | OUT | `32 * ARRAY_DIM` | INT32 accumulator outputs per row |
| `done` | OUT | 1 | Current tile complete |
| `clk`, `rst` | IN | 1 | |

#### 2.3 Nonlinear Activation Unit

**Owner:** Accelerator Group  
**File:** `rtl/activation_unit.sv`

Fully combinational post-processing of the INT32 systolic array outputs after all tiling passes complete. Operations applied in order:

1. **Bias addition** — sign-extend each INT16 bias value to INT32 and add to the corresponding accumulator.
2. **Requantization** — multiply each biased INT32 value by the Wishbone-configurable Q16.16 scale factor via arithmetic right shift.
3. **ReLU** — zero all negative values.
4. **INT8 clip** — saturate to [−128, 127].

Both the bias vector and the scale factor are runtime-configurable via Wishbone registers to support different neural network models post-tapeout without re-spin. For two-layer inference the host writes Layer 2 bias values to `BIAS[16:23]` before the second activation pass.

**Port table:**

| Port | Direction | Width | Description |
|---|---|---|---|
| `acc_in[i]` | IN | `32 * ARRAY_DIM` | INT32 accumulators from systolic array (after all tiles) |
| `bias_in[i]` | IN | `16 * ARRAY_DIM` | INT16 per-output bias, sign-extended to INT32 before addition |
| `scale` | IN | 32 | Q16.16 requantization scale, Wishbone-writable |
| `y_out[i]` | OUT | `8 * ARRAY_DIM` | INT8 activations |

#### 2.4 Wishbone Slave Interface

**Owner:** Integration Group  
**File:** `rtl/wishbone_slave.sv`

Memory-mapped register file. Standard Wishbone B4 protocol, natively compatible with Caravel harness. The layout below is the target register map; it is finalized at Milestone 0 once the one-layer vs two-layer decision is locked (the `WEIGHT_W2` region is reserved pending that decision).

**Register map (target — finalized at M0):**

| Offset | Name | R/W | Description |
|---|---|---|---|
| 0x00 | `CTRL` | W | Bit 0: start. Bit 1: reset. Bit 2: mode (0=Wishbone, 1=LVDS). Bit 3: clear_weights_valid |
| 0x04 | `STATUS` | R | Bit 0: done. Bit 1: busy. Bit 2: error. Bit 3: weights_valid. Bits [7:4]: error code |
| 0x08 | `TIMEOUT` | W | Watchdog cycle count. FSM enters ERROR if any stage exceeds this |
| 0x0C | `SCALE` | W | Q16.16 requantization scale for activation unit |
| 0x10–0x4F | `BIAS` | W | 64 bytes — 32 × INT16 bias values. Entries 0–15: Layer 1 bias. Entries 16–23: Layer 2 bias (two-layer config only; unused entries ignored in one-layer config) |
| 0x50–0x14F | `WEIGHT_W1` | W | 256 bytes — Layer 1 INT8 weight matrix (16×16, all 256 bytes required) |
| 0x150–0x1CF | `WEIGHT_W2` | W | 128 bytes — Layer 2 INT8 weight matrix (16×8 = 128 bytes). Reserved/unused if one-layer decision at M0 |
| 0x1D0–0x2CF | `SAMPLE_DATA` | W | 256 bytes — N=64 × 32-bit complex IQ samples (16-bit real + 16-bit imaginary), fed into the matched filter |
| 0x2D0–0x3CF | `CHIRP_DATA` | W | 256 bytes — N=64 × 32-bit complex reference chirp (16+16 per sample) |
| 0x3D0–0x3D7 | `RESULT` | R | 8 bytes — 8 × INT8 output classification vector |

#### 2.5 Control FSM

**Owner:** Integration Group  
**File:** `rtl/control_fsm.sv`

Orchestrates the full pipeline. All transitions are registered. No combinational paths cross state boundaries.

**Primary state sequence:**

```
                    ┌── (if weights_valid: skip LOAD_WEIGHTS) ──────────────────┐
                    │                                                            │
IDLE → LOAD_WEIGHTS → LOAD_SAMPLES → RUN_FILTER → RUN_SYSTOLIC (tile 0–3) → ACTIVATE → DONE → IDLE
                    │              │                │                         │
                    │              └─(LVDS mode:   └──(clear on tile 0 only) └─(two-layer:
                    │                skip to         increment tile counter,    load W2, reset
                    └──(LVDS mode:   RUN_FILTER)     loop back for tiles 1–3)  tile counter,
                       skip to                                                  re-enter
                       RUN_FILTER)                                              RUN_SYSTOLIC)
                                        │
                 ERROR ◄── any stage exceeds TIMEOUT ─────────────────────────┘
```

**weights_valid shortcut:** If `STATUS.weights_valid` is already set when inference is triggered, `LOAD_WEIGHTS` is skipped:
- Wishbone mode: IDLE → LOAD_SAMPLES → RUN_FILTER
- LVDS mode: IDLE → RUN_FILTER

**State descriptions:**

- `IDLE`: waiting for `CTRL.start` (Wishbone mode) or `frame_ready` (LVDS streaming mode).

- `LOAD_WEIGHTS`: streams weight data from the Wishbone write buffer into systolic PE registers. On completion, sets `STATUS.weights_valid`. Skipped entirely if `weights_valid` is already set. For two-layer config, loads W1 first; the second weight load (W2) happens after Layer 1 ACTIVATE.

- `LOAD_SAMPLES`: streams radar samples from the Wishbone write buffer into the sample buffer. **Wishbone mode only.** In LVDS mode this state is skipped — the FSM transitions directly LOAD_WEIGHTS → RUN_FILTER because samples are already buffered by `radar_input_interface`.

- `RUN_FILTER`: asserts `matched_filter.start`. Waits on `matched_filter.done`.

- `RUN_SYSTOLIC` (tiling loop): The FSM holds a 2-bit tile counter `t`. On each entry:
  - If t=0: assert `clear`, then assert `compute` with input slice x_compressed[0:15]. After `systolic.done`, increment t.
  - If t=1..3: do **not** assert `clear`. Assert `compute` with x_compressed[t*16 : t*16+15]. After `systolic.done`, increment t.
  - After t=3 completes, transition to ACTIVATE.
  - For two-layer config: after ACTIVATE (Layer 1), the FSM re-enters LOAD_WEIGHTS (for W2, if not already loaded), resets t=0, and re-enters RUN_SYSTOLIC for a single pass (Layer 2 has 16 inputs, so only one pass with t=0 needed).

- `ACTIVATE`: passes the INT32 accumulator outputs through the combinational activation unit (bias → requantize → ReLU → clip). One-cycle latency.

- `DONE`: writes result to output register, asserts `STATUS.done`. Returns to IDLE on next start. In two-layer mode, automatically clears `STATUS.weights_valid` on entry to DONE — the PEs hold W2 at this point, not W1, so the next inference must reload W1.

- `ERROR`: entered if any stage does not assert `done` within `TIMEOUT` cycles. Sets `STATUS.error` and error code. Remains in ERROR until host writes `CTRL.reset`. Asserting `CTRL.start` while the FSM is not in IDLE or DONE is silently ignored.

**Reset strategy:** Caravel provides clock and synchronous reset from the harness. All user area registers reset synchronously on the Caravel-provided reset. The FSM reset path must be verified in simulation — do not assume async reset behavior.

#### 2.6 Radar Input Interface

**Owner:** Integration Group  
**File:** `rtl/radar_input_interface.sv`

Receives raw IQ frames from the IWR6843 via the LVDS interface after external SN65LVDS1 line receivers on the carrier PCB. Deserializes the bit stream, buffers one complete chirp (N=64 complex samples), asserts `frame_ready` to the control FSM.

The IWR6843 LVDS configuration: 2 data lanes, 1 bit clock lane, 1 frame clock lane. After line receivers these arrive as 4 single-ended 1.8V signals on `io_in[15:18]`. The bit clock is a separate domain from the chip's internal clock — an async FIFO sits at this boundary.

Mode select: `CTRL[2]` = 0 selects Wishbone preload; `CTRL[2]` = 1 selects LVDS streaming. The Wishbone preload path is always available as fallback.

**Port table:**

| Port | Direction | Width | Description |
|---|---|---|---|
| `lvds_data[1:0]` | IN | 2 | Single-ended data lanes after line receiver |
| `lvds_bclk` | IN | 1 | Bit clock, async domain |
| `lvds_fclk` | IN | 1 | Frame clock, async domain |
| `mode` | IN | 1 | 0=idle, 1=streaming active |
| `frame_ready` | OUT | 1 | One complete chirp buffered, asserted to FSM |
| `samples_out` | OUT | `2*16*N` | Buffered complex IQ samples to matched filter |
| `clk`, `rst` | IN | 1 | Internal clock domain |

---
