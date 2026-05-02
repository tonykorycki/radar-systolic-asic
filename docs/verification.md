# Verification Strategy

### Golden models

Two Python reference implementations in `golden/`. Both must be written and validated before any RTL is written.

**`golden/golden_model_float.py`:** Uses `np.fft.fft` at double precision. Validates algorithm correctness independent of quantization.

**`golden/golden_model_fixed.py`:** Mirrors exact RTL bit widths — 16-bit complex input, 32-bit butterfly accumulation, 16-bit truncation after IFFT, INT8 quantization (8 MSBs of each 16-bit bin) at systolic array input, INT32 accumulation with four-pass tiling, INT16 bias addition, Q16.16 requantization. RTL output is checked against this model, not the float model.

**`golden/precision_sweep.py`:** Runs the fixed-point model at Q8.8, Q12.4, Q16.16 input widths on synthetic chirps with 40dB dynamic range. Measures classification accuracy at each precision. Must be run and results committed before Milestone 0 closes — it is the empirical justification for the 16-bit input width decision.

### Neural network topology decision (Milestone 0)

The choice between a one-layer and two-layer network is locked at Milestone 0 by empirical test. This decision gates `interfaces.sv` and the final Wishbone register map. No RTL may be written until it is resolved.

**Procedure:**

1. Implement two golden model configurations in `golden/train.py`:
   - **Model A:** `Linear(64→8)` with bias — 520 parameters, outputs 8 classes directly.
   - **Model B:** `Linear(64→16) → ReLU → Linear(16→8)` with bias at each layer — 1168 parameters.

2. Train both in float32 on the full synthetic dataset (16,000 samples, 8 classes). Establish float32 accuracy baseline for each.

3. Apply quantization-aware training (QAT) to both. Export INT8 weights.

4. Evaluate classification accuracy **separately** at:
   - High SNR: 30–40 dB test set
   - Low SNR: 5–10 dB test set

   Low-SNR accuracy is the primary comparison metric. A model that looks equivalent on average can have a substantial gap at low SNR, which is the operationally important case.

5. **Decision rule:** If Model A low-SNR accuracy is within 5% of Model B, choose one layer. If the gap exceeds 5%, choose two layers.

6. Commit results to `results/m0_layer_decision/` with both training logs, accuracy tables by SNR band, and a short written justification for the decision.

**If two-layer is chosen:**
- Both weight matrices `W1` (256 bytes) and `W2` (128 bytes) live in the Wishbone register file simultaneously.
- The FSM holds a layer counter and runs the tiling loop twice: four passes with W1, one pass with W2.
- `BIAS[0:15]` holds Layer 1 bias; `BIAS[16:23]` holds Layer 2 bias.
- `golden_model_fixed.py` must implement the full two-pass inference including both bias additions.

### Neural network training

The INT8 weight matrix (or matrices) must be trained and ready before Milestone 2. This is a parallel workstream starting at Milestone 1, owned by one person on the Verification & Backend group.

**Target classes (8):** pedestrian, cyclist, car, drone, bird, corner reflector, clutter, noise.

**Training data — synthetic phase (starts at Milestone 0):**

Generate range profiles from `golden_model_fixed.py`. Each sample is a 64-element INT8 range profile. Per-class parameters:

| Class | RCS range | Range window | Notes |
|---|---|---|---|
| Pedestrian | 0.5–2 dBsm | 1–30m | Low RCS, narrow peak |
| Cyclist | 2–5 dBsm | 1–30m | Medium RCS |
| Car | 10–20 dBsm | 5–50m | High RCS, wide peak |
| Drone | 3–8 dBsm | 1–50m | Medium RCS, variable |
| Bird | -5–2 dBsm | 1–20m | Low RCS, similar to pedestrian |
| Corner reflector | 25–35 dBsm | 1–50m | Very high RCS, calibration target |
| Clutter | — | — | Multiple low-RCS returns at varied ranges |
| Noise | — | — | No target, noise floor only |

Generate 2000 samples per class (16000 total) with randomized range, RCS drawn from per-class distribution, and SNR varied from 5dB to 40dB.

**Training data — real capture phase (starts at Milestone 2.5):**

