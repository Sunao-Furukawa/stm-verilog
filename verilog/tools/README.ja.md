# tools/ — アセンブラと変換ツール

[English](README.md) | **日本語**

STM のプログラムを Verilog のシミュレーションや FPGA で動かすための道具です。
必要なのは Python 3 だけです (`asm64.pl` を使うときだけ Perl が要ります)。

| ファイル | 中身 |
|---|---|
| `asm.py` | アセンブラ (`soft/asm.pl` の Python 移植版)。通常はこちらを使います。RTOS 用に `SVC` 命令を追加 |
| `asm64.pl` | `soft/asm.pl` を 64bit perl で動くように 1 行だけ直したもの (参考用) |
| `mem2hex.py` | アセンブラの出力 `mem.dat` を `$readmemh` 形式の `.hex` に変換する |
| `form_cmp.dat` | C 版シミュレータとサイクルごとに比べるときの表示フォーマット |

## 使い方

```sh
python tools/asm.py ../samples/tst.s 200 -o mem.dat     # アセンブル (200 = 最大サイクル数)
python tools/mem2hex.py mem.dat mem.hex                 # "PC=300 CYCLES=200" と表示される
vvp work/sim.vvp +HEX=mem.hex +PC=300 +CYCLES=200
```

PowerShell 5 の `>` は UTF-16 で書いてしまうので、`asm.py` には `-o` で出力先を渡してください
(`mem2hex.py` は UTF-16 の入力も読めます)。
`asm.py` / `asm64.pl` を作った経緯は [../README.ja.md 5 章](../README.ja.md#5-判断が必要だった点-元ソースとの差)、
`asm.py` に加えた変更と書き方の注意は [../rtos/README.ja.md](../rtos/README.ja.md#アセンブラ-toolsasmpy-の変更) にあります。

## ファイルの形式

* **`mem.dat`** (`asm.py` の出力): 1 行目が開始番地 (`main` ラベル, 16 進)、2 行目がサイクル数、
  その後に `adr:` 行 (16 進のバイト番地) と 16 進 1 語のデータ行が続きます。`#` で始まる行はコメント
  (`# ラベル=番地`)。
* **`.hex`** (`mem2hex.py` の出力): `@` 行 (**語番地** = バイト番地 / 4) と 16 進 1 語の行だけにしたもの。
  `$readmemh` でそのまま読めます。

## Verilog 側のどこで使われるか

このフォルダのツールは Python / Perl なので、Verilog のような行ごとのコメントは付けていません
(各ファイルの先頭に使い方と形式を書いてあります)。出力を受け取る Verilog の側には、
各行の行末に意味と合成後の回路を書いたコメントがあります
(書き方は [../README.ja.md 2 章「ソースのコメント」](../README.ja.md#ソースのコメント) 参照)。

| ツールの出力 | 受け取る Verilog (ファイル: 行) | コメントに書いてあること |
|---|---|---|
| `.hex` (シミュレーション) | `tb/tb_stm.v`, `tb/tb_exp.v`: `$readmemh(hexfile, u_sys.u_mem.mem)`, `tb/tb_stm_axi.v`, `tb/tb_noio.v`: `$readmemh(hexfile, u_mem.mem)` | メモリの配列へ直接読み込む (階層参照)。AXI4 版で `BYTE_SWAP=1` なら読んだ後に語のバイト順を反転する |
| `.hex` (メモリモデルの初期値) | `rtl/stm_memory.v`: `INIT_HEX` と `initial` | 全語を 0 にしてからファイルを読む。シミュレーション専用のモデル |
| `.hex` (FPGA) | `syn/vivado/stm_prog_ram.v`: `INIT_FILE` と `initial` | 合成時にブロック RAM の初期値 (INIT_xx) としてビットストリームに入る。`create_bd.tcl` の第 2 引数で渡す |
| `mem2hex.py` が表示する `PC=` / `CYCLES=` | テストベンチの `+PC=` / `+CYCLES=` (`$value$plusargs` の行) | 開始番地 (→ `RESET_PC` → PC の FF のリセット値) とサイクルの上限 |
| `form_cmp.dat` | `tb/tb_stm.v`, `tb/tb_exp.v`: `+CTRACE` の `$display` | C 版の `siml.res` と同じ並び (PC, 各段の FWD, I0/I1, IB_AD, LBS_AD, W_WDT1/2, PSW_CC, NIP_A/B) で表示する。各値は `stm_cntl` の内部ネットの階層参照 |
| `SVC n` (`E00000nn`) | `rtl/stm_fmt_ls_ex.vh`: `is_legal_opc`, `rtl/ch/015_d_i01.vh`: `I0_IS_LEGAL` | 上位 4bit が `1110` の命令語は不正命令として判定され、違法命令例外になる |
