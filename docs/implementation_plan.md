# Radar Inference Accelerator — Project Plan

**Platform:** SkyWater 130nm via Efabless Caravel MPW shuttle  
**Target submission:** Spring 2027  
**Team structure:** DSP Group · Accelerator Group · Integration Group · Verification & Backend Group

---

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
y = ReLU( W * x_compressed + b )
```

`W` is a quantized INT8 weight matrix. The 16×16 systolic array computes the matrix-vector product — 256 MACs per cycle. The activation unit applies requantization and ReLU. The argmax of the output vector is the predicted target class.

Array dimensions: `ARRAY_DIM = 16` (compile-time parameter, reducible to 8×8 if area is constrained). Number of output classes: 8. The weight matrix is 16×16 INT8 = 2 Kbits total, implemented as a synthesized register file — no SRAM macro required.

### Hardware/software boundary

The boundary is the Wishbone slave register file. Everything on the host side is firmware running on PicoRV32; everything on the user side is RTL.

In Wishbone-preload mode: PicoRV32 loads weights, writes radar samples, asserts start, polls done, reads result. In LVDS streaming mode: the `radar_input_interface` module receives frames directly from the IWR6843 via external line receivers, buffers one chirp, and triggers the FSM automatically — the host only reads the result.

### Interface summary

| Interface | Type | Direction | Purpose |
|---|---|---|---|
| Wishbone slave | Memory-mapped registers | Host ↔ IP | Weight load, sample load, chirp load, control, result read |
| LVDS input (io_in[15:18]) | Digital GPIO | External → IP | Streaming IQ samples from IWR6843 after line receivers |
| Weight register file | Internal registers | FSM → Systolic array | Weight storage and feed |
| Matched filter → systolic | Internal wire bus | Filter → Array | 16-element INT8 compressed feature vector |
| Systolic → activation | Internal wire bus | Array → Activation | INT32 accumulator outputs |
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
| SPI (STM32/PYNQ path) | IN/OUT | io_in/out[23:26] | Optional middleman interface |
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
    ├── LOAD_WEIGHTS ──► weight register file ──────────┐
    │                                                   │
    ├── LOAD_SAMPLES ──► sample buffer                  │
    │         │                                         │
    │         ▼                                         ▼
    └── RUN_FILTER ──► Matched Filter Front End    16×16 Systolic Array
                       (FFT → cmul → IFFT)    ──►  (256 INT8 MACs/cycle)
                                                        │
                                                        ▼
                                             Nonlinear Activation Unit
                                             (requantize + ReLU + clip)
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
| `x_compressed` | OUT | `16*N` | Range profile magnitudes, 16-bit per bin |
| `clk`, `rst` | IN | 1 | |

#### 2.2 16×16 Systolic Array

**Owner:** Accelerator Group  
**File:** `rtl/systolic_array.sv`

Computes `y = W * x_compressed`. 256 processing elements (PEs), each with one INT8 multiplier and one INT32 accumulator.

**Dataflow:** Weight-stationary. Weights are preloaded into PEs once and remain fixed across successive chirps. Input feature vector elements enter from the left edge, one per cycle per row. Partial sums accumulate rightward. Output vector emerges from the right edge after `ARRAY_DIM` cycles. Weight-stationary chosen over output-stationary because the same weights run against many successive chirps — load once, infer many times.

**PE internals:** Each PE holds one INT8 weight register. On each cycle: multiply incoming INT8 activation by stored weight, add to INT32 accumulator, pass activation to the right. Two reset inputs: `rst` resets everything including stored weights; `clear` resets accumulators only and is asserted by the FSM at the start of every `RUN_SYSTOLIC` entry. This allows back-to-back inference without reloading weights.

**Port table:**

| Port | Direction | Width | Description |
|---|---|---|---|
| `weight_in[i][j]` | IN | `8 * ARRAY_DIM^2` | Preloaded INT8 weight matrix |
| `x_in[i]` | IN | `8 * ARRAY_DIM` | INT8 feature vector inputs, one element/cycle |
| `load_weights` | IN | 1 | Weight load enable |
| `compute` | IN | 1 | Begin matrix-vector multiply |
| `clear` | IN | 1 | Reset accumulators only (not weights) |
| `y_out[i]` | OUT | `32 * ARRAY_DIM` | INT32 accumulator outputs per row |
| `done` | OUT | 1 | Output valid |
| `clk`, `rst` | IN | 1 | |

#### 2.3 Nonlinear Activation Unit

**Owner:** Accelerator Group  
**File:** `rtl/activation_unit.sv`

Fully combinational post-processing of INT32 systolic array outputs. Operations in order: (1) requantization — multiply each INT32 accumulator by a Wishbone-configurable Q16.16 scale factor via right shift; (2) ReLU — zero all negative values; (3) INT8 clip — saturate to [-128, 127]. The scale factor is runtime-configurable via Wishbone to support different neural network models post-tapeout without re-spin.

**Port table:**

| Port | Direction | Width | Description |
|---|---|---|---|
| `acc_in[i]` | IN | `32 * ARRAY_DIM` | INT32 accumulators from systolic array |
| `scale` | IN | 32 | Q16.16 requantization scale, Wishbone-writable |
| `y_out[i]` | OUT | `8 * ARRAY_DIM` | INT8 activations |

#### 2.4 Wishbone Slave Interface

**Owner:** Integration Group  
**File:** `rtl/wishbone_slave.sv`

Memory-mapped register file. Standard Wishbone B4 protocol, natively compatible with Caravel harness. Register map is frozen — no TBDs.

| Offset | Name | R/W | Description |
|---|---|---|---|
| 0x00 | `CTRL` | W | Bit 0: start. Bit 1: reset. Bit 2: mode (0=Wishbone, 1=LVDS stream) |
| 0x04 | `STATUS` | R | Bit 0: done. Bit 1: busy. Bit 2: error. Bits [7:4]: error code |
| 0x08 | `TIMEOUT` | W | Watchdog cycle count. FSM enters ERROR if any stage exceeds this |
| 0x0C | `SCALE` | W | Q16.16 requantization scale for activation unit |
| 0x10–0x8F | `WEIGHT_DATA` | W | 128-byte sequential weight write port (16×16 × INT8) |
| 0x90–0xCF | `SAMPLE_DATA` | W | 64-byte radar sample write port (N=64 × 16-bit magnitude) |
| 0xD0–0x14F | `CHIRP_DATA` | W | 128-byte reference chirp write port (N=64 × 16+16 complex) |
| 0x150–0x15F | `RESULT` | R | 8-byte output classification vector (8 × INT8) |

#### 2.5 Control FSM

**Owner:** Integration Group  
**File:** `rtl/control_fsm.sv`

Orchestrates the full pipeline. All transitions are registered. No combinational paths cross state boundaries.

**States:**

```
IDLE → LOAD_WEIGHTS → LOAD_SAMPLES → RUN_FILTER → RUN_SYSTOLIC → ACTIVATE → DONE → IDLE
                                                                                      │
                                          ERROR ◄─── any stage exceeds TIMEOUT count ┘
