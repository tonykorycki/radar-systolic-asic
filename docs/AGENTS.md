# Agent Context — Radar Inference Accelerator

This file gives an AI assistant (or a new contributor) the context needed to be immediately useful on this project. Read it before helping with any task. Do not suggest alternatives to decisions marked **[FROZEN]** — those are finalized and not up for debate.

---

## What this project is

A custom silicon tapeout on SkyWater 130nm via Efabless Caravel MPW shuttle, targeting Spring 2027. The chip takes raw complex IQ radar samples, runs a matched filter front end (FFT → complex multiply → IFFT) to produce a 64-element range-compressed profile, and feeds that profile into a 16×16 INT8 systolic array that runs neural network inference via four sequential tiling passes. Output is a discrete target classification (8 classes). Everything runs on a single Sky130 die with no external processor.

The chip works alongside a TI IWR6843ISK 60GHz radar eval board, which provides raw IQ samples over an LVDS interface. The IWR6843's onboard DSP does classical signal processing only — this chip provides the learned classification layer the IWR cannot do.

---

## Key parameters [FROZEN]

| Parameter | Value |
|---|---|
| FFT size N | 64 |
| Array dimensions | 16×16 |
| Output classes | 8 |
| Input sample width | 16-bit complex (16 real + 16 imaginary) |
| FFT butterfly accumulation | 32-bit internal, truncated to 16-bit after IFFT |
| Systolic input quantization | 8 MSBs of each 16-bit matched filter output bin |
| Tiling passes per inference | 4 (16-element slices of the 64-element range profile) |
| Systolic array weights | INT8 |
| Systolic array accumulators | INT32 |
| Bias | INT16 per output, Wishbone-writable, added in activation unit before requantization |
| Requantization | Q16.16 scale factor, runtime-configurable via Wishbone |
| Target clock | 25 MHz (50 MHz stretch goal) |
| Process | SkyWater 130nm, sky130_fd_sc_hd standard cells |
| Caravel harness | PicoRV32 host, Wishbone B4 bus |

---

## Six modules

| Module | Owner | File |
|---|---|---|
| Matched filter front end | DSP Group | `rtl/matched_filter.sv` |
| 16×16 systolic array | Accelerator Group | `rtl/systolic_array.sv` |
| Nonlinear activation unit | Accelerator Group | `rtl/activation_unit.sv` |
| Wishbone slave interface | Integration Group | `rtl/wishbone_slave.sv` |
| Control FSM | Integration Group | `rtl/control_fsm.sv` |
| Radar input interface | Integration Group | `rtl/radar_input_interface.sv` |

All modules are instantiated in `rtl/top.sv`. Shared port and type definitions are in `rtl/interfaces.sv` — check this file before defining any port that crosses module boundaries.

---

## Toolchain

| Task | Tool |
|---|---|
| RTL | SystemVerilog |
| Simulation | Verilator |
| Testbenches | Cocotb (Python) |
| Golden models | Python + NumPy |
| NN training | PyTorch with quantization-aware training (QAT) |
| Synthesis + P&R | OpenLane 2 + OpenROAD |
| Standard cells | sky130_fd_sc_hd |
| DRC | Magic + KLayout |
| LVS | Netgen |
| STA | OpenSTA |
| FPGA prototype | PYNQ-Z2, Vivado 2025.1, AXI4-Lite replaces Wishbone |

Do not suggest commercial tools (Synopsys, Cadence, Mentor). Do not suggest VHDL. Do not suggest Verilog-2001 style — the project uses SystemVerilog throughout.

---

## Frozen decisions

These are not open questions. Do not suggest reconsidering them.

**Fixed-point widths:** 16-bit complex input samples, 32-bit butterfly accumulation, 16-bit truncation post-IFFT. The 32-bit accumulation is required — radar signals have ~40dB dynamic range and 8-bit accumulation overflows.

**Systolic array input quantization:** The matched filter outputs 64 × 16-bit values. These are quantized to INT8 by extracting the 8 MSBs of each 16-bit bin before entering the array. This happens at the input boundary between the matched filter output and the systolic array input mux in the FSM datapath.

**Tiling:** The 64-element range profile is processed in four sequential passes through the 16×16 array. The FSM holds a 2-bit tile counter. `clear` is asserted only on tile 0 — it must never be asserted on tiles 1–3, as doing so zeros partial sums accumulated from earlier tiles and produces a wrong result. After tile 3, the FSM transitions to ACTIVATE.