Capture IQ frames from IWR6843ISK using DCA1000EVM + mmWave Studio. Place a corner reflector at known distances (3m, 5m, 10m, 15m, 20m) for calibration. Use human subjects for pedestrian and cyclist classes. Label captures and merge with synthetic dataset.

**Training pipeline:** PyTorch with quantization-aware training. Train the topology chosen at M0. Train in float32 first to establish accuracy baseline, then apply QAT. Export INT8 weight matrix (or matrices) in the row/column order the systolic PE grid expects via `golden/export_weights.py`, which outputs binary files PicoRV32 firmware loads via Wishbone.

**IWR6843 chirp configuration:** 4GHz bandwidth, 40μs ramp time, 128 samples per chirp decimated to 64 for N=64 FFT, 60GHz center frequency. Range resolution: ~3.75cm per bin. Maximum unambiguous range: ~15m at this decimation.

### Simulating the LVDS path without hardware

All LVDS tests run entirely in Verilator simulation using a Python bit serializer. No IWR6843, DCA1000EVM, or line receivers are needed until Milestone 2.5. The `radar_input_interface` unit test and the top-level LVDS integration test both use this approach.

**How it works:** A helper function in the testbench takes an array of N=64 complex IQ samples and serializes them into LVDS-style signals following the IWR6843 LVDS streaming protocol:
- Two serial data lanes (`lvds_data[0]`, `lvds_data[1]`) carry interleaved I/Q bits
- `lvds_bclk` is driven as a square wave at a chosen bit rate, independent of the chip clock — use a prime-ratio frequency to stress the async FIFO CDC
- `lvds_fclk` toggles to mark frame boundaries (one frame = N=64 complex samples)

The serializer must be written against the IWR6843 LVDS output protocol documented in the TI mmWave SDK (see External References in `docs/AGENTS.md`). The person writing the `radar_input_interface` RTL and the person writing the testbench serializer must read the same spec section before starting.

**Wishbone / LVDS cross-check:** In the top-level integration test, drive the same 64-sample test vector both ways — write it directly to `SAMPLE_DATA` via Wishbone and serialize the same samples through the LVDS path. Both must produce identical output relative to `golden_model_fixed.py`. A mismatch isolates a bug in the deserializer or async FIFO.

**Async FIFO stress test:** Run the bit serializer at several clock ratios relative to the chip clock (e.g., 0.9×, 1.1×, 1.5×, 2.3×). Verify no samples are dropped or corrupted across all ratios. CDC bugs that would only appear with real hardware are caught here.

### Testbench framework

Cocotb + Verilator throughout. All testbench stimulus and checking in Python. Each module has a standalone Cocotb testbench with its own `Makefile`. The golden model and RTL checking live in the same Python file — no re-implementation of signal processing in SystemVerilog.

### Per-module test plan

**Matched filter:**
- FFT butterfly against `np.fft.fft` on random complex vectors. Check magnitude and phase within fixed-point quantization error.
- Complex multiply stage on known chirp pairs with preloaded reference.
- Full filter against `golden_model_fixed.py`. Verify peak position matches expected range bin.
- Corner cases: all-zero input, single-tone input, maximum-magnitude input (overflow check), chirp register write then read-back.

**Systolic array:**
- Single PE: known INT8 multiply + accumulate. Verify accumulator overflow behavior.
- Full array on identity matrix (output equals input).
- Full array on random INT8 weight matrix and feature vector against `np.matmul`.
- **Tiling accumulation test:** run four sequential tile passes on a known 64-element input with known weights. Verify the final INT32 accumulators match the full `np.matmul(W, x)` result. This is the primary correctness test for the tiling logic.
- **clear-on-tile-0 test:** assert `clear` only on tile 0 of a four-pass sequence. Verify partial sums accumulate correctly on passes 1–3. Then run a second inference (clear on tile 0 again) and verify no contamination from the first run.
- **clear must not fire mid-sequence:** run a four-pass sequence with `clear` mistakenly asserted on tile 2. Verify the output is wrong (use this as a negative test to confirm the FSM behavior matters).
- Weight persistence: verify stored weights survive `clear` assertion across back-to-back inferences.

