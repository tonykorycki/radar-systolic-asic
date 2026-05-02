# Radar Inference Accelerator ASIC

Custom silicon tapeout on SkyWater 130nm via Efabless Caravel MPW shuttle. The chip takes raw complex IQ radar samples from a TI IWR6843 60GHz radar front end, runs a matched filter (FFT → complex multiply → IFFT) to produce a range-compressed profile, and feeds that profile into a 16×16 INT8 systolic array running quantized neural network inference. Output is a discrete target classification (8 classes) with no external compute required.

Target submission: Spring 2027.

---

## Documentation

| Document | Purpose |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Module descriptions, port tables, register map, FSM states |
| [docs/verification.md](docs/verification.md) | Golden models, NN topology decision, per-module test plans |
| [docs/milestones.md](docs/milestones.md) | Build plan, milestone deliverables, gate policy |
| [docs/hardware.md](docs/hardware.md) | Carrier PCB, IWR6843ISK interface, connection paths |
| [docs/AGENTS.md](docs/AGENTS.md) | Context for AI assistants and new contributors — frozen decisions, conventions, toolchain |

Start with `docs/architecture.md` for the design, `docs/milestones.md` for the schedule, and `docs/AGENTS.md` for coding conventions and what not to change.

---

## Toolchain

| Task | Tool |
|---|---|
| RTL | SystemVerilog |
| Simulation | Verilator |
| Testbenches | Cocotb (Python) |
| Golden models | Python + NumPy |
| NN training | PyTorch + QAT |
| Synthesis + P&R | OpenLane 2 + OpenROAD |
| Standard cells | sky130_fd_sc_hd |
| DRC | Magic + KLayout |
| LVS | Netgen |
| STA | OpenSTA |
| FPGA prototype | PYNQ-Z2, Vivado 2025.1 |

Open-source tools only. No Synopsys, Cadence, or Mentor.

---

## Quick start

**Run the precision sweep (Milestone 0 first task):**
```bash
cd golden
python precision_sweep.py
```

**Run unit tests (after RTL is written):**
```bash
cd tb
make test_matched_filter   # or test_systolic, test_activation, etc.
```

**Run synthesis:**
```bash
cd openlane
flow.tcl -design radar_accel
```

---

## Team

DSP Group · Accelerator Group · Integration Group · Verification & Backend Group

See [docs/architecture.md](docs/architecture.md) for module ownership assignments.
