# Verilog HDL 2001 version of the STM-1.2 hardware description

**English** | [日本語](README.ja.md)

This directory contains the CHDL sources (`*.ch`) and C headers (`*.h`) from `hard/`, translated
into Verilog HDL 2001. The original files are left untouched.

## 1. The original description (CHDL)

STM is a 32-bit RISC CPU that issues up to two instructions per cycle (2-way superscalar).
Its hardware is written in **CHDL**, a small home-grown HDL whose statements are essentially C expressions:

| CHDL               | Meaning |
|--------------------|---------|
| `NAME = expr`      | A combinational net |
| `NAME := expr`     | Assignment to a flip-flop (FF); the value changes at the next clock |
| `-` inside a name  | An ordinary character (`DD-RAD1` is a single name) |
| after `#`          | Comment (`#ifndef VHDL` and the like are cpp directives) |

`soft/chc` + `soft/perlcmd1` translate CHDL into C to build the cycle simulator `stmsiml`.
In that process `A := expr` becomes `A_NEW = expr;`, and FFs are updated at the end of each
cycle with `A = A_NEW;`. The `*.h` files are the macros prepended to that C source
(bit-field extraction, adders, etc.) and the ALU function `exu()`.

So that the same sources can also be translated to VHDL (for Alliance) by the tools in `vh/`,
some places use `#ifdef VHDL` to switch between a C-style and a VHDL-style formulation.

## 2. Files

