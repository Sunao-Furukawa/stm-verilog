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
│   ├── stm_sys.v         top level connecting everything (equivalent to vh/behave/sys.vst)
│   ├── stm_icache.v      instruction cache (section 8)
│   ├── stm_axi_master.v  memory requests of stm_cntl -> AXI4 master (section 8)
│   └── stm_axi_top.v     CPU with an AXI4 master port (stm_cntl + stm_regfile + stm_icache + stm_axi_master)
├── syn/                  logic-synthesis setups for Quartus / Vivado (see syn/README.md)
├── tb/
│   ├── tb_stm.v          testbench
│   ├── tb_stm_axi.v      testbench for stm_axi_top
│   └── axi4_mem_slave.v  AXI4 slave memory model (random waits / reordering, protocol checks)
├── bench/loop.s          loop benchmark (shows the effect of the instruction cache)
├── tests/                tests for the AXI4 version (I/O region, bus-error exceptions; section 8)
├── rtos/                 a small real-time OS (rtos.s) and a checker; see rtos/README.md
├── tools/
│   ├── asm.py            assembler (Python port of soft/asm.pl; use this one normally; adds SVC)
│   ├── asm64.pl          soft/asm.pl fixed for 64-bit Perl (for reference)
│   ├── mem2hex.py        mem.dat → $readmemh format
│   └── form_cmp.dat      display format used to compare against the C version
├── run_bup.ps1           full bup0/bup1 regression (Windows PowerShell)
├── run_bup.sh            the same (sh / Git Bash)
├── run_bup_axi.ps1       full regression of the AXI4 version (Windows PowerShell)
└── run_bup_axi.sh        the same (sh / Git Bash)
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
Later, an `SVC` instruction was added for the RTOS ([rtos/](rtos/README.md)), and a bug where pass 1
did not count `SETHI`/`RSR`/`WSR`/`RFE` was fixed (the output for existing files is unchanged).

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

## 8. AXI4 master version (`stm_axi_top`)

`stm_axi_top` is the complete CPU (core + register file) with an **instruction cache** and a
single **AXI4 master** port in place of `stm_memory`. Instructions and data both go through
this port; there is no data cache.

```
 stm_cntl (EXT_BUS=1) --IB_AD, IB_AD_NXT--> stm_icache --line fills--+
      ^  |  \                                                        v
      |  |   +---------------LBS_* (loads / stores)-------------> stm_axi_master <==AXI4==> m_axi_*
      |  v GR                                                     (32-bit data)
 stm_regfile
```

| Port | Description |
|---|---|
| `aclk`, `aresetn` | clock, active-low reset (treated as synchronous; deassert it synchronously to `aclk`) |
| `RESET_PC` | start address after reset |
| `m_axi_aw*`, `w*`, `b*`, `ar*`, `r*` | AXI4 master (32-bit data, 32-bit address, `ID_W`-bit IDs; no `*USER`/`*REGION`) |
| `PC`, `bus_error` | observation: current PC; sticky flag set by any SLVERR/DECERR response (load errors also raise an exception, see below) |

| Parameter | Default | Meaning |
|---|---|---|
| `ID_W`, `IF_ID`, `OP_ID` | 4, 0, 1 | AXI ID width; IDs used for instruction fetches and for loads/stores |
| `BYTE_SWAP` | 0 | byte-lane order (see below) |
| `ICACHE` | 1 | 1 = instruction cache, 0 = no cache (each fetch reads 8 bytes) |
| `IC_LINE_W` | 5 | cache line = 2^`IC_LINE_W` bytes (4–6: 16–64 bytes) |
| `IC_SET_W` | 7 | number of lines = 2^`IC_SET_W` (default 32 B × 128 = 4 KB) |
| `IO_EN`, `IO_BASE`, `IO_MASK` | 1, `F000_0000`, `F000_0000` | I/O region = addresses with `(addr & IO_MASK) == IO_BASE` (default: the top 256 MB); `IO_EN=0` removes it |

### Instruction cache (`rtl/stm_icache.v`)