**Reference chirp storage:** Wishbone-writable register file, not ROM. Allows testing different waveforms on real silicon without re-spin.

**Accumulator reset:** Two separate signals — `rst` resets everything including stored weights; `clear` resets accumulators only. `clear` is asserted by the FSM at tile 0 entry. These are different signals — do not conflate them.

**Bias:** Each output neuron has a per-output INT16 bias stored in the Wishbone `BIAS` register region (0x10–0x4F). Bias is added inside the activation unit as the first step (before requantization, ReLU, and clip). Bias values are signed and sign-extended to INT32 before addition with the INT32 accumulator.

**Weight storage:** Synthesized register file, not OpenRAM macro. Total weight storage: 256 bytes for W1, 128 bytes for W2 (two-layer config). Total is well under the threshold where SRAM macro verification overhead is justified.

**Requantization scale:** Runtime-configurable via Wishbone register `SCALE` at offset 0x0C.

**weights_valid flag:** Once LOAD_WEIGHTS completes, `STATUS.weights_valid` (bit 3) is set. It means "W1 is currently loaded in the PE registers." Subsequent inferences skip LOAD_WEIGHTS entirely. Cleared by `CTRL.reset`, `CTRL.clear_weights_valid` (bit 3), or automatically by the FSM on entry to DONE in two-layer mode (because the PEs hold W2 at that point, not W1). In one-layer mode the flag is never auto-cleared — back-to-back inference is fully efficient.

**LOAD_SAMPLES bypass in LVDS mode:** In LVDS mode the FSM transitions directly LOAD_WEIGHTS → RUN_FILTER. LOAD_SAMPLES is skipped because samples are already buffered by `radar_input_interface`. In Wishbone mode, LOAD_SAMPLES runs normally.

**Clock target:** 25 MHz official, 50 MHz stretch. Do not suggest designing to 50 MHz as the primary target.

**Dataflow:** Weight-stationary. Do not suggest output-stationary.

**FSM error handling:** Configurable timeout watchdog via `TIMEOUT` register at 0x08. FSM transitions to `ERROR` state on timeout, stays there until host writes `CTRL.reset`. Start-during-run is silently ignored.

**LVDS interface:** External SN65LVDS1 line receivers on carrier PCB convert IWR6843 LVDS differential pairs to 1.8V single-ended signals before reaching Sky130 GPIO pads. Do not suggest receiving LVDS directly on Sky130 GPIO — both P and N lines sit above Sky130's ~0.9V input trip point and this does not work.

**Pin assignment:** LVDS input on io_in[15:18] (North die edge). UART on io_in/out[5:6]. Do not suggest reassigning these.

**Neural network topology:** Locked at Milestone 0 by empirical test (Model A vs Model B low-SNR accuracy comparison — see `docs/verification.md`). Do not suggest a topology change after M0.

---

## Wishbone register map [finalised at M0 — see docs/register_map.md after M0]

| Offset | Name | R/W | Description |
|---|---|---|---|
| 0x00 | `CTRL` | W | Bit 0: start. Bit 1: reset. Bit 2: mode (0=Wishbone, 1=LVDS). Bit 3: clear_weights_valid |
| 0x04 | `STATUS` | R | Bit 0: done. Bit 1: busy. Bit 2: error. Bit 3: weights_valid. Bits [7:4]: error code |
| 0x08 | `TIMEOUT` | W | Watchdog cycle count |
| 0x0C | `SCALE` | W | Q16.16 requantization scale |
| 0x10–0x4F | `BIAS` | W | 64 bytes — 32 × INT16 bias values (entries 0–15: L1 bias; entries 16–23: L2 bias if two-layer) |
| 0x50–0x14F | `WEIGHT_W1` | W | 256 bytes — Layer 1 weight matrix (16×16 INT8) |
| 0x150–0x1CF | `WEIGHT_W2` | W | 128 bytes — Layer 2 weight matrix (16×8 INT8); reserved if one-layer |
| 0x1D0–0x2CF | `SAMPLE_DATA` | W | 256 bytes — N=64 × 32-bit complex IQ samples (raw, fed into matched filter) |
| 0x2D0–0x3CF | `CHIRP_DATA` | W | 256 bytes — N=64 × 32-bit complex reference chirp |
| 0x3D0–0x3D7 | `RESULT` | R | 8 bytes — 8 × INT8 classification result |

