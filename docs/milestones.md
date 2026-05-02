# Build Plan and Milestones

## Incremental Build Plan

Gate policy: each milestone must be signed off before the next begins. No module advances to integration without passing its unit testbench against `golden_model_fixed.py`.

---

### Milestone 0 — Architecture lock (May 2026)

All of the following must be completed before any RTL is written. This milestone produces the locked interface and parameter files that all groups build against in Milestone 1.

**Precision sweep (first task, blocks everything else):**
Run `golden/precision_sweep.py` at Q8.8, Q12.4, Q16.16 on synthetic chirps with 40dB dynamic range. Confirm 16-bit input provides acceptable classification accuracy. Commit results to `results/precision_sweep/`.

**NN topology decision (blocks interfaces.sv and register map):**
Run the empirical Model A vs Model B comparison described in `docs/verification.md`. Train both architectures, compare low-SNR accuracy (5–10 dB), apply the 5% decision rule, commit results and written justification to `results/m0_layer_decision/`. The Wishbone register map is finalized only after this decision — `WEIGHT_W2` region and Layer 2 `BIAS` entries are confirmed or removed based on the outcome.

**Interface and register map freeze:**
Freeze all inter-block interfaces in `rtl/interfaces.sv`. No interface changes after this point without full team sign-off. Commit `docs/register_map.md` with the final layout incorporating the layer decision.

**Supporting deliverables:**
- Write and validate both golden models on synthetic chirps.
- Begin neural network training workstream (parallel, runs through Milestone 2): generate synthetic dataset from `golden_model_fixed.py`, train float baseline for chosen topology.
- Configure IWR6843 chirp parameters.
- Commit `docs/parameter_choices.md` and `docs/pin_assignment.md`.

**Group responsibilities:**
- **DSP Group:** Write and validate `golden_model_float.py`. Confirm FFT algorithm and chirp multiply are correct in float. Define matched filter ports for `interfaces.sv`.
- **Accelerator Group:** Write and validate `golden_model_fixed.py`. Run `precision_sweep.py` and own the quantization width justification. Define systolic array and activation unit ports for `interfaces.sv`.
- **Integration Group:** Draft `interfaces.sv`. Own `docs/register_map.md`, `docs/parameter_choices.md`, `docs/pin_assignment.md` once topology decision lands.
- **Verification & Backend:** Run the Model A vs B training comparison. Generate synthetic dataset. Set up Verilator + Cocotb build infrastructure.
- **All:** Module ownership assignment, IWR6843 chirp parameter configuration.

**M0 deliverables:**
`rtl/interfaces.sv`, `golden/golden_model_float.py`, `golden/golden_model_fixed.py`, `results/precision_sweep/`, `results/m0_layer_decision/`, `docs/register_map.md`, `docs/parameter_choices.md`, `docs/pin_assignment.md`.

All M0 deliverables must be committed and reviewed before summer break so September is not a cold restart.

---

### Milestone 1 — Module RTL + unit tests (Sep–Nov 2026)

All six modules developed independently. All must pass unit tests before Milestone 2.

- **DSP Group:** `rtl/matched_filter.sv` + `tb/test_matched_filter.py`. Includes Wishbone-writable chirp register file.
- **Accelerator Group:** `rtl/systolic_array.sv` + `rtl/activation_unit.sv` + testbenches. Systolic array implements the four-pass tiling protocol — `clear` on tile 0 only. Activation unit implements bias addition (bias → requantize → ReLU → clip). If two-layer chosen at M0: systolic array testbench includes the layer-2 single-pass case.
- **Integration Group:** `rtl/wishbone_slave.sv` + `rtl/control_fsm.sv` + `rtl/radar_input_interface.sv` + testbenches. FSM implements tile counter (2-bit), `weights_valid` flag, LOAD_SAMPLES bypass in LVDS mode, timeout watchdog, ERROR state, and layer counter if two-layer. LVDS mode select in CTRL register.
- **Verification & Backend:** Verilator + Cocotb Makefiles, unit test execution and reporting, neural network QAT training and weight export (both W1 and W2 if two-layer).
- **Integration Group (firmware, parallel workstream):** Begin `firmware/picorv32/` — Wishbone driver routines for weight load, sample load, start/poll, result read. Firmware is developed alongside RTL and tested in Verilator co-simulation before M3.

