# stm-verilog

**English** | [日本語](README.ja.md)

A translation of the hardware description of **STM-1.2** (a 2-way superscalar 32-bit RISC CPU,
1995) from CHDL into **Verilog HDL 2001**. The repository contains the complete original
distribution together with the translated Verilog.

## Contents

| Path | Description |
|------|-------------|
| `verilog/` | **Verilog 2001 version** (newly added). See [verilog/README_en.md](verilog/README_en.md) for details |
| `hard/` | Original hardware description (CHDL `*.ch` files and C headers `*.h`) |
| `soft/` | Original tools (CHDL-to-C translator, assembler, instruction-set simulator) |
| `vh/` | Original CHDL-to-VHDL translator and VHDL models |
| `bup0/`, `bup1/` | Assembly programs for the regression tests |
| `samples/`, `work/` | Samples and a working directory |
| `doc/` | Original documentation (English / Japanese) |

## Verification of the Verilog version

* Compiles with `iverilog -g2001 -Wall` without warnings
* All 64 programs in `bup0` / `bup1` × (no cache misses / random cache misses) = 128/128 pass
* Every internal state compared cycle by cycle against the original C simulator over 65 programs: identical

## Running

Requires Python 3 and Icarus Verilog (Perl is not needed).

```powershell
cd verilog
powershell -ExecutionPolicy Bypass -File run_bup.ps1   # Windows PowerShell
sh run_bup.sh                                          # sh / Git Bash
```

## Character encoding of the documentation

The Japanese documents in `doc/japanese/` were originally written in **EUC-JP** (as of 1995) and
have been **converted to UTF-8** so they can be read on GitHub. The content is unchanged:
converting them back from UTF-8 to EUC-JP reproduces the original files byte for byte.
The statement in the original `README` that `make doc.j` produces a file in EUC Kanji code
predates this conversion; `doc.j` is now UTF-8 as well.
All files added under `verilog/` are UTF-8.

## License

The author of the original STM wrote:

* `doc/english/overview`: "It is free hardware; it is distributed under a condition similar to GPL."
* `doc/japanese/intro`: 「STMはフリー・ハードウェアとします。… その他もろもろはGPLに従う、としましょう。」
  ("STM is free hardware. … Everything else follows the GPL.")

Since the original does not specify a GPL version, this repository (including the Verilog version)
is distributed under the **GNU General Public License version 2 (GPL v2)**. See [LICENSE](LICENSE)
for the full text.