---

## RTL coding conventions

The entire team must follow these. When generating RTL, follow them exactly.

**Reset:** Synchronous reset only, active high, signal named `rst`. No async resets anywhere in the design.

```systemverilog
always_ff @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end
```

**No latches:** All combinational blocks must have complete case statements and else branches. Always use `always_comb`, never `always @(*)`.

**No implicit nets:** All files start with `` `default_nettype none ``. Every signal must be explicitly declared.

**Parameterization:** Use parameters for all widths and dimensions. Never hardcode `16`, `64`, `8`, or `32` — use `DATA_WIDTH`, `N`, `NUM_CLASSES`, `ACC_WIDTH`. Parameters are defined in `rtl/interfaces.sv`.

**Naming conventions:**
- Modules: `snake_case`
- Ports: `snake_case`
- Parameters: `UPPER_SNAKE_CASE`
- Internal signals: `snake_case`
- FSM states: `UPPER_SNAKE_CASE` via `typedef enum`
- Active-high enables: `_en` suffix
- Active-high valids: `_valid` suffix
- Done signals: `_done` suffix

**File structure:** One module per file. Module name matches filename.

**Signed arithmetic:** Use `signed` keyword explicitly when doing INT8 or INT32 arithmetic. Do not rely on implicit signedness.

```systemverilog
logic signed [7:0]  weight;
logic signed [7:0]  activation;
logic signed [31:0] accumulator;

always_ff @(posedge clk) begin
    if (clear)
        accumulator <= '0;
    else if (compute)
        accumulator <= accumulator + (activation * weight);
end
```

---

## Testbench conventions

All testbenches use Cocotb + Verilator. Testbench files are in `tb/`, named `test_<module>.py`.

Every testbench must import and use the fixed-point golden model for checking:

```python
import sys
sys.path.append('../golden')
from golden_model_fixed import run_matched_filter, run_inference
```

Do not re-implement signal processing logic inside a testbench. Generate expected outputs from the golden model, drive the same inputs into the RTL, compare outputs.

Standard test structure:

```python
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import numpy as np

@cocotb.test()
async def test_name(dut):
    cocotb.start_soon(Clock(dut.clk, 40, units="ns").start())  # 25 MHz
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)
    # test body
```

Clock period is 40ns (25 MHz). Always reset for exactly one cycle before driving inputs.

---

## Golden model locations

| File | Purpose |
|---|---|
| `golden/golden_model_float.py` | Double-precision reference. Use to validate algorithm correctness. |
| `golden/golden_model_fixed.py` | Fixed-point reference mirroring RTL bit widths. Use for RTL output checking. Implements tiling, bias addition, and (if two-layer) both passes. |
| `golden/precision_sweep.py` | Accuracy vs bit width analysis. Run at M0. |
| `golden/generate_dataset.py` | Synthetic training data generator. |
| `golden/train.py` | PyTorch QAT training script. Trains Model A and Model B for M0 comparison. |
| `golden/export_weights.py` | Exports INT8 weights in the format the systolic array PE grid expects. |
| `golden/weights_int8.bin` | One-layer trained weights from synthetic dataset. |
| `golden/weights_int8_w1.bin` | Two-layer config: Layer 1 weights (if two-layer chosen at M0). |
| `golden/weights_int8_w2.bin` | Two-layer config: Layer 2 weights (if two-layer chosen at M0). |
| `golden/weights_int8_v2.bin` | Retrained weights after real IWR6843 captures (available after M2.5). |

---

## FSM state reference

```
                    ┌── (weights_valid set: skip LOAD_WEIGHTS) ──────────────────┐
                    │                                                             │
IDLE → LOAD_WEIGHTS → LOAD_SAMPLES → RUN_FILTER → RUN_SYSTOLIC → ACTIVATE → DONE → IDLE
                    │              │               (×4 tiles,     (×2 if        │
                    └─(LVDS mode:  └─(LVDS mode:   clear on t=0   two-layer)    │
                       skip to        skip to       only)                        │
                       RUN_FILTER)    RUN_FILTER)                                │
                                                                                 │
                         ERROR ◄─── any stage exceeds TIMEOUT ──────────────────┘