**M1 deliverables:** all six RTL files passing unit testbenches. Results in `results/unit/`. Trained INT8 weights in `golden/weights_int8.bin` (one-layer) or `golden/weights_int8_w1.bin` + `golden/weights_int8_w2.bin` (two-layer).

---

### Milestone 2 — Top-level integration (Dec 2026)

Wire all blocks in `rtl/top.sv`. Write `tb/test_top.py` covering:
- Both Wishbone and LVDS paths
- Full four-pass tiling end-to-end, verified against `golden_model_fixed.py`
- Two-layer inference path end-to-end (if applicable)
- `weights_valid` flag behavior across back-to-back inferences (second run skips LOAD_WEIGHTS)
- Timeout recovery
- Minimum 50 distinct test vectors

No RTL changes to individual modules without re-running their unit tests.

**Group responsibilities:**
- **DSP Group:** Support integration, fix any matched filter bugs surfaced by top-level tests.
- **Accelerator Group:** Support integration, fix any tiling or activation bugs surfaced by top-level tests.
- **Integration Group:** Write `top.sv` and `test_top.py`. Own the LVDS end-to-end integration path.
- **Verification & Backend:** Drive test execution, verify all vectors against `golden_model_fixed.py`, track pass/fail.

**M2 deliverables:** `rtl/top.sv` passing end-to-end testbench. Results in `results/integration/`.

---

### Milestone 2.5 — FPGA prototype (Dec 2026–Jan 2027)

Run the RTL on real radar data before committing to synthesis. This milestone gates Milestone 3 — synthesis does not start until the FPGA prototype produces correct outputs on real IWR6843 captures.

*A two-week buffer is built into this milestone for FPGA bring-up surprises. Hard contingency: if the FPGA prototype is not producing correct real-radar outputs by January 10, 2027, unblock M3 synthesis anyway using the M2 simulation-validated RTL. The risk is shipping RTL not validated on real hardware; the alternative is missing the tapeout window. Document any outstanding real-radar discrepancies and resolve during M3–M4 if possible.*

Port RTL to PYNQ-Z2: replace Wishbone with AXI4-Lite, synthesize in Vivado 2025.1, deploy as PYNQ overlay. All other RTL (including tiling logic, bias, weights_valid) is identical to the tapeout version.

Connect IWR6843ISK via DCA1000EVM → 1 Gbps Ethernet (USB-C to Ethernet adapter on laptop/PYNQ) → PYNQ ARM → AXI writes into fabric. Python script on PYNQ ARM receives UDP frames from DCA1000EVM, formats them, writes to FPGA fabric.

Validation: place corner reflector at 3m, 5m, 10m. Verify FPGA pipeline classifies correctly. Supplement with human subject captures for pedestrian class. Commit results to `results/fpga_prototype/`.

Use this milestone to collect Phase 2 real training data. Retrain with combined synthetic + real dataset. Export updated weights to `golden/weights_int8_v2.bin` (or `_w1_v2` / `_w2_v2` if two-layer).

**Group responsibilities:**
- **DSP Group:** Validate matched filter output on real IWR6843 captures — confirm range peaks land in expected bins.
- **Accelerator Group:** Validate inference classification on real radar data against known targets.
- **Integration Group:** AXI4-Lite port of RTL, Vivado synthesis, PYNQ overlay deployment, DCA1000EVM UDP capture script on PYNQ ARM.
- **Verification & Backend:** Real data capture and labeling, retrain with combined dataset, export updated weights.

**M2.5 deliverables:** PYNQ-Z2 overlay passing real radar data validation. Updated weights. Capture dataset in `data/real_captures/`.

---

### Milestone 3 — Synthesis + timing closure (Jan 2027)

