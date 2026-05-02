# Radar Inference Accelerator — Project Plan

**Platform:** SkyWater 130nm via Efabless Caravel MPW shuttle  
**Target submission:** Spring 2027  
**Team structure:** DSP Group · Accelerator Group · Integration Group · Verification & Backend Group

---

## Overview

This chip is a complete radar signal processing pipeline on a single Sky130 die. Raw IQ radar samples enter a matched filter front end (FFT → complex multiply → IFFT), producing a 64-element range-compressed profile. That profile feeds a 16×16 INT8 systolic array running quantized neural network inference via four sequential tiling passes. Output is a discrete target classification from 8 classes. Everything runs on-chip with PicoRV32 (Caravel harness) orchestrating over Wishbone.

---

## Document index

| Document | Contents |
|---|---|
| [docs/architecture.md](architecture.md) | IP definition, module descriptions, interface tables, register map, FSM states |
| [docs/verification.md](verification.md) | Golden models, NN topology decision procedure, per-module test plans, sign-off criteria |
| [docs/milestones.md](milestones.md) | Incremental build plan — milestone deliverables and gate policy |
| [docs/hardware.md](hardware.md) | IWR6843ISK, carrier PCB design requirements, connection paths |
| [docs/AGENTS.md](AGENTS.md) | AI assistant context — frozen decisions, coding conventions, toolchain |
| docs/register_map.md | **Frozen at M0** — final Wishbone register layout |
| docs/parameter_choices.md | **Frozen at M0** — FFT size, array dimensions, clock target justification |
| docs/pin_assignment.md | **Frozen at M0** — Caravel pad assignments |
| docs/carrier_pcb_notes.md | Component choices and layout notes for carrier PCB |

---

## Repository structure

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
│   ├── weights_int8.bin               # synthetic-data trained weights (one-layer)
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
│   ├── m0_layer_decision/             # Model A vs B accuracy comparison
│   ├── unit/
│   ├── integration/
│   ├── fpga_prototype/
│   ├── synth/
│   ├── pnr/
│   └── signoff/
└── docs/
    ├── architecture.md
    ├── verification.md
    ├── milestones.md
    ├── hardware.md
    ├── AGENTS.md
    ├── register_map.md                # frozen at M0
    ├── parameter_choices.md           # frozen at M0
    ├── pin_assignment.md              # frozen at M0
    └── carrier_pcb_notes.md
```