**Activation unit:**
- Sweep INT32 inputs across full range. Verify ReLU, clip, requantization, and bias addition at all boundary values against fixed-point golden model.
- **Bias test:** apply non-zero INT16 bias values. Verify biased output matches `golden_model_fixed.py` with the same bias.
- Verify zero bias produces same output as the pre-bias implementation (regression).
- Verify scale factor updates take effect on the next inference cycle.
- Two-layer case: verify that writing Layer 2 bias values to `BIAS[16:23]` and re-running activation produces correct Layer 2 output.

**Wishbone slave:**
- Protocol compliance: `ack` timing, back-to-back transactions, read-after-write.
- Full register map: every register readable/writable at correct offset and size. Confirm sizes match register map (WEIGHT_W1=256B, SAMPLE_DATA=256B, CHIRP_DATA=256B).
- `STATUS.done` asserted only after full pipeline completion.
- `STATUS.error` asserted on timeout, cleared only by `CTRL.reset`.
- `STATUS.weights_valid` asserted after LOAD_WEIGHTS completes. Cleared by `CTRL.reset` or `CTRL.clear_weights_valid`.
- `CTRL.clear_weights_valid`: verify setting this bit clears weights_valid and causes the next inference to go through LOAD_WEIGHTS.

**Radar input interface:**
- Frame boundary detection: `frame_ready` asserts exactly once per complete chirp.
- Back-to-back frames: second frame immediately after first consumed by FSM.
- Clock domain crossing: no samples dropped or corrupted across async FIFO at varied clock ratios.
- Mode switching: toggle between LVDS and Wishbone modes between frames.

**Control FSM:**
- Full state transition coverage: every edge reachable including all conditional branches.
- **LVDS mode LOAD_SAMPLES bypass:** assert `frame_ready` in LVDS mode, verify FSM transitions LOAD_WEIGHTS → RUN_FILTER without entering LOAD_SAMPLES.
- **weights_valid skip:** run one complete inference to set weights_valid, then trigger a second inference. Verify the second run skips LOAD_WEIGHTS and goes directly to LOAD_SAMPLES (WB mode) or RUN_FILTER (LVDS mode).
- **Tile counter sequencing:** verify FSM issues exactly four RUN_SYSTOLIC passes per inference. Verify `clear` asserted on pass 0 only.
- **Two-layer sequencing (if applicable):** verify FSM runs tile loop twice with correct W1/W2 weight loads between passes.
- Handshake sequencing: correct start/done pairs with each downstream block.
- Timeout: stall matched filter `done`, verify FSM reaches ERROR within TIMEOUT cycles.
- Start-during-run: assert `CTRL.start` mid-pipeline, verify ignored.
- Reset from every state: verify clean return to IDLE.

**Top-level integration:**
- Wishbone path: synthetic chirp → `golden_model_fixed.py` expected output → Wishbone-driven RTL → verify match.
- LVDS path: drive `radar_input_interface` with synthetic bit stream, verify same end-to-end result.
- Back-to-back inference: second chirp immediately after DONE. Verify accumulator clear fires correctly on tile 0 of the new inference, and weights_valid flag skips LOAD_WEIGHTS.
- **Tiling end-to-end:** verify that the four-tile sequence produces the same result as a direct matmul in `golden_model_fixed.py` for at least 20 distinct test vectors.
- Timeout recovery: stall a stage mid-inference, verify ERROR, write CTRL.reset, verify clean restart.
- Minimum 50 distinct test vectors with varied target ranges and weight matrices.

### Sign-off criteria

| Check | Tool | Pass condition |
|---|---|---|
| Functional correctness | Cocotb + Verilator | All test vectors match `golden_model_fixed.py` within quantization tolerance |
| DRC | Magic + KLayout | Zero violations |
| LVS | Netgen | Clean |
| STA setup | OpenSTA | Met at 25 MHz, worst-case slow corner |
| STA hold | OpenSTA | Met at 25 MHz, best-case fast corner |

Target clock is **25 MHz**. 50 MHz is a stretch goal. The INT8 multiplier chain in the systolic PE is the expected critical path on Sky130 HD cells. If synthesis closes at 50 MHz without changes, update the target. If it does not, pipeline the PE multiplier (adds one latency cycle per accumulation step, functionally correct).

---
