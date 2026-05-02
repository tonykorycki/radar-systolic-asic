# Wishbone Register Map

**Status:** Frozen at Milestone 0. Do not modify without full team sign-off.

All offsets are relative to the Caravel user project base address. Register width is 32 bits; sub-word fields are described per register. Multi-byte regions (BIAS, WEIGHT, SAMPLE, CHIRP, RESULT) are byte-addressable within the region.

---

## Register map

| Offset | Name | R/W | Width | Description |
|---|---|---|---|---|
| 0x00 | `CTRL` | W | 32 | Bit 0: start. Bit 1: reset. Bit 2: mode (0=Wishbone, 1=LVDS). Bit 3: clear_weights_valid |
| 0x04 | `STATUS` | R | 32 | Bit 0: done. Bit 1: busy. Bit 2: error. Bit 3: weights_valid. Bits [7:4]: error code |
| 0x08 | `TIMEOUT` | W | 32 | Watchdog cycle count. FSM enters ERROR if any stage exceeds this count |
| 0x0C | `SCALE` | W | 32 | Q16.16 requantization scale factor for activation unit |
| 0x10–0x4F | `BIAS` | W | 64 B | 32 × INT16 bias values. Entries 0–15: Layer 1 bias. Entries 16–23: Layer 2 bias (two-layer config only) |
| 0x50–0x14F | `WEIGHT_W1` | W | 256 B | Layer 1 INT8 weight matrix — 16×16 = 256 bytes, row-major |
| 0x150–0x1CF | `WEIGHT_W2` | W | 128 B | Layer 2 INT8 weight matrix — 16×8 = 128 bytes, row-major. Reserved if one-layer |
| 0x1D0–0x2CF | `SAMPLE_DATA` | W | 256 B | N=64 complex IQ samples — 64 × 32-bit (16-bit real + 16-bit imaginary, interleaved) |
| 0x2D0–0x3CF | `CHIRP_DATA` | W | 256 B | N=64 complex reference chirp — same format as SAMPLE_DATA |
| 0x3D0–0x3D7 | `RESULT` | R | 8 B | 8 × INT8 classification scores, one per output class |

---

## CTRL register (0x00)

| Bit | Name | Description |
|---|---|---|
| 0 | `start` | Pulse high to begin inference. Ignored if FSM is not in IDLE or DONE |
| 1 | `reset` | Synchronous reset — returns FSM to IDLE, clears weights_valid |
| 2 | `mode` | 0 = Wishbone preload mode. 1 = LVDS streaming mode |
| 3 | `clear_weights_valid` | Clears weights_valid flag, forcing LOAD_WEIGHTS on next inference |

## STATUS register (0x04)

| Bit | Name | Description |
|---|---|---|
| 0 | `done` | Inference complete. Result valid in RESULT register |
| 1 | `busy` | FSM active — not in IDLE, DONE, or ERROR |
| 2 | `error` | Timeout or fault. Cleared only by CTRL.reset |
| 3 | `weights_valid` | W1 is loaded in PE registers. Next inference skips LOAD_WEIGHTS |
| [7:4] | `error_code` | Error classification (TBD at M1) |

---

## Size verification

| Region | Formula | Expected size |
|---|---|---|
| WEIGHT_W1 | 16 × 16 × 1 byte | 256 bytes ✓ |
| WEIGHT_W2 | 16 × 8 × 1 byte | 128 bytes ✓ |
| BIAS | 32 × 2 bytes (INT16) | 64 bytes ✓ |
| SAMPLE_DATA | 64 × 4 bytes (32-bit complex) | 256 bytes ✓ |
| CHIRP_DATA | 64 × 4 bytes (32-bit complex) | 256 bytes ✓ |
| RESULT | 8 × 1 byte (INT8) | 8 bytes ✓ |

---

## Notes

- `WEIGHT_W2` region is present in hardware regardless of one-layer vs two-layer decision. In one-layer mode the region is writable but ignored by the FSM.
- `BIAS[16:23]` (Layer 2 bias) is likewise always present; unused in one-layer mode.
- Weight matrices are stored row-major. Row index = output neuron, column index = input feature.
- `weights_valid` tracks W1 only. W2 is always reloaded unconditionally after Layer 1 ACTIVATE in two-layer mode.