```

- `IDLE`: waiting for `CTRL.start` (Wishbone mode) or `frame_ready` (LVDS streaming mode).
- `LOAD_WEIGHTS`: streams weight data from Wishbone write buffer into systolic PE registers.
- `LOAD_SAMPLES`: streams radar samples from Wishbone write buffer (Wishbone mode only — in LVDS mode samples are already buffered by `radar_input_interface`).
- `RUN_FILTER`: asserts `matched_filter.start` and `systolic.clear` simultaneously, waits on `matched_filter.done`.
- `RUN_SYSTOLIC`: feeds `x_compressed` into systolic array, asserts `compute`, waits on `systolic.done`.
- `ACTIVATE`: passes accumulator outputs through activation unit (combinational, one-cycle latency).
- `DONE`: writes result to output register, asserts `STATUS.done`. Returns to IDLE on next start.
- `ERROR`: entered if any stage does not assert `done` within `TIMEOUT` cycles. Sets `STATUS.error` and error code. Remains in ERROR until host writes `CTRL.reset`. Asserting `CTRL.start` while FSM is not in IDLE or DONE is silently ignored.

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

## 3. Verification Strategy

### Golden models

Two Python reference implementations in `golden/`. Both must be written and validated before any RTL is written.

**`golden/golden_model_float.py`:** Uses `np.fft.fft` at double precision. Validates algorithm correctness independent of quantization.

**`golden/golden_model_fixed.py`:** Mirrors exact RTL bit widths — 16-bit complex input, 32-bit butterfly accumulation, 16-bit truncation after IFFT, INT8 quantization at systolic array input, INT32 accumulation, Q16.16 requantization. RTL output is checked against this model, not the float model.

**`golden/precision_sweep.py`:** Runs the fixed-point model at Q8.8, Q12.4, Q16.16 input widths on synthetic chirps with 40dB dynamic range. Measures classification accuracy at each precision. Must be run and results committed before Milestone 0 closes — it is the empirical justification for the 16-bit input width decision.

### Neural network training

The INT8 weight matrix must be trained and ready before Milestone 2. This is a parallel workstream starting at Milestone 1, owned by one person on the Verification & Backend group.

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

**Training pipeline:** Two-layer INT8 MLP in PyTorch with quantization-aware training. Architecture: Linear(64→16) → ReLU → Linear(16→8). The 16-neuron hidden layer is a hard constraint matching the systolic array width. Train in float32 first to establish accuracy baseline, then apply QAT. Export INT8 weight matrix in the row/column order the systolic PE grid expects via `golden/export_weights.py`, which outputs a binary file PicoRV32 firmware loads via Wishbone.

**IWR6843 chirp configuration:** 4GHz bandwidth, 40μs ramp time, 128 samples per chirp decimated to 64 for N=64 FFT, 60GHz center frequency. Range resolution: ~3.75cm per bin. Maximum unambiguous range: ~15m at this decimation.

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
- `clear` test: run inference, assert `clear`, run second inference, verify no accumulator contamination from first run.
- Weight persistence: verify weights survive `clear` assertion.

**Activation unit:**
- Sweep INT32 inputs across full range. Verify ReLU, clip, requantization at all boundary values against fixed-point golden model.
- Verify scale factor updates take effect on next inference cycle.

**Wishbone slave:**
- Protocol compliance: `ack` timing, back-to-back transactions, read-after-write.
- Full register map: every register readable/writable at correct offset.
- `STATUS.done` asserted only after full pipeline completion.
- `STATUS.error` asserted on timeout, cleared only by `CTRL.reset`.

**Radar input interface:**
- Frame boundary detection: `frame_ready` asserts exactly once per complete chirp.
- Back-to-back frames: second frame immediately after first consumed by FSM.
- Clock domain crossing: no samples dropped or corrupted across async FIFO at varied clock ratios.
- Mode switching: toggle between LVDS and Wishbone modes between frames.

**Control FSM:**
- Full state transition coverage: every edge reachable.
- Handshake sequencing: correct start/done pairs with each downstream block.
- Timeout: stall matched filter `done`, verify FSM reaches ERROR within TIMEOUT cycles.
- Start-during-run: assert `CTRL.start` mid-pipeline, verify ignored.
- Reset from every state: verify clean return to IDLE.
- LVDS trigger: assert `frame_ready` in LVDS mode, verify FSM starts without `CTRL.start`.

**Top-level integration:**
- Wishbone path: synthetic chirp → `golden_model_fixed.py` expected output → Wishbone-driven RTL → verify match.
- LVDS path: drive `radar_input_interface` with synthetic bit stream, verify same end-to-end result.
- Back-to-back inference: second chirp immediately after DONE, verify accumulator clear works in full pipeline context.
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

## 4. Incremental Build Plan

Gate policy: each milestone must be signed off before the next begins. No module advances to integration without passing its unit testbench against `golden_model_fixed.py`.

### Milestone 0 — Architecture lock (May 2026)

All of the following must be completed before any RTL is written.

Run `golden/precision_sweep.py` at Q8.8, Q12.4, Q16.16 on synthetic chirps with 40dB dynamic range. Confirm 16-bit input provides acceptable classification accuracy. Commit results to `results/precision_sweep/`. This is the first task and blocks everything else.

Freeze all inter-block interfaces in `rtl/interfaces.sv`. No interface changes after this point without full team sign-off.

Freeze the Wishbone register map exactly as specified in Section 2.4. Commit `docs/register_map.md`.

Write and validate both golden models on synthetic chirps.

Begin neural network training workstream (parallel, runs through Milestone 2): generate synthetic dataset from `golden_model_fixed.py`, train float MLP baseline.

Assign module ownership. Configure IWR6843 chirp parameters. Commit `docs/parameter_choices.md` and `docs/pin_assignment.md`.

Deliverables: `rtl/interfaces.sv`, `golden/golden_model_float.py`, `golden/golden_model_fixed.py`, `results/precision_sweep/`, `docs/register_map.md`, `docs/parameter_choices.md`, `docs/pin_assignment.md`.

### Milestone 1 — Module RTL + unit tests (Sep–Nov 2026)

All six modules developed independently. All must pass unit tests before Milestone 2.

- **DSP Group:** `rtl/matched_filter.sv` + `tb/test_matched_filter.py`. Includes Wishbone-writable chirp register file.
- **Accelerator Group:** `rtl/systolic_array.sv` + `rtl/activation_unit.sv` + testbenches. Includes `clear` signal and runtime scale factor register.
- **Integration Group:** `rtl/wishbone_slave.sv` + `rtl/control_fsm.sv` + `rtl/radar_input_interface.sv` + testbenches. FSM includes timeout watchdog and ERROR state. LVDS mode select in CTRL register.
- **Verification & Backend:** Verilator + Cocotb Makefiles, unit test execution and reporting, neural network QAT training and weight export.

Deliverables: all six RTL files passing unit testbenches. Results in `results/unit/`. Trained INT8 weights in `golden/weights_int8.bin`.

### Milestone 2 — Top-level integration (Dec 2026)

Wire all blocks in `rtl/top.sv`. Write `tb/test_top.py` covering both Wishbone and LVDS paths, back-to-back inference, timeout recovery, minimum 50 test vectors. No RTL changes to individual modules without re-running their unit tests.

Deliverables: `rtl/top.sv` passing end-to-end testbench. Results in `results/integration/`.

### Milestone 2.5 — FPGA prototype (Dec 2026–Jan 2027)

Run the RTL on real radar data before committing to synthesis. This milestone gates Milestone 3 — synthesis does not start until the FPGA prototype produces correct outputs on real IWR6843 captures.

Port RTL to PYNQ-Z2: replace Wishbone with AXI4-Lite, synthesize in Vivado 2025.1, deploy as PYNQ overlay. All other RTL is identical to the tapeout version.

Connect IWR6843ISK via DCA1000EVM → 1 Gbps Ethernet (USB-C to Ethernet adapter on laptop/PYNQ) → PYNQ ARM → AXI writes into fabric. Python script on PYNQ ARM receives UDP frames from DCA1000EVM, formats them, writes to FPGA fabric. No line receivers needed for this path.

Validation: place corner reflector at 3m, 5m, 10m. Verify FPGA pipeline classifies correctly. Supplement with human subject captures for pedestrian class. Commit results to `results/fpga_prototype/`.

Use this milestone to collect Phase 2 real training data. Retrain with combined synthetic + real dataset. Export updated weights to `golden/weights_int8_v2.bin`.

Deliverables: PYNQ-Z2 overlay passing real radar data validation. Updated weights. Capture dataset in `data/real_captures/`.

### Milestone 3 — Synthesis + timing closure (Jan 2027)

Run OpenLane synthesis targeting `sky130_fd_sc_hd`. Target 25 MHz. Review critical path — expected bottleneck is INT8 multiplier in systolic PE. If timing fails at 25 MHz, pipeline the PE multiplier. Formal equivalence check gate-level netlist vs RTL.

Also during this milestone: complete carrier PCB KiCad schematic and layout. Submit Gerbers to JLCPCB by end of January (4-layer controlled impedance stackup, ~2 week turnaround).

Deliverables: gate-level netlist meeting timing. Reports in `results/synth/`. KiCad files in `hardware/carrier_pcb/`.

### Milestone 4 — Physical design (Feb 2027)

Floorplan: `radar_input_interface` in north region (close to io_in[15:18]), systolic array as regular grid in center, matched filter and FSM surrounding, weight register file at east edge. Power ring + mesh. OpenROAD global → detail placement. CTS: single clock domain, balanced tree to all 256 PE flip-flops and FFT pipeline registers. OpenROAD global → detailed routing. Target DRC-clean first pass.

Carrier PCB arrives from fab this month. Bring up power rails, verify 1.8V and 3.3V before populating ICs.

Deliverables: routed DEF + GDS in `results/pnr/`. Carrier PCB power rails verified.

### Milestone 5 — Sign-off (Mar 2027)

DRC: Magic + KLayout, zero violations. LVS: Netgen, clean. STA: OpenSTA setup and hold at 25 MHz, worst-case slow and best-case fast corners. Re-run functional simulation on gate-level netlist with back-annotated parasitics if STA reveals unexpected paths.

Deliverables: clean reports in `results/signoff/`.

### Milestone 6 — Tapeout submission (Apr–May 2027)

Integrate hardened block into Efabless Caravel harness. Run Efabless precheck tool. Resolve precheck failures. GDSII export and final KiCad visual inspection. Submit to Sky130 MPW shuttle.

Fallback: if Sky130 shuttle timing slips, same flow targets GlobalFoundries 180nm via IHP. RTL is PDK-agnostic.

Deliverables: GDSII committed to repo, Efabless submission confirmed.

---

## 5. External Hardware and Carrier PCB

### IWR6843ISK eval board

The IWR6843ISK is the radar front end. It provides 60–64 GHz FMCW radar with integrated antennas, analog front end, ADC, and onboard DSP. For this project the onboard DSP is bypassed — raw ADC samples are extracted via the LVDS debug interface. The IWR powers and configures itself over its own USB-C connection, separate from the carrier PCB.

The IWR6843 LVDS output uses 4 differential pairs at 1125–1275 mV common-mode voltage with 250–450 mV differential swing. Sky130 GPIO inputs cannot receive LVDS directly — both the P and N lines sit above Sky130's ~0.9V input trip point so a single-ended input always sees logic high. The fix is 4× SN65LVDS1 line receiver ICs on the carrier PCB, one per differential pair, converting each to a clean 1.8V single-ended signal. 100Ω termination resistors sit at the line receiver inputs on the PCB.

For the FPGA prototype phase, the DCA1000EVM board receives the IWR LVDS output and streams raw IQ frames over 1 Gbps Ethernet UDP. No line receivers are needed for this path.

### Carrier PCB

The carrier PCB mounts the chip (WLCSP 3.2mm × 5.3mm, 0.5mm bump pitch), line receivers, power regulation, and connectors. Design in KiCad, fabricate at JLCPCB on 4-layer controlled impedance stackup.

Critical design requirements:
- WLCSP footprint from Caravel package drawing. Requires 4 mil trace/space minimum.
- LVDS differential pair traces: length-matched within 5mm, 100Ω differential impedance (~0.15mm trace/space on standard FR4). Termination resistors at line receiver inputs.
- Single USB-C connector: VBUS 5V → LDO regulators → 3.3V + 1.8V for chip and line receivers; D+/D- → CP2102 USB-UART → io_in/out[5:6] for laptop serial console. One cable handles both power and communication.
- IWR6843 eval board connects via signal header (LVDS lines only — IWR powers from its own USB).
- Bidirectional level shifter (TXS0104 or equivalent, 1.8V ↔ 3.3V) on SPI lines for PYNQ-Z2 Pmod and STM32 GPIO headers.
- SWD header for PicoRV32 firmware flashing.

Full component choices and layout notes in `docs/carrier_pcb_notes.md`.

### Connection paths

**FPGA prototype validation:**
```
IWR6843ISK (USB-C → laptop, mmWave Studio config)
    → DCA1000EVM → Ethernet (USB-C adapter) → PYNQ-Z2 ARM
    → Python formats frame → AXI write to FPGA fabric
    → FPGA runs RTL → result to ARM → display