```
verilog/
├── rtl/
│   ├── stm_const.vh      <- hard/const.h      constants (opcodes, interrupt codes, system register numbers)
│   ├── stm_defs.vh       <- hard/defs.h + vdefs.h  macros → functions (sign extension, cc_match, build_psw, adders)
│   ├── stm_fmt_jb.vh     <- hard/fmt-jb.h     field-extraction functions for JB / privileged instructions
│   ├── stm_fmt_ls_ex.vh  <- hard/fmt-ls-ex.h  field-extraction functions for LS / EX instructions, is_legal_opc
│   ├── stm_exu.v         <- hard/exu.h        ALU (C function exu() → module)
│   ├── stm_cntl.v        CPU core: declarations + `include of ch/*.vh + FF update
│   ├── ch/010_d_pre.vh … 210_g_bc.vh   <- one file per hard/*.ch
│   ├── stm_regfile.v     <- GR[] in 045-g-ram.ch  (16 general-purpose registers)
│   ├── stm_memory.v      <- Mem[] in 045-g-ram.ch (memory model for simulation)
│   └── stm_sys.v         top level connecting everything (equivalent to vh/behave/sys.vst)
├── tb/tb_stm.v           testbench
├── tools/
│   ├── asm.py            assembler (Python port of soft/asm.pl; use this one normally)
│   ├── asm64.pl          soft/asm.pl fixed for 64-bit Perl (for reference)
│   ├── mem2hex.py        mem.dat → $readmemh format
│   └── form_cmp.dat      display format used to compare against the C version
├── run_bup.ps1           full bup0/bup1 regression (Windows PowerShell)
└── run_bup.sh            the same (sh / Git Bash)
```

The `ch/*.vh` files are Verilog fragments, not stand-alone modules: they are pulled into
`module stm_cntl` with `` `include `` (pass `-I rtl` to the compiler and do not list `.vh`
files on the command line).

## 3. Translation rules

| CHDL / C                                   | Verilog 2001 |
|--------------------------------------------|--------------|
| `DD-RAD1 = expr`                           | `assign DD_RAD1 = expr;` |
| `PC := expr`                               | `assign PC_NEW = expr;` and `always @(posedge clk) PC <= PC_NEW;` |
| names containing `-`                       | `-` → `_` (same rule as the VHDL translator) |
| `0xdead0a0a`                               | `32'hdead0a0a` |
| macros `ls_store(i)`, `cc_match(cc,m)` …   | `function`s with the same names |
| `exu(opc,x,y,&cc,&z,&intr)`                | instances of `stm_exu` (one for the A cycle, one for the E cycle) |
| `GR[..] :=`, `Mem[..] :=`                  | external modules `stm_regfile` / `stm_memory` |
| `#ifndef VHDL … #else … #endif`            | the C side (the one that was actually verified) is used; the VHDL side is kept as a comment |
| `#if 0 … #endif`                           | disabled in the original too; kept as a comment |
| bit numbering (MSB = bit 0)                | converted to the usual `[31:0]` (LSB = bit 0); `bit_ext(i,s,n)` = `i[31-s -: n]` |

Bit widths are not written in the original sources, so they were taken from the tables used
by the VHDL translator, `vh/prop.tab` / `vh/assi.tab`.

**Evaluation order**: when CHDL is turned into C, statements run in the order they are written,
so order matters in principle (a net must be defined before it is used). Every `.ch` file was
checked and all nets appear in define-before-use order, so replacing them with order-independent
Verilog continuous assignments does not change the behavior.

**Reset**: `rst=1` clears all FFs to 0 and sets only `PC` to `RESET_PC`. This matches the
C version, which loaded the start address into PC and started everything else at 0; since
`START_TRIGGER_BAR=0`, instruction fetch begins in the first cycle.

Japanese explanatory comments (marked `【解説】`) are included throughout the RTL.

## 4. What the circuit does (role of each .ch file)

The pipeline is **IF → D → A → B → E → W**. Up to two instructions are issued in D and
dispatched to the LS pipe (loads/stores, operations with a memory operand), the EX pipe
(register operations), and JB (branches).

| File | Contents |
|---|---|
| 010-d-pre | Picks the next two instructions I0/I1 from the instruction queues IWQ-A/B (6 words each). Branch prediction keeps two paths; `EID` selects which one is used |
| 015-d-i01 | Field decoding of I0/I1 |
| 020-d-iss | Whether each instruction is LS/EX/JB/privileged, and which registers it reads and writes |
| 030-d-sec | Decides whether the second instruction can be issued together (CC/register dependencies, pipe conflicts) and dispatches to ILS/IEX/IJB |
| 035-d-ixx | Field decoding of ILS/IEX/IJB |
| 040-d-bra | Branches: kind (BA/JA/BL/JL/BC), whether a conditional branch is already resolved, backward branches predicted taken, target address DD-TGT |
| 045-g-ram | Register file and memory (separate modules in Verilog) |
| 050-op-lb1 | Outputs of the S unit (operand cache), cancellation on interrupts / branch mispredictions, address-compare interrupt |
| 060-g-srq | Per-stage valid flags, detection of operands not yet available in the A cycle (A-EAB), priority of requests to the SU |
| 070-g-ilk | Interlock conditions and per-stage advance signals (D/A/B/E-FWD) |
| 080-w-act | W cycle: update of system registers, PC and PSW; interrupt handling |
| 090-e-act | E cycle: LS-pipe ALU, interrupt priority, hand-off to W, store buffer STB |
| 100-b-dat | B cycle: selection of operands / load data, including bypasses |
| 110-b-act | B → E state transition; byte/halfword opcode determined from the low address bits |
| 120-a-dat | A cycle: EX-pipe EXU, address generation (EAG), system register reads |
| 130-a-act | A → B state transition |
| 140-d-dat | Operands passed from D to A; bypass selection from each stage |
| 150-d-act | D → A state transition |
| 160-op-lb2 | Next state of the S unit (WAIT/B states) |
| 170-if-req | Address/ID of instruction-fetch requests |
| 180-if-lbs | Instruction-fetch responses (including cache-miss emulation) |
| 190-if-stm | Instruction-fetch state machine and NIP (position of the next instruction in the queue) |
| 200-if-iwq | Shifting/filling of the instruction queues IWQ |
| 210-g-bc | Global FFs holding the resolution state of conditional branches (G-BC-*) |

## 5. Decisions that had to be made (differences from the original)

Wherever the C and VHDL formulations disagree, the **C version** was followed. The C version
is the one actually verified by the regression tests (`samples/subbup`), and the verification
below confirms agreement with it.

1. **`is_legal_opc`** (fmt-ls-ex.h): the VHDL expression ignores user mode and uses slightly
   different instruction ranges (a simplified version). The C version is used.
2. **`WW-STATECHANGE`** (050-op-lb1.ch): the C version means "WSR writes system register 0–3
   (PSW etc.)", while the VHDL version has the opposite condition (4 and above). The C version is used.
3. **Register file / memory**: in the C version `GR[..] :=` writes immediately and is visible to
   reads in the same cycle (write-through). `stm_regfile` / `stm_memory` reproduce this with read bypasses.
4. **Undefined EXU behavior**: where the C version leaves a value unset (undefined opcodes, cc of
   byte operations) the output is 0. Shift amounts of 32 or more (undefined behavior in C) give
   0 for SL/SRL and sign fill for SRA.
5. **Random cache-miss emulation** (`random()`): turned into input ports
   `RANDOM_FOR_OPCLH/IFRDY/IFCLH`. Tied to 1 the cache always hits; the testbench's `+RANDOM`
   gives the equivalent of the C version's `stmsiml -r`.
6. **Simulation probes** (`E-STAT` etc.) are kept as wires.

The original assembler `soft/asm.pl` assumes 32-bit Perl; with today's 64-bit Perl, negative
displacements come out corrupted, e.g. `80aeffff00000000fefc`. A copy with that one mask
computation fixed is provided as `tools/asm64.pl`.

In addition, Windows Perl builds (Strawberry Perl etc.) can fail inside folders whose path
contains Japanese characters with an error like
`Can't open perl script ...: No mapping for the Unicode character exists in the target multi-byte code page.`
For this reason the assembler was ported to Python as `tools/asm.py`, which is used by default.
It produces the same output as `asm64.pl` for all 67 files in bup0/bup1/samples.

## 6. Verification

* Compiles with `iverilog -g2001 -Wall` without warnings.
* **Regression tests**: all 64 programs in `bup0` / `bup1` were run both without cache misses and
  with random cache misses; 128/128 finish at SUCCESS (PC=0x3F0).
* **Cycle-by-cycle comparison with the C version**: the original C simulator (`stmsiml`, generated
  by `soft/chc`) was run under a RISC-V cross compiler + QEMU. For 65 programs (all 64 in
  bup0/bup1 plus `samples/tst.s`), the PC, the FWD signal of each stage, I0/I1, IB-AD, LBS-AD,
  W-WDT1/2, PSW-CC and NIP-A/B were compared every cycle → **identical in every cycle**.
  (Random mode was not compared cycle by cycle, because its random sequence differs from C's `random()`.)

## 7. Usage

Requirements: Python 3 and Icarus Verilog (iverilog / vvp). Perl is not needed.

### Full regression

Windows PowerShell (in the `verilog` folder):

```powershell
powershell -ExecutionPolicy Bypass -File run_bup.ps1
```

sh, e.g. Git Bash:

```sh
sh run_bup.sh
```

### Running a single program

```powershell
python tools/asm.py ../samples/tst.s 200 -o mem.dat
python tools/mem2hex.py mem.dat mem.hex          # prints "PC=300 CYCLES=200"
iverilog -g2001 -I rtl -o sim.vvp tb/tb_stm.v rtl/stm_sys.v rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v rtl/stm_memory.v
vvp sim.vvp +HEX=mem.hex +PC=300 +CYCLES=200 +TRACE
```

* Write the assembler output to a file with `-o`. PowerShell 5's `>` saves in UTF-16
  (`mem2hex.py` can read UTF-16 too, but `-o` is the reliable way).
* `+RANDOM` (+`SEED=n`) enables cache-miss emulation; `+CTRACE` prints in the same format as the
  C version's `siml.res`.
