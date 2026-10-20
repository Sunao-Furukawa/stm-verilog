# Logic synthesis of the STM CPU core

**English** | [日本語](README.ja.md)

Ready-to-run synthesis setups for the CPU core `stm_cntl` (with its two `stm_exu` ALUs), and for
the complete CPU with an AXI4 master port, `stm_axi_top` (see the last section).

| Directory | Tool | Contents |
|---|---|---|
| `quartus/` | Intel/Altera Quartus II (tested with 13.0sp1) | projects (`stm_cntl.qpf` / `.qsf`, `stm_axi_top.qpf` / `.qsf`) and timing constraints (`stm_cntl.sdc`, `stm_axi_top.sdc`) |
| `vivado/` | AMD/Xilinx Vivado (tested with 2022.2) | batch synthesis scripts (`synth.tcl`, `synth_axi.tcl`) and constraints (`stm_cntl.xdc`, `stm_axi_top.xdc`), a script that builds an IP Integrator block design (`create_bd.tcl`, last section) |

## What is synthesized

Only `stm_cntl` is synthesized, as the original author also did for the VHDL version.
`stm_regfile` and `stm_memory` are **simulation models** and are left out:

* `stm_memory` has three asynchronous (same-cycle) read ports, so it cannot be mapped to FPGA
  block RAM; as is, the whole memory would become flip-flops and multiplexers. Running on real
  hardware needs a redesigned memory interface.
* As a result `stm_cntl` brings all register-file and memory signals out to its ports
  (516 pins). Quartus therefore targets a large-package device, and Vivado synthesizes
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
| Quartus II 13.0sp1, Cyclone IV E EP4CE115F29C7 (full compile) | 5,514 LEs, 1,622 registers, 516 pins | met at 25 MHz (setup slack +3.3 ns). An earlier build (before the ports for the AXI4 version were added) reached Fmax 38.6 MHz when constrained to 50 MHz |
| Vivado 2022.2, Artix-7 xc7a100tcsg324-1 (synthesis only) | 3,034 LUTs, 1,623 FFs | met at 25 MHz (WNS +11.2 ns, post-synthesis estimate) |