Run OpenLane synthesis targeting `sky130_fd_sc_hd`. Target 25 MHz. Review critical path — expected bottleneck is the INT8 multiplier in the systolic PE. If timing fails at 25 MHz, pipeline the PE multiplier (adds one latency cycle per accumulation step, functionally correct). Formal equivalence check gate-level netlist vs RTL.

Also during this milestone: complete carrier PCB KiCad schematic and layout. Submit Gerbers to JLCPCB by end of January (4-layer controlled impedance stackup, ~2 week turnaround).

**Group responsibilities:**
- **DSP Group:** Review FFT butterfly critical path in synthesis reports. Flag if matched filter pipeline depth needs adjustment.
- **Accelerator Group:** Review systolic PE critical path (INT8 multiplier chain). Pipeline the PE multiplier if timing fails at 25 MHz.
- **Integration Group:** Complete firmware and co-simulate against RTL in Verilator. Own carrier PCB KiCad schematic and layout — submit Gerbers.
- **Verification & Backend:** Run OpenLane synthesis. Formal equivalence check gate-level netlist vs RTL.

**M3 deliverables:** gate-level netlist meeting timing. Reports in `results/synth/`. KiCad files in `hardware/carrier_pcb/`. PicoRV32 firmware complete and co-simulated against RTL in Verilator (`firmware/picorv32/`).

---

### Milestone 4 — Physical design (Feb 2027)

Floorplan: `radar_input_interface` in north region (close to io_in[15:18]), systolic array as regular grid in center, matched filter and FSM surrounding, weight register file at east edge. Power ring + mesh. OpenROAD global → detail placement. CTS: single clock domain, balanced tree to all 256 PE flip-flops and FFT pipeline registers. OpenROAD global → detailed routing. Target DRC-clean first pass.

Carrier PCB arrives from fab this month. Bring up power rails, verify 1.8V and 3.3V before populating ICs. Flash PicoRV32 firmware via SWD debugger and verify Wishbone register access before chip is populated.

**Group responsibilities:**
- **DSP Group:** Advise on matched filter placement relative to sample buffer routing.
- **Accelerator Group:** Advise on systolic array floorplan — regular grid in center region, weight register file at east edge.
- **Integration Group:** PCB bringup — verify power rails, flash firmware via SWD, confirm Wishbone register read/write on bare board.
- **Verification & Backend:** Run OpenROAD global and detailed placement, CTS, routing. Target DRC-clean first pass.

**M4 deliverables:** routed DEF + GDS in `results/pnr/`. Carrier PCB power rails verified. Firmware flashed and Wishbone comms confirmed on bare board.

---

### Milestone 5 — Sign-off (Mar 2027)

DRC: Magic + KLayout, zero violations. LVS: Netgen, clean. STA: OpenSTA setup and hold at 25 MHz, worst-case slow and best-case fast corners. Re-run functional simulation on gate-level netlist with back-annotated parasitics if STA reveals unexpected paths.

**Group responsibilities:**
- **DSP Group:** Support gate-level simulation if STA reveals unexpected paths in the matched filter pipeline.
- **Accelerator Group:** Support gate-level simulation if STA reveals unexpected paths in the systolic PE chain.
- **Integration Group:** Verify firmware behaves correctly against gate-level netlist in co-simulation.
- **Verification & Backend:** Run DRC (Magic + KLayout), LVS (Netgen), STA (OpenSTA) at all corners. Own sign-off report.

**M5 deliverables:** clean reports in `results/signoff/`.

---

### Milestone 6 — Tapeout submission (Apr–May 2027)

Integrate hardened block into Efabless Caravel harness. Run Efabless precheck tool. Resolve precheck failures. GDSII export and final KiCad visual inspection. Submit to Sky130 MPW shuttle.

Fallback: if Sky130 shuttle timing slips, same flow targets GlobalFoundries 180nm via IHP. RTL is PDK-agnostic.

**Group responsibilities:**
- **Integration Group:** Caravel harness integration, precheck failure resolution, final KiCad visual inspection.
- **Verification & Backend:** Run Efabless precheck tool, GDSII export, submission.
- **All:** Final review of GDSII before submission.

**M6 deliverables:** GDSII committed to repo, Efabless submission confirmed.

---