```

Key signals:
- `clear` — assert only on tile 0 entry of RUN_SYSTOLIC. Resets accumulators, not weights.
- `rst` — resets everything including stored weights.
- `weights_valid` — set after LOAD_WEIGHTS completes. Cleared by reset or CTRL.clear_weights_valid.
- `frame_ready` — from radar_input_interface. Triggers FSM in LVDS mode without CTRL.start.

---

## Documentation consistency

**Any change to a design parameter, interface, register map, FSM behavior, or module port must be reflected across all affected docs.** These files cross-reference each other and drift silently — a register offset updated in one place but not another causes bugs in firmware, testbenches, and RTL simultaneously.

When making a change, check every file in this list and update each one that references what you changed:

| What changed | Files to update |
|---|---|
| Register map (offsets, sizes, new registers) | `docs/architecture.md` §2.4, `docs/AGENTS.md` register map, `docs/verification.md` Wishbone test plan |
| FSM states or transitions | `docs/architecture.md` §2.5, `docs/AGENTS.md` FSM reference |
| Module port added/removed/renamed | `docs/architecture.md` port table for that module, `rtl/interfaces.sv` |
| Key parameter (N, ARRAY_DIM, clock, widths) | `docs/AGENTS.md` key parameters table, `docs/architecture.md` |
| Milestone deliverable added/changed | `docs/milestones.md`, `docs/implementation_plan.md` repo tree if a new file |
| New frozen decision | `docs/AGENTS.md` frozen decisions section |
| Hardware component added/removed | `docs/hardware.md` BOM, `docs/AGENTS.md` references if a new datasheet |
| Test plan change | `docs/verification.md` per-module test plan |

Do not update a single file in isolation. If you are not sure which docs are affected, search for the changed term across `docs/` before finishing.

---

## What to check before suggesting anything

Before generating RTL, a testbench, or a fix, check:

1. Does the port you're adding exist in `rtl/interfaces.sv`? If not, it needs to be added there, not just in the module file.
2. Does your suggestion change a frozen decision? If yes, don't suggest it.
3. Does your RTL use synchronous reset named `rst`? If not, fix it.
4. Does your RTL start with `` `default_nettype none ``? If not, add it.
5. Does your testbench import the fixed-point golden model for output checking? If not, add the import.
6. Are all widths parameterized via constants from `interfaces.sv`? If not, fix the hardcodes.
7. Does your suggested tool exist in the toolchain table above? If not, the team doesn't have it.
8. If you're writing FSM code: does `clear` only fire on tile 0? Does your tiling loop go exactly 4 passes? Does it handle weights_valid and LOAD_SAMPLES bypass correctly?
9. If you changed any design detail: did you update all affected docs per the consistency table above?

---

## External references

| Resource | URL |
|---|---|
| Efabless Caravel harness | https://github.com/efabless/caravel |
| Efabless Caravel user project template | https://github.com/efabless/caravel_user_project |
| OpenLane 2 | https://github.com/efabless/openlane2 |
| OpenROAD (P&R engine inside OpenLane) | https://github.com/The-OpenROAD-Project/OpenROAD |
| OpenROAD docs | https://openroad.readthedocs.io |
| OpenSTA (STA engine, part of OpenROAD project) | https://github.com/The-OpenROAD-Project/OpenSTA |
| Sky130 PDK | https://github.com/google/skywater-pdk |
| sky130_fd_sc_hd cell library | https://github.com/google/skywater-pdk-libs-sky130_fd_sc_hd |
| PicoRV32 | https://github.com/YosysHQ/picorv32 |
| Cocotb docs | https://docs.cocotb.org |
| TI IWR6843ISK product page | https://www.ti.com/tool/IWR6843ISK |
| TI DCA1000EVM product page | https://www.ti.com/tool/DCA1000EVM |
| TI mmWave SDK (includes LVDS streaming interface spec) | https://www.ti.com/tool/MMWAVE-SDK |
| SN65LVDS1 datasheet | https://www.ti.com/product/SN65LVDS1 |
| Wishbone B4 specification | https://cdn.opencores.org/downloads/wbspec_b4.pdf |
| PYNQ-Z2 | https://www.pynq.io/boards.html |
| IHP SG13G2 PDK (tapeout fallback) | https://github.com/IHP-Open-PDKs/IHP-Open-PDK |