* Direct-mapped, read-only. The data array is 64 bits wide (one entry = the 8 bytes the core
  fetches at a time); data and tag arrays are synchronous-read RAMs with one write port, so they
  map to FPGA block RAM. Only the valid bits are flip-flops.
* **Hits take no extra cycle.** The core now also outputs the address it will fetch next cycle
  (`IB_AD_NXT`), and the cache reads its RAM one cycle ahead with it. A hit is therefore answered
  in the same cycle as the original same-cycle `stm_memory`; code that stays in the cache runs
  at the original cycle count for instruction fetch.
* **Misses** fill the whole line with one WRAP burst starting at the requested 8 bytes. That
  pair goes to the core as soon as its two beats arrive (early restart), and each later pair is
  handed over as it arrives, so straight-line code does not wait for the end of the fill. Other
  hits resume when the fill has finished.
* A fill that was started is always completed, even if the core cancels the fetch. Requests are
  matched by address, so the cache does not need to know where the core's requests begin.
* The cache is not kept coherent with stores (see self-modifying code below).

### I/O region

Addresses in the I/O region are treated as device registers, where a read can have side effects:

* **Loads are not executed speculatively.** An I/O load waits in the A cycle until it is no longer
  behind an unsolved conditional branch, no older instruction is left in B or E (so none of them
  can still raise an interrupt), and every older store has been written (store buffer empty and
  no ST2 in the S unit). Only then does it go to the bus, so device accesses happen once and in
  program order. A held load waits only for older instructions, which never wait for it, so it
  cannot deadlock. Other loads are not affected.
* **Stores do not read first.** A store normally reads the word in the B cycle (to merge
  sub-word data); for the I/O region that read is skipped. Write whole words to I/O registers:
  in a sub-word store the other bytes become 0.
* **No instruction fetch.** The instruction cache does not fetch from the I/O region (so
  prefetching cannot touch devices); it hands the core the illegal instruction `0xE0000000`
  instead. Jumping there raises the illegal-instruction exception with the address in XPC.
* Accesses use `AxCACHE=4'b0000` (Device, non-bufferable).

One case is not covered: when an EX instruction issued in the same pair just before the I/O load
overflows, the load has already gone to the bus when the overflow interrupt cancels it.

### Bus errors

| Access with an error response (SLVERR / DECERR) | Result |
|---|---|
| Load, or the B-cycle read of a store | **data access exception**: interrupt code 3 (the code reserved for the unimplemented TLB), XPC = the instruction's address, **XLA = the accessed address**. The destination register is not written and the store is not performed |
| Instruction fetch | the 8 bytes are replaced by the illegal instruction `0xE0000000` and the line is not kept in the cache; executing it raises the illegal-instruction exception (code 1, XPC = its address). A speculative fetch is just discarded |
| Store write (B response) | only `bus_error`: the store has already completed in the CPU, so there is no precise way to report it |

`bus_error` is set in all three cases.

### What appears on the bus

| Access | Channel | Burst |
|---|---|---|
| Instruction fetch, `ICACHE=1` (line fill) | AR/R, `ARID=IF_ID`, `ARPROT=3'b100` (instruction) | WRAP, `ARLEN=2^(IC_LINE_W-2)-1` (8 beats by default), `ARSIZE=2`, starts at the requested 8 bytes |
| Instruction fetch, `ICACHE=0` (8 bytes = 2 instructions) | the same | INCR, `ARLEN=1`, 8-byte aligned |
| Load, and the B-cycle read of a store | AR/R, `ARID=OP_ID`, `ARPROT=3'b000` | single beat, 4-byte aligned |
| Store (ST2 from the store buffer) | AW/W/B, `AWID=OP_ID` | single beat, `WSTRB=4'hf` |

* Only whole 32-bit words are transferred: sub-word stores are merged into a word inside the
  CPU before ST2 writes it.
* The fetch and operand sides can each have one transaction outstanding. They share the AR
  channel (operand side has priority; once ARVALID is shown the choice is kept until
  ARREADY). R beats are routed by RID, so responses may come back out of order or interleaved.
