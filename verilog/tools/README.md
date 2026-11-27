# tools/ — assembler and conversion tools

**English** | [日本語](README.ja.md)

Tools for running STM programs in the Verilog simulation or on an FPGA.
Only Python 3 is needed (Perl only if you use `asm64.pl`).

| File | Contents |
|---|---|
| `asm.py` | assembler (Python port of `soft/asm.pl`); use this one normally. Adds the `SVC` instruction for the RTOS |
| `asm64.pl` | `soft/asm.pl` with one line fixed so it works on 64-bit Perl (for reference) |
| `mem2hex.py` | converts the assembler output `mem.dat` into a `.hex` file in `$readmemh` format |
| `form_cmp.dat` | display format used to compare cycle by cycle against the C simulator |

## Usage

```sh
python tools/asm.py ../samples/tst.s 200 -o mem.dat     # assemble (200 = maximum cycles)
python tools/mem2hex.py mem.dat mem.hex                 # prints "PC=300 CYCLES=200"
vvp work/sim.vvp +HEX=mem.hex +PC=300 +CYCLES=200
```

In PowerShell 5, `>` writes UTF-16, so give `asm.py` its output file with `-o`
(`mem2hex.py` also reads UTF-16 input).
Why `asm.py` / `asm64.pl` exist is explained in [../README.md §5](../README.md#5-decisions-that-had-to-be-made-differences-from-the-original);
the changes made to `asm.py` and notes on writing for it are in [../rtos/README.md](../rtos/README.md#assembler-changes-toolsasmpy).

## File formats

* **`mem.dat`** (output of `asm.py`): line 1 is the start address (the `main` label, hex), line 2 the
  number of cycles, followed by `adr:` lines (hex byte address) and data lines with one hex word each.
  Lines starting with `#` are comments (`# label=address`).
* **`.hex`** (output of `mem2hex.py`): only `@` lines (**word address** = byte address / 4) and lines
  with one hex word. `$readmemh` reads it as it is.

## Where the Verilog side uses them

The tools in this folder are Python / Perl, so they do not have the per-line comments the Verilog
files have (the top of each file describes its usage and formats). The Verilog that consumes their
output has a comment at the end of every line saying what it does and what it becomes after
synthesis (see [../README.md §2 "Comments in the sources"](../README.md#comments-in-the-sources)).

| Tool output | Verilog that reads it (file: line) | What the comments say |
|---|---|---|
| `.hex` (simulation) | `tb/tb_stm.v`, `tb/tb_exp.v`: `$readmemh(hexfile, u_sys.u_mem.mem)`; `tb/tb_stm_axi.v`, `tb/tb_noio.v`: `$readmemh(hexfile, u_mem.mem)` | loads straight into the memory array (hierarchical reference); in the AXI4 version with `BYTE_SWAP=1` the bytes of every word are reversed afterwards |
| `.hex` (initial value of the memory model) | `rtl/stm_memory.v`: `INIT_HEX` and `initial` | clears every word, then reads the file; a simulation-only model |
| `.hex` (FPGA) | `syn/vivado/stm_prog_ram.v`: `INIT_FILE` and `initial` | becomes the block RAM's initial value (INIT_xx) in the bitstream at synthesis; passed as the second argument of `create_bd.tcl` |
| `PC=` / `CYCLES=` printed by `mem2hex.py` | the testbenches' `+PC=` / `+CYCLES=` (the `$value$plusargs` lines) | start address (-> `RESET_PC` -> reset value of the PC FFs) and the cycle limit |
| `form_cmp.dat` | `tb/tb_stm.v`, `tb/tb_exp.v`: the `+CTRACE` `$display` | prints in the same order as the C version's `siml.res` (PC, stage FWDs, I0/I1, IB_AD, LBS_AD, W_WDT1/2, PSW_CC, NIP_A/B); every value is a hierarchical reference to an internal net of `stm_cntl` |
| `SVC n` (`E00000nn`) | `rtl/stm_fmt_ls_ex.vh`: `is_legal_opc`; `rtl/ch/015_d_i01.vh`: `I0_IS_LEGAL` | an instruction word whose top 4 bits are `1110` is judged illegal and raises an illegal-instruction exception |
