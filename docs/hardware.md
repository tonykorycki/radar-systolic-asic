# External Hardware and Carrier PCB

### Hardware to acquire

Items needed across all project phases. Evaluation boards have multi-week lead times — order at M0. Carrier PCB components are ordered when the KiCad BOM is finalized at M3.

**Evaluation boards:**

| Item | Qty | Phase needed | Purpose |
|---|---|---|---|
| [TI IWR6843ISK](https://www.ti.com/product/IWR6843ISK) | 1 | M2.5 | Radar front end — 60GHz FMCW, ADC, LVDS output. ISK variant has integrated antennas. |
| [TI DCA1000EVM](https://www.ti.com/tool/DCA1000EVM) | 1 | M2.5 | Raw IQ capture board for FPGA prototype and real data collection. Connects to IWR6843ISK via 60-pin header. |
| [PYNQ-Z2](https://www.pynq.io/boards.html) | 1 | M2.5 | FPGA prototype platform (Digilent / AMD). Runs AXI4-Lite version of the RTL. |
| SWD debugger (J-Link EDU Mini or Black Magic Probe) | 1 | M4 | PicoRV32 firmware programming on carrier PCB. |

**Carrier PCB components (order when KiCad BOM finalized at M3):**

| Item | Qty | Purpose | Notes |
|---|---|---|---|
| [SN65LVDS1](https://www.ti.com/product/SN65LVDS1) | 4 | LVDS line receivers — convert IWR6843 differential pairs to 1.8V single-ended | One IC per differential pair |
| [TXS0104](https://www.ti.com/product/TXS0104E) or equivalent | 1 | Bidirectional level shifter, 1.8V ↔ 3.3V | SPI lines to PYNQ-Z2 Pmod header |
| [CP2102](https://www.silabs.com/interface/usb-bridges/classic/device.cp2102) | 1 | USB-UART bridge | Laptop serial console via single USB-C cable |
| USB-C connector (SMD) | 1 | Power + comms | 5V VBUS → LDOs; D+/D- → CP2102 |
| 3.3V LDO | 1 | 5V → 3.3V rail | Part TBD in `docs/carrier_pcb_notes.md` |
| 1.8V LDO | 1 | 5V → 1.8V rail for chip + line receivers | Part TBD in `docs/carrier_pcb_notes.md` |
| 100Ω resistor, 0402 | 8 | LVDS differential termination | Two per line receiver input (one per leg) |
| Decoupling capacitors, 0402 | ~20 | Power rail bypassing | 100nF + 10μF per rail per IC |

**PCB fabrication:**

| Item | Notes |
|---|---|
| 4-layer carrier PCB | JLCPCB advanced service. WLCSP 0.5mm bump pitch requires 4 mil min trace/space. JLCPCB standard spec is 6 mil — confirm advanced tier is selected at time of order. JLC04161H-7628 stackup supports controlled impedance. ~2 week turnaround. |

**Chip (received, not purchased):** The tapeout die arrives from the Efabless MPW shuttle after submission — not purchased. WLCSP, 3.2mm × 5.3mm, 0.5mm bump pitch. Estimated return: several months after M6 submission.

---

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
- Bidirectional level shifter (TXS0104 or equivalent, 1.8V ↔ 3.3V) on SPI lines for PYNQ-Z2 Pmod header.
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
