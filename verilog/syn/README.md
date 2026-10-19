# Logic synthesis of the STM CPU core

**English** | [日本語](README.ja.md)

Ready-to-run synthesis setups for the CPU core `stm_cntl` (with its two `stm_exu` ALUs), and for
the complete CPU with an AXI4 master port, `stm_axi_top` (see the last section).

| Directory | Tool | Contents |
|---|---|---|
| `quartus/` | Intel/Altera Quartus II (tested with 13.0sp1) | projects (`stm_cntl.qpf` / `.qsf`, `stm_axi_top.qpf` / `.qsf`) and timing constraints (`stm_cntl.sdc`, `stm_axi_top.sdc`) |
| `vivado/` | AMD/Xilinx Vivado (tested with 2022.2) | batch synthesis scripts (`synth.tcl`, `synth_axi.tcl`) and constraints (`stm_cntl.xdc`, `stm_axi_top.xdc`) |

## What is synthesized

Only `stm_cntl` is synthesized, as the original author also did for the VHDL version.
`stm_regfile` and `stm_memory` are **simulation models** and are left out:

* `stm_memory` has three asynchronous (same-cycle) read ports, so it cannot be mapped to FPGA
  block RAM; as is, the whole memory would become flip-flops and multiplexers. Running on real
  hardware needs a redesigned memory interface.
* As a result `stm_cntl` brings all register-file and memory signals out to its ports
  (484 pins). Quartus therefore targets a large-package device, and Vivado synthesizes
  out of context (no I/O buffers).
* Tie `RANDOM_FOR_OPCLH`, `RANDOM_FOR_IFRDY` and `RANDOM_FOR_IFCLH` to `1` in hardware
  (they only emulate cache misses in simulation).

## Running

> **Note: use a folder path without Japanese (non-ASCII) characters.**
> Quartus II 13.0 refuses such paths ("Can't create project … Specify a legal project name"),
> and Vivado 2022.2 crashed after RTL elaboration when run from one. Copy or clone the
> repository to e.g. `C:\work\stm-verilog` before synthesizing.

### Quartus

GUI: *File → Open Project* → `quartus/stm_cntl.qpf` → *Processing → Start Compilation*.

Command line:

```sh
cd verilog/syn/quartus
quartus_sh --flow compile stm_cntl
```

Reports go to `quartus/output_files/` (`stm_cntl.fit.summary`, `stm_cntl.sta.rpt`).
Device: Cyclone IV E EP4CE115F29C7 (DE2-115). Change `FAMILY` / `DEVICE` in the `.qsf` for another device.

### Vivado

```sh
cd verilog/syn/vivado
vivado -mode batch -source synth.tcl                              # xc7a100tcsg324-1 (default)
vivado -mode batch -source synth.tcl -tclargs xc7a35tcpg236-1     # another part
```

Reports go to `vivado/reports/` (`utilization.rpt`, `timing_summary.rpt`), the checkpoint to `stm_cntl_synth.dcp`.

## Results (as tested)

Clock target 25 MHz (40 ns), with half a cycle budgeted for the external logic on every I/O.

| Tool / device | Resources | Timing |
|---|---|---|
| Quartus II 13.0sp1, Cyclone IV E EP4CE115F29C7 (full compile) | 5,507 LEs, 1,623 registers, 484 pins | met at 25 MHz (setup slack +2.6 ns). An earlier build (before the 4 bus-handshake outputs were added) reached Fmax 38.6 MHz when constrained to 50 MHz |
| Vivado 2022.2, Artix-7 xc7a100tcsg324-1 (synthesis only) | 2,990 LUTs, 1,624 FFs | met at 25 MHz (WNS +11.7 ns, post-synthesis estimate) |

Warnings that remain are harmless: truncation of C-style unsized constants (e.g. `? 1 : 0`)
and decoded fields / pipeline tags that are never read and get optimized away.

## The CPU with an AXI4 master (`stm_axi_top`)

`stm_axi_top` (see [../README.md §8](../README.md#8-axi4-master-version-stm_axi_top)) contains
`stm_cntl`, `stm_regfile` and the bridge `stm_axi_master`, so it is a complete CPU whose only
interface is the AXI4 master port (281 pins including the observation outputs `PC` / `bus_error`).
The register file is built from flip-flops (it has four same-cycle read ports).

```sh
cd verilog/syn/quartus
quartus_sh --flow compile stm_axi_top
cd ../vivado
vivado -mode batch -source synth_axi.tcl        # reports in vivado/reports_axi/
```

| Tool / device | Resources | Timing |
|---|---|---|
| Quartus II 13.0sp1, Cyclone IV E EP4CE115F29C7 (full compile) | 7,686 LEs, 2,333 registers, 281 pins | met at 25 MHz (setup slack +2.4 ns) |
| Vivado 2022.2, Artix-7 xc7a100tcsg324-1 (synthesis only, out of context) | 4,412 LUTs, 2,337 FFs | met at 25 MHz (WNS +11.5 ns, post-synthesis estimate) |

The extra warnings compared with `stm_cntl` are pipeline tags used only for observation that are
now removed, and the note that the register file is implemented in registers.