* The operand side handles one request at a time and waits for its R data / B response before
  the next one, so loads and stores reach the bus in program order. A store counts as done
  only after its B response.
* `AxCACHE=4'b0011` (normal, non-cacheable, bufferable), or `4'b0000` (Device) in the I/O region.
  `AxLOCK=0`, `AxQOS=0`. `RREADY` and `BREADY` are always 1.
* Every response is registered (operand data in `stm_axi_master`, instructions in the cache
  RAM / fill registers) before it reaches the core: there is no combinational path from AXI
  inputs into `stm_cntl`.

### Changes to the core (`EXT_BUS` parameter of `stm_cntl`)

The core already had a handshake for cache misses (`RANDOM_FOR_OPCLH/IFRDY/IFCLH`). The AXI4
version reuses it as a "bus data has arrived" signal. With the default `EXT_BUS=0` the core is
exactly as before (the 128/128 regression and the cycle-by-cycle match with the C version are
unchanged); `stm_axi_top` sets `EXT_BUS=1`, which changes these things:

1. **ST2 waits for the bus.** In the original an ST2 always finished in one cycle; now it stays in
   OP-B until the write completes (`OP_B_FORWARDING` in 160-op-lb2).
2. **Store-to-load forwarding by the OP-B address.** The original made a load "hit" when the
   store buffer or the store in E held the same address, and supplied the data with a bypass in
   the B cycle (`BB_MEM_DATA`). With a bus a request can wait in OP-B for many cycles, by which
   time the instruction is no longer in B, so the data is now selected directly by `LBS_AD`
   (`OP_LBS_DATA` in 050-op-lb1). The same applies to the B-cycle read of a store.
3. **A stale fetch is cancelled when an unsolved BC is issued** (`CANCEL_IB` in 170-if-req).
   The fetch request for the target of an unsolved conditional branch is issued only once and
   is lost if the fetch unit is busy. The original never noticed, because its fetches always
   completed in the next cycle. With slow fetches the target queue went on filling from an old
   fetch, so wrong-path code was executed. Cancelling that old fetch frees the fetch unit, and the
   core then re-requests the target from `D_IF_AD` in the next cycle.
4. **I/O loads are held in A** (`AA_IO_LD_HOLD` in 060-g-srq) and **I/O stores skip their read**
   (`OP_B_IO_ST` in 050-op-lb1), as described under "I/O region". The region is set by the core
   parameters `IO_EN` / `IO_BASE` / `IO_MASK`.
5. **Data access exception on bus errors.** A new input `MEM_OP_ERR` comes with the read data;
   it sets `OP_B_INTCODE` to `INTCODE_TLB` (050-op-lb1). For that code the E cycle passes the
   address instead of the load result to `W_WDT1`, so W saves it in XLA, and a faulting store is
   not put into the store buffer (090-e-act).
6. **New ports** for the cache and the bridge: outputs `IB_VALID`, `IB_AD_NXT` (next-cycle
   `IB_AD`), `OP_B_NEW`, `OP_B_BUSREQ` and the input `MEM_OP_ERR`. In `stm_sys` the outputs are
   left unconnected and `MEM_OP_ERR` is tied to 0.

When the core cancels a load/store (branch misprediction, interrupt) after its AXI transaction
has started, `stm_axi_master` finishes the transaction and discards the result.

### Performance

Cycles to SUCCESS. `stm_sys` is the original same-cycle memory, i.e. the ideal case.

| Program | `stm_sys` | AXI, no cache | AXI, I-cache 4 KB | AXI random waits, no cache | AXI random waits, I-cache 4 KB |
|---|---|---|---|---|---|
| `bench/loop.s` (100 iterations, 9 loads + 1 store each) | 2,218 | 6,737 | **5,047** | 13,408 | **9,397** |
| all 64 bup programs (total) | 4,275 | 12,157 | **9,180** | — | — |

In `bench/loop.s` the cache cuts instruction-fetch bus reads from 1,208 to 6. What remains is
the loads and stores, which all go to the bus. The bup programs are short and run mostly on cold
misses, so they gain less.

### Points to be aware of

