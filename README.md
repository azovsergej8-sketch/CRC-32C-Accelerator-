# Multi-Channel Pipelined CRC-32C Hardware Accelerator

[![Language](https://img.shields.io/badge/Language-SystemVerilog-blue.svg)](https://en.wikipedia.org/wiki/SystemVerilog)
[![Python Generation](https://img.shields.io/badge/RTL%20Generator-Python%203-green.svg)](https://www.python.org/)
[![Bus Standards](https://img.shields.io/badge/Interface-AMBA%20AXI4%2FAPB-red.svg)](https://developer.arm.com/architectures/system-architectures/amba)

A high-performance, 2-stage pipelined CRC-32C (Castagnoli polynomial `0x82F63B78`) calculation engine designed for high-frequency SoC packet processing. The IP core features automatically synthesized XOR reduction trees, hardware backpressure handling, a 32-channel context-switching arbiter, and native support for AMBA AXI4-Full and APB Slave interfaces.

## Architectural Overview

The architecture is split into a mathematical compute core, a multi-channel context arbiter, and dedicated memory controllers:

* **`crc32c_engine.sv`** — Two-stage pipelined CRC calculation core. Features dynamically selectable byte-enables (8/16/32-bit input words), combinational XOR trees, and hardware backpressure (`stall`) management.
* **`generate_matrices.py`** — Python script executing LSB-first Galois LFSR matrix transformations to auto-generate optimized, deterministic SystemVerilog reduction functions with minimal combinational depth.
* **`AXI4_Arbiter.sv`** — Central arbitration unit coordinating data streams across 32 independent channels. Manages context switching, AXI4-Full burst payload routing, and APB register access.
* **`BRAM.sv`** — Dual-port SRAM controller with two-stage pipelined Read/Write FSMs for storing per-channel CRC states and packet length descriptors.
* **`Interfaces.sv`** — Strongly typed SystemVerilog `interface` and `modport` bundles for `AXI4_Full`, `APB_Slave`, `CRC_arbiter`, and `bram_if`.

---

## Key Technical Highlights

### 1. Matrix Pre-computation & Minimal-Depth XOR Reduction
Rather than using sequential LFSR shift registers that restrict throughput to 1 bit/clock, the compute core relies on Galois LFSR matrix pre-computation. The `generate_matrices.py` tool models the state-transition matrices $A$ and $B$:
$$R_{next} = (A \cdot R_{curr}) \oplus (B \cdot D_{in})$$
This yields flat, single-cycle reduction XOR-trees for 8-bit, 16-bit, and 32-bit word widths, maximizing execution speed.

### 2. Two-Stage Pipelined Execution ($f_{max}$ Optimization)
To maintain high clock frequencies in modern ASIC/FPGA tech nodes, 32-bit data evaluations are sliced across two pipeline stages:
* **Stage 1:** Evaluates the lower 16-bit payload segment or full 8/16-bit words. Buffers the upper 16 bits if present.
* **Stage 2:** Completes upper half-word evaluation and commits the updated CRC residue.
* **Backpressure Control:** The control path transparently handles pipeline stalls (`bus_if.stall`) by latching internal state registers without dropping valid transaction beats.

### 3. Multi-Channel Context Switching & Interconnect
The accelerator supports up to 32 concurrent data channels:
* **Context Preservation:** Current CRC values and length descriptors are buffered in internal registers and backed by a dual-port BRAM array.
* **Interconnect Integration:** High-throughput streaming uses an AMBA AXI4-Full interface, while status and control registers are exposed via an APB Slave interface.

---

## Module Interfaces & Signal Map
+---------------------------------------+
                 |            AXI4_Arbiter               |
AXI4-Full Stream >|  [32-Channel Context Arbitration]    |< APB Slave (Config/Status)
|                                       |
+---+-+---------------------------+-+---+
| |                           | |
| | BRAM IF                   | | CRC IF
v v                           v v
+-------+                     +-------+
| BRAM  |                     | CRC32 |
| Memory|                     | Engine|
+-------+                     +-------+


### Supported Protocols:
* **AMBA AXI4-Full:** Address/Data burst write channels with configurable ID/Address width.
* **AMBA APB Slave:** Register-mapped interface for reading final CRC checksums and configuring channel parameters.
* **BRAM Interface:** Synchronous memory handshake with address decoding split into Channel ID (`CHAN_BITS`) and Word Index (`WORD_BITS`).

---

## Use Cases

* **Storage Subsystems:** Offloading hardware CRC-32C computation for NVMe-oF and SATA protocol frames.
* **Network Interface Cards (NIC):** High-speed Ethernet frame check sequence (FCS) verification.
* **High-Frequency Interconnects:** Real-time data integrity validation across SoC bus