```

**Data collection:**
```
IWR6843ISK → DCA1000EVM → Ethernet → laptop
    → Python: UDP receive → label → save to data/real_captures/
```

**Final silicon demo:**
```
IWR6843ISK → LVDS → SN65LVDS1×4 on carrier PCB → io_in[15:18]
    → chip runs pipeline autonomously
    → PicoRV32 reads result → UART → USB-C → laptop terminal
```

---

## 6. Repository Structure

```
radar-accelerator/
├── rtl/
│   ├── interfaces.sv                  # frozen at M0
│   ├── matched_filter.sv
│   ├── systolic_array.sv
│   ├── activation_unit.sv
│   ├── wishbone_slave.sv
│   ├── control_fsm.sv
│   ├── radar_input_interface.sv
│   └── top.sv
├── tb/
│   ├── test_matched_filter.py
│   ├── test_systolic.py
│   ├── test_activation.py
│   ├── test_wishbone.py
│   ├── test_fsm.py
│   ├── test_radar_input.py
│   └── test_top.py
├── golden/
│   ├── golden_model_float.py
│   ├── golden_model_fixed.py
│   ├── precision_sweep.py
│   ├── generate_dataset.py
│   ├── train.py
│   ├── export_weights.py
│   ├── weights_int8.bin               # synthetic-data trained weights
│   └── weights_int8_v2.bin            # retrained after real captures
├── data/
│   ├── synthetic/
│   └── real_captures/
├── fpga_prototype/
│   ├── vivado/
│   └── notebooks/
├── hardware/
│   └── carrier_pcb/                   # KiCad schematic + layout
├── firmware/
│   └── picorv32/
├── openlane/
│   └── config.json
├── results/
│   ├── precision_sweep/
│   ├── unit/
│   ├── integration/
│   ├── fpga_prototype/
│   ├── synth/
│   ├── pnr/
│   └── signoff/
└── docs/
    ├── register_map.md                # frozen at M0
    ├── parameter_choices.md           # frozen at M0
    ├── pin_assignment.md              # frozen at M0
    └── carrier_pcb_notes.md
```