* **No data cache**: every load and store is a bus transaction, which is now the main cost.
* **Speculative reads outside the I/O region**: there, loads on a mispredicted path can reach the
  bus before they are cancelled (as in the original), and instruction prefetches and line fills
  can read past the end of the code. Put read-sensitive devices in the I/O region.
* **Self-modifying code** is not supported: the instruction cache does not see stores, and
  instruction fetches are not ordered against stores.
* **Store write errors** (B response) only set `bus_error` (see "Bus errors").
* **Byte order**: STM is big-endian (the byte at address 4n is the most significant byte).
  `BYTE_SWAP=0` puts the CPU's word on the bus unchanged, so a `$readmemh` word image can be used
  as is. `BYTE_SWAP=1` reverses the bytes so that the byte at address 4n+k is on
  `xDATA[8k+7:8k]` (the usual AXI byte-lane rule), for sharing memory byte-wise with
  little-endian masters or peripherals.

### Verification

* `iverilog -g2001 -Wall` compiles without warnings.
* `run_bup_axi.ps1` / `run_bup_axi.sh` run all 64 bup0/bup1 programs five ways — 4 KB cache
  with a no-wait slave; 4 KB cache with random waits, reordering and interleaving of read
  responses; the same with `BYTE_SWAP=1`; a 2-line × 16-byte cache (many replacements); no
  cache — 320/320 finish at SUCCESS.
* Stress run: the 64 bup programs and the 5 tests in `tests/` × 20 more seeds of the random
  slave, spread over five cache configurations (4 KB, 4 KB + `BYTE_SWAP`, 2 × 16 B, 4 × 64 B,
  none) = 1380/1380 pass.
  `bench/loop.s` also passes in every configuration tried.
* Tests for the new behavior, in `tests/` (self-checking; they end at SUCCESS). The slave model
  has a test device at `F000_0000` (register A returns how many times it has been read; register B
  returns the inverse of the last value written) and returns SLVERR for `E000_0000`–`EFFF_FFFF`:

  | Test | Checks |
  |---|---|
  | `io_order.s` | I/O loads on a mispredicted path never reach the device; a store to I/O does not read it; a load right after a store to the same I/O register reads the device after the write (not the forwarded value) |
  | `load_err.s` / `store_err.s` | error response → exception code 3 with the right XPC and XLA; destination register / memory unchanged |
  | `fetch_io.s` / `fetch_err.s` | jumping into the I/O region / to an address that returns an error → illegal-instruction exception with XPC = that address |

  `run_bup_axi.*` runs them (and `bench/loop.s` and the RTOS `rtos/rtos.s`) in all five configurations
  together with the bup programs: 355/355 pass. With the I/O protection switched off (`IO_EN=0`), `io_order.s` fails
  (the device is read twice on the mispredicted path), so the test does detect the problem.
* `tb/axi4_mem_slave.v` checks the master's protocol on every cycle (VALID held until READY with
  stable payload, WLAST matching the burst length, no 4 KB crossing, size ≤ bus width) and the
  testbench reports `AXIERR` on any violation; none were found.

### Running

```powershell
powershell -ExecutionPolicy Bypass -File run_bup_axi.ps1   # Windows PowerShell
sh run_bup_axi.sh                                          # sh / Git Bash
```

A single program:

```powershell
python tools/asm.py bench/loop.s 20000 -o mem.dat
python tools/mem2hex.py mem.dat mem.hex
iverilog -g2001 -I rtl -o axi.vvp tb/tb_stm_axi.v tb/axi4_mem_slave.v rtl/stm_axi_top.v rtl/stm_icache.v rtl/stm_axi_master.v rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v
vvp axi.vvp +HEX=mem.hex +PC=300 +CYCLES=20000 +RANDOM +SEED=5
```

`+RANDOM` turns on random waits and reordering in the slave, `+TRACE` prints every cycle, and
`+VCD` writes `tb_stm_axi.vcd`. Parameters are set on the `iverilog` line, e.g.
`-P tb_stm_axi.ICACHE=0`, `-P tb_stm_axi.IC_SET_W=4`, `-P tb_stm_axi.BYTE_SWAP=1`.