The exception to the half-cycle rule is `IB_AD_NXT` (the next fetch address, used by the AXI4
version's instruction cache), which gets a 5 ns output budget: it is combinational from the
fetch-handshake inputs and goes straight to the cache RAM's address register, so half a cycle at
both ends would leave no time for the path itself.

Warnings that remain are harmless: truncation of C-style unsized constants (e.g. `? 1 : 0`)
and decoded fields / pipeline tags that are never read and get optimized away.

## The CPU with an AXI4 master (`stm_axi_top`)

`stm_axi_top` (see [../README.md §8](../README.md#8-axi4-master-version-stm_axi_top)) contains
`stm_cntl`, `stm_regfile`, the instruction cache `stm_icache` and the bridge `stm_axi_master`, so
it is a complete CPU whose only interface is the AXI4 master port (281 pins including the
observation outputs `PC` / `bus_error`). The instruction cache (4 KB by default) maps to block
RAM; the register file is built from flip-flops (it has four same-cycle read ports).

```sh
cd verilog/syn/quartus
quartus_sh --flow compile stm_axi_top
cd ../vivado
vivado -mode batch -source synth_axi.tcl        # reports in vivado/reports_axi/
```

| Tool / device | Resources | Timing |
|---|---|---|
| Quartus II 13.0sp1, Cyclone IV E EP4CE115F29C7 (full compile) | 8,593 LEs, 2,562 registers, 35,328 memory bits, 281 pins | met at 25 MHz (setup slack +2.0 ns) |
| Vivado 2022.2, Artix-7 xc7a100tcsg324-1 (synthesis only, out of context) | 4,875 LUTs, 2,564 FFs, 1.5 block RAM tiles | met at 25 MHz (WNS +10.4 ns, post-synthesis estimate) |

The extra warnings compared with `stm_cntl` are pipeline tags used only for observation that are
now removed, address bits the cache does not use, and the note that the register file is
implemented in registers.

## IP Integrator block design (`vivado/create_bd.tcl`)

A script that builds a project using `stm_axi_top` in IP Integrator. Tested with Vivado 2022.2.

```sh
cd verilog
python tools/asm.py ../samples/hello_uart.s 1000 -o work/hello_uart.dat     # prints Hello World on the UART
python tools/mem2hex.py work/hello_uart.dat work/hello_uart.hex
cd syn/vivado
vivado -mode batch -source create_bd.tcl                                            # memory starts as zeros
vivado -mode batch -source create_bd.tcl -tclargs xc7a100tcsg324-1 ../../work/hello_uart.hex   # part and program
```

It creates `vivado/stm_bd/stm_bd.xpr`. From the Tcl console of the GUI you can also run
`cd <this folder>; set argv {xc7a100tcsg324-1 ../../work/hello_uart.hex}; source create_bd.tcl`.

Contents of the block design `stm_system`:

```
sys_clk (100 MHz) ─▶ Clocking Wizard (25 MHz) ─▶ aclk of everything
reset_n (active low) ─▶ Clocking Wizard, Processor System Reset ─▶ aresetn
Constant 0x300 ─▶ cpu/RESET_PC
cpu (stm_axi_top, module reference) ──m_axi──▶ AXI SmartConnect
      M00 ─▶ AXI BRAM Controller + stm_prog_ram   0x0000_0000–0x0000_1FFF (8KB)
      M01 ─▶ AXI UART Lite (115200 baud)         0xF000_0000–0xF000_FFFF
bus_error, uart (rxd / txd) ─▶ top-level ports
```

* The CPU is placed from the RTL as a **module reference** (*Add Module*). A module reference
  needs the include files to be in the project as well, so `rtl/*.vh` and `rtl/ch/*.vh` are added.
  `rtl/ch/*.vh` are parts of the body of `stm_cntl` and are syntax errors on their own, so their
  `used_in` is set to empty: they are not parsed alone, only read through `` `include ``.
* The program memory is [`vivado/stm_prog_ram.v`](vivado/stm_prog_ram.v) (a module reference)
  instead of the Block Memory Generator, because a Block Memory Generator driven by an AXI BRAM
  Controller in a block design would not accept an init file. `stm_prog_ram` reads the output of
  `tools/mem2hex.py` as it is with `$readmemh` and maps to block RAM (two RAMB36 for 8KB).
* The UART Lite is in the CPU's I/O region (`0xF000_0000`–). Loads there are not speculative, so
  reading the RX FIFO (which consumes data) is safe. Registers: +0x0 RX FIFO, +0x4 TX FIFO,
  +0x8 status (bit 3 = TX FIFO full), +0xC control. Write whole words.
* [`samples/hello_uart.s`](../../samples/hello_uart.s) checks the status register and writes one
  character at a time to `F000_0004` while the TX FIFO has room, prints `Hello World` (with CR LF)
  and then stops in an endless loop. `samples/hello.s` writes to the testbench console
  (`F000_0008`) instead, so it prints nothing on a real UART. The testbenches have no UART, so a
  simulation of `hello_uart.s` shows nothing and ends with TIMEOUT (on the AXI4 version, the 13
  bytes of `Hello World
` were checked to be written to `F000_0004`, with exactly 13 status reads).
* Pin assignments for `sys_clk`, `reset_n`, `uart_rxd`, `uart_txd` and `bus_error` depend on the
  board; add an XDC before implementation.

Checked: the project was created with `hello.hex` and synthesized with no errors or critical
warnings. `hello.hex` is loaded into the program memory, which maps to block RAM. It has not been
run on hardware.

> With Vivado 2022.2, creating the block design (`create_bd_design`) occasionally stopped with an
> error about Vivado's own IP scripts (`couldn't read file ...`, `Failed to load feature
> 'ipintegrator'` and so on). This is unrelated to the script; running it again works.

### Using *Add Module* in your own project

If you place `stm_axi_top` with *Add Module* in a block design of your own project instead of
using `create_bd.tcl`, you may get this error:

```
[filemgmt 56-591] Given include File '.../verilog/rtl/ch/130_a_act.vh' needs to be addded to the project in order to use it as an RTL module.
```

A module reference needs every file read through `` `include `` to be part of the project.
`stm_cntl.v` includes `rtl/*.vh` (4 files) and `rtl/ch/*.vh` (23 files). With the project open,
enter the following in the Tcl Console (adjust the `rtl` path to your setup):

```tcl
set rtl C:/work/stm-verilog/verilog/rtl
set vh_ch [glob $rtl/ch/*.vh]
set vh    [concat [glob $rtl/*.vh] $vh_ch]
add_files -norecurse $vh
set_property file_type {Verilog Header} [get_files $vh]
set_property used_in {} [get_files $vh_ch]
set_property include_dirs [list $rtl] [current_fileset]
update_compile_order -fileset sources_1
```

* `rtl/*.vh` and `rtl/ch/*.vh` are added to the project as Verilog Headers.
* `rtl/ch/*.vh` are pieces of the body of `stm_cntl` and are not valid Verilog on their own. If
  they are only added, Vivado parses each of them and reports 23 CRITICAL WARNINGs
  (`Syntax error near 'assign'`), so their `used_in` is set to empty to stop that. They are still
  read through `` `include ``.
* `stm_cntl.v` includes files with paths relative to `rtl/` (`"ch/010_d_pre.vh"`), so `rtl/` is
  added to the include search path.

In the GUI: add the 27 `.vh` files with *Add Sources*, check that their Type is *Verilog Header*,
uncheck everything under *Used In* in the *Source File Properties* of the 23 files in `ch/`, and
add `verilog/rtl` to *Settings → General → Verilog options → Include Search Paths*.
