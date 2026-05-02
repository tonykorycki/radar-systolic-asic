# Radar Inference Accelerator — Project Plan

**Platform:** SkyWater 130nm via Efabless Caravel MPW shuttle  
**Target submission:** Spring 2027  
**Team structure:** DSP Group · Accelerator Group · Integration Group · Verification & Backend Group

---

## Overview

This chip is a complete radar signal processing pipeline on a single Sky130 die. Raw IQ radar samples enter a matched filter front end (FFT → complex multiply → IFFT), producing a 64-element range-compressed profile. That profile feeds a 16×16 INT8 systolic array running quantized neural network inference via four sequential tiling passes. Output is a discrete target classification from 8 classes. Everything runs on-chip with PicoRV32 (Caravel harness) orchestrating over Wishbone.

---

See [docs/architecture.md](architecture.md) §3 for the document index and §4 for the repository structure.
