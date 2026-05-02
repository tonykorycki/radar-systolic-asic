# Pin Assignment

**Status:** Frozen at Milestone 0. Do not modify without full team sign-off.

All pin assignments are for the Efabless Caravel harness. User area I/O uses the `io_in` / `io_out` / `io_oeb` arrays provided by the Caravel wrapper. Indices refer to the Caravel `mprj_io` pad ring.

---

## Pin table

| Function | Signal | Direction | Caravel pad | Notes |
|---|---|---|---|---|
| LVDS data lane 0 | `io_in[15]` | IN | mprj_io[15] | North die edge. Single-ended after SN65LVDS1 line receiver on carrier PCB |
| LVDS data lane 1 | `io_in[16]` | IN | mprj_io[16] | North die edge. Single-ended after SN65LVDS1 line receiver |
| LVDS bit clock | `io_in[17]` | IN | mprj_io[17] | North die edge. Async domain — async FIFO in `radar_input_interface` |
| LVDS frame clock | `io_in[18]` | IN | mprj_io[18] | North die edge. Marks chirp frame boundaries |
| UART TX | `io_out[6]` | OUT | mprj_io[6] | Caravel management UART to CP2102 on carrier PCB |
| UART RX | `io_in[5]` | IN | mprj_io[5] | Caravel management UART from CP2102 |
| SPI MOSI | `io_in[23]` | IN | mprj_io[23] | Optional PYNQ-Z2 debug host via Pmod. Level-shifted by TXS0104 on carrier PCB |
| SPI MISO | `io_out[24]` | OUT | mprj_io[24] | Optional PYNQ-Z2 debug host |
| SPI CLK | `io_in[25]` | IN | mprj_io[25] | Optional PYNQ-Z2 debug host |
| SPI CS | `io_in[26]` | IN | mprj_io[26] | Optional PYNQ-Z2 debug host |
| Debug status [3:0] | `io_out[22:19]` | OUT | mprj_io[22:19] | FSM state / bringup visibility |

---

## Placement notes

- `io_in[15:18]` (LVDS) are 4 consecutive pads on the North die edge per the Caravel pad ring order. `radar_input_interface` is placed in the northern floorplan region to minimize routing distance.
- LVDS differential pairs on the carrier PCB must be length-matched within 5 mm, 100Ω differential impedance. Termination resistors at line receiver inputs.
- Sky130 GPIO cannot receive LVDS directly — both P and N lines exceed Sky130's ~0.9V input trip point. External SN65LVDS1 line receivers on the carrier PCB convert to 1.8V single-ended before reaching these pads.

---

## Unassigned pads

All `mprj_io` pads not listed above are unassigned. Leave `io_oeb` high (input mode) for unassigned pads in the Caravel wrapper.
