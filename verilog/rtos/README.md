# STM-RTOS

**English** | [日本語](README.ja.md)

A small real-time OS for STM-1.2. A single assembly source, [`rtos.s`](rtos.s), assembled with
`tools/asm.py`, contains the kernel, four demo tasks and a self-check of the result.

## Features

* **Four tasks with fixed-priority preemptive scheduling** (a smaller number is a higher
  priority). When a higher-priority task becomes ready, the kernel switches to it at once.
  Tasks of equal priority take turns with `YIELD`.
* Tasks run in **user mode** and talk to the kernel through **system calls**.
* Four **counting semaphores** and two **mailboxes** (each queues up to four messages). If a
  task is waiting to receive, a sent message is handed to it directly.
* If a task raises an **exception** (overflow, illegal instruction, compare stop, or a bus error
  on the AXI4 version), the kernel terminates just that task and records it in the log.
* When all tasks have finished, the kernel calls the application's exit handler (`APP_DONE`).
  If only waiting tasks remain, it stops at `DEADLOCK` (0x3E0).

STM has **no timer interrupt and no external interrupts** (the only interrupts are illegal
instruction, compare stop, overflow, and bus error on the AXI4 version). There is therefore no
time-based switching (time slicing, `sleep`); task switches happen only at system calls.

## System calls

A task calls the kernel with `SVC n`. `SVC` is an instruction added to `tools/asm.py`; it
assembles to the undefined instruction `E00000nn`. Executing it raises an illegal-instruction
exception (INTTYPE=1), so the kernel treats it as a system call when the top 8 bits of the
instruction word at XPC are `E0`, and as a genuine illegal instruction otherwise.

Arguments are in GR1 and GR2, the result is returned in GR1. All other GRs are preserved.

| No. | Name | Arguments | Result |
|---|---|---|---|
| 0 | EXIT | | (does not return) |
| 1 | YIELD | | |
| 2 | SEM_WAIT | GR1 = semaphore (0–3) | 0 / -1 (bad ID) |
| 3 | SEM_SIGNAL | GR1 = semaphore | 0 / -1 |
| 4 | SEND | GR1 = mailbox (0–1), GR2 = message | 0 / -1 (bad ID, full) |
| 5 | RECV | GR1 = mailbox | message / -1 |
| 6 | LOG | GR1 = value | (appended to the log at 0xE00) |
| 7 | GETTID | | task number (0–3) |

`SEM_WAIT` blocks while the count is 0, and `RECV` blocks while the mailbox is empty.

## How it works

```
 task (user mode)               kernel (kernel mode)
   SVC n  ──illegal insn──▶   TRAP (TBR=0x440)
                               save GR0-15, XPC, XPSW to the TCB (SVR0 = current TCB)
                               check INTTYPE and the insn word, jump to table 0x400+4n
                               ...handle the call...
                               SCHED: pick the highest-priority ready task
   ◀──────── RFE ───────────  DISPATCH: restore GRs, XPC, XPSW from the TCB
```

* **TCB** (0x60 bytes): GR0–15, PC, PSW, state (dormant / ready / waiting), priority, address of
  the object being waited on, task number.
* **Saving registers** follows the method described in the architecture document
  (`doc/japanese/arch-details01`): `WSR 9,15` moves GR15 to SVR1, `RSR 15,8` loads SVR0 (the
  current TCB) into GR15, and then the GRs are stored one by one. Tasks can use all 16 GRs.
* **There are no wait queues.** To wake a task, the kernel scans the four TCBs and picks the
  highest-priority task (the lowest number on a tie) waiting on that object.
* Tasks run with USER=1 in the PSW, so a privileged instruction (RSR/WSR/RFE) in a task raises an
  illegal-instruction exception and the task is terminated.

### Memory map (4KB)

| Address | Contents |
|---|---|
| 0x300 | Reset (`main`). 0x3D0 `DEAD`, 0x3E0 `DEADLOCK`, 0x3F0 `SUCCESS` |
| 0x400– | System call jump table (8 words) |
| 0x440– | Trap entry and kernel |
| 0x900– | User tasks (T0 0x900, T1 0x980, T2 0xA00, T3 0xA80) |
| 0xB00– | Exit handler after all tasks finish (checks the log) |
| 0xC00–0xD7F | 4 TCBs |
| 0xD80–0xE7F | Kernel variables, semaphores, mailboxes, log (cleared at boot) |
| 0xF00– | Task table (entry address, priority) |
| 0xF40– | Expected log |

## Demo (self-checking)

The four tasks below each record values with `LOG`; at the end the sequence is compared with
the expected values, and on a match the CPU stops at `SUCCESS` (0x3F0).

| Task | Priority | Behaviour |
|---|---|---|
| T0 | 1 | Receives three messages from mailbox 0 (blocking each time), then signals semaphore 0 |
| T1 | 2 | Sends 0x11, 0x22, 0x33 (each send switches to the higher-priority T0), then sends 0x44 and 0x55 (no receiver, so they are queued) |
| T2 | 3 | Alternates with T3 using `YIELD`, signals semaphore 1 to wake T3, and finally overflows on purpose and is terminated by the kernel |
| T3 | 3 | Waits on semaphore 1, receives the two queued messages, and checks that a bad ID returns -1 |

Expected log (19 words):

```
A0 B0 11 B1 22 B2 33 B3 B4 C0 D0 C1 C2 C3 D1 44 55 C4 E4
```

The final `E4` is the kernel's record of T2's overflow exception (`E0` + INTTYPE 4).
T0 and T1 also check that GR10 is preserved across system calls.

## Running

In the `verilog` folder:

```sh
python tools/asm.py rtos/rtos.s 20000 -o work/rtos.dat
python tools/mem2hex.py work/rtos.dat work/rtos.hex
# stm_sys (ideal memory): about 7,500 cycles
iverilog -g2001 -I rtl -o work/sim.vvp tb/tb_stm.v rtl/stm_sys.v rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v rtl/stm_memory.v
vvp work/sim.vvp +HEX=work/rtos.hex +PC=300 +CYCLES=20000
# AXI4 version (4KB instruction cache, random waits): about 28,000 cycles
iverilog -g2001 -I rtl -o work/axi.vvp tb/tb_stm_axi.v tb/axi4_mem_slave.v rtl/stm_axi_top.v rtl/stm_icache.v rtl/stm_axi_master.v rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v
vvp work/axi.vvp +HEX=work/rtos.hex +PC=300 +CYCLES=400000 +RANDOM +SEED=1
```

`RESULT: stop at PC=000003f0 ... -> OK` means success. `run_bup_axi.sh` / `run_bup_axi.ps1` also
run this RTOS in all five configurations together with bup and the other tests.

### Verification

* `stm_sys` (no cache misses): passes (7,548 cycles).
* AXI4 version: no waits, plus 20 seeds of random waits and reordered responses in each of four
  configurations (4KB cache, the same with `BYTE_SWAP=1`, a 2-line 16-byte cache, no cache):
  81/81 pass.
* With `stm_sys` in `+RANDOM` mode (random cache misses, like `stmsiml -r` of the C version),
  1 of 20 seeds (`SEED=7`) stops at `DEADLOCK`. This is not an RTOS problem but a bug in the
  original design: when an instruction fetch is late, instructions on the wrong side of a
  resolved conditional branch are executed instead of being cancelled. It is the same problem as
  "cancel the old fetch when an unresolved BC is issued" in
  [../README.md §8](../README.md); that fix (`CANCEL_IB`) was applied only to the AXI4 version
  (`EXT_BUS=1`), so the random mode of `stm_sys` still shows it.

## Hardware bugs and the workarounds

While writing the RTOS, two bugs were found in the CPU core. Both are in logic translated as-is
from the original CHDL, so they are bugs of the original STM-1.2 design. The regression tests (bup) contain no instance of these
patterns, so they had not shown up before. The CPU core is left unchanged so that it stays
cycle-identical with the C version; the RTOS avoids the patterns instead.
[`check_bc.py`](check_bc.py) checks a source statically:

```sh
python rtos/check_bc.py rtos/rtos.s      # "conflicts: 0" means OK
```

### 1. Results of instructions cancelled by a misprediction are bypassed

When a conditional branch's CC is not ready yet, STM issues the following instructions using a
static prediction (backward taken, forward not taken). In the cycle the misprediction is
detected, the first issue group of the correct path (up to two instructions) is in the D cycle,
and **the results of the instructions being cancelled in the A cycle are bypassed to it**. The
operand bypass from D to A (140_d_dat.vh) looks only at the write flags (`A_WE2` and so on), not
at the cancel signal (`A_V_NOCAN`).

An actual case:

```
K_SEND:  L   1,13(4)
         CU  1,%2
         BGE K_ERR        # K_ERR is backward, predicted taken -> K_ERR's O 1,0,%-1 issues first
         SL  1,1,%5       # after the misprediction, this SL got GR1 = -1 (the cancelled O's result)
         ...
K_ERR:   O   1,0,%-1
```

Workarounds (checked by `check_bc.py`):

* Make branches to error handling **forward** branches, so they are not followed speculatively.
* For each branch, the first two instructions on one side must not read a register written by
  the first four instructions on the predicted side. (Only one group of two instructions is in
  A at cancel time; four leaves a margin.)

### 2. WSR's GR and a store's base register do not wait for a load

The A-cycle interlock that detects operands not yet available (`A_EAB`, 060_g_srq.vh) only
covers instructions that write a GR (`A_WE1`, `A_WE2`) or set the CC. WSR, stores and J write no
GR, so they use the old register value without waiting for a preceding load.

```
L   1,15(40)
WSR 5,1          # XPC receives GR1 from before the load
```

Workaround: copy the loaded value with an EX instruction that writes a GR (`O 1,1,%0`) before
using it. EX instructions do interlock, and their result is bypassed correctly.

## Assembler changes (`tools/asm.py`)

* Added the **`SVC n`** instruction (`E00000nn`, n in hex, 0–FF).
* The original `asm.pl` did not count `SETHI`, `RSR`, `WSR` and `RFE` in pass 1 (which assigns
  label addresses), so labels after them (up to the next `EQU`) got wrong addresses. This is
  fixed. The output for all 74 existing files in bup0/bup1/samples/tests/bench is unchanged
  character for character (they all put an `EQU` after such instructions).

Notes on writing for asm.py (same as the original asm.pl):

* Start instructions at the beginning of the line (pass 1 recognizes them there). Put one label
  per line, on its own.
* Put an `EQU` between data lines and a following branch instruction (pass 2 resets the address
  to 0 on a data line). Do not put comments after data lines.
* Do not use `RFE` inside a label name, and do not end the name of a `J` target label with `B`
  (both are mistaken for other instructions).
