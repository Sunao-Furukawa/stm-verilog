# STM-1.2 ハードウェア記述の Verilog HDL 2001 版

`hard/` にある CHDL (`*.ch`) と C ヘッダ (`*.h`) を Verilog HDL 2001 に変換したものです。
元ファイルには手を加えていません。

## 1. 元の記述 (CHDL) について

STM は 2 命令同時発行 (2-way スーパースカラ) の 32bit RISC CPU です。
ハードウェアは **CHDL** という独自の簡易 HDL で書かれています。中身はほぼ C の式で、

| CHDL                | 意味 |
|---------------------|------|
| `NAME = 式`          | 組合せ回路のネット |
| `NAME := 式`         | フリップフロップ (FF) への代入。次のクロックで値が変わる |
| 名前中の `-`          | 普通の文字 (`DD-RAD1` で 1 つの名前) |
| `#` 以降              | コメント (`#ifndef VHDL` などは cpp の指令) |

`soft/chc` + `soft/perlcmd1` が CHDL を C に変換してサイクルシミュレータ `stmsiml` を作ります。
その際 `A := 式` は `A_NEW = 式;` になり、サイクルの最後に `A = A_NEW;` で FF が更新されます。
`*.h` は、その C ソースの先頭に付けるマクロ (ビットフィールド抽出、加算器など) と演算器 `exu()` です。

同じソースを `vh/` のツールで VHDL (Alliance 用) にも変換できるよう、`#ifdef VHDL` で
C 用と VHDL 用の書き方を切り替えている箇所があります。

## 2. 生成したファイル

```
verilog/
├── rtl/
│   ├── stm_const.vh      <- hard/const.h      定数 (opcode, 割り込みコード, システムレジスタ番号)
│   ├── stm_defs.vh       <- hard/defs.h + vdefs.h  マクロ → function (符号拡張, cc_match, build_psw, 加算器)
│   ├── stm_fmt_jb.vh     <- hard/fmt-jb.h     JB/特権命令のフィールド抽出 function
│   ├── stm_fmt_ls_ex.vh  <- hard/fmt-ls-ex.h  LS/EX 命令のフィールド抽出 function, is_legal_opc
│   ├── stm_exu.v         <- hard/exu.h        演算器 (C 関数 exu() → モジュール)
│   ├── stm_cntl.v        CPU 本体。宣言 + ch/*.vh を `include + FF 更新
│   ├── ch/010_d_pre.vh … 210_g_bc.vh   <- hard/*.ch を 1 ファイルずつ変換
│   ├── stm_regfile.v     <- 045-g-ram.ch の GR[]  (汎用レジスタ 16 本)
│   ├── stm_memory.v      <- 045-g-ram.ch の Mem[] (シミュレーション用メモリ)
│   └── stm_sys.v         全体を接続するトップ (VHDL 版 vh/behave/sys.vst 相当)
├── tb/tb_stm.v           テストベンチ
├── tools/
│   ├── asm.py            アセンブラ (soft/asm.pl の Python 移植版。通常はこちらを使う)
│   ├── asm64.pl          soft/asm.pl の 64bit perl 対応版 (参考用)
│   ├── mem2hex.py        mem.dat → $readmemh 形式
│   └── form_cmp.dat      C 版との比較用の表示フォーマット
├── run_bup.ps1           bup0/bup1 回帰テスト一式 (Windows PowerShell 用)
└── run_bup.sh            同じもの (sh / Git Bash 用)
```

## 3. 変換のルール

| CHDL / C                                   | Verilog 2001 |
|--------------------------------------------|--------------|
| `DD-RAD1 = 式`                             | `assign DD_RAD1 = 式;` |
| `PC := 式`                                 | `assign PC_NEW = 式;` と `always @(posedge clk) PC <= PC_NEW;` |
| `-` を含む名前                              | `-` → `_` (VHDL 変換ツールと同じ規則) |
| `0xdead0a0a`                               | `32'hdead0a0a` |
| マクロ `ls_store(i)`, `cc_match(cc,m)` …   | 同名の `function` |
| `exu(opc,x,y,&cc,&z,&intr)`                | `stm_exu` のインスタンス (A サイクル用と E サイクル用の 2 個) |
| `GR[..] :=`, `Mem[..] :=`                  | 外部モジュール `stm_regfile` / `stm_memory` |
| `#ifndef VHDL … #else … #endif`            | C 側 (実際に検証されていた方) を採用し、VHDL 側はコメントで残す |
| `#if 0 … #endif`                           | 元でも無効なのでコメントとして残す |
| ビット番号 (MSB=0 番)                       | 一般的な `[31:0]` (LSB=0 番) に変換。`bit_ext(i,s,n)` = `i[31-s -: n]` |

ビット幅は元ソースに書かれていないので、VHDL 変換ツール用の表 `vh/prop.tab` / `vh/assi.tab` から取りました。

**評価順序について**: CHDL→C では文が書いた順に実行されるため、本来は順序に意味があります
(使う前に定義が必要)。全 `.ch` を調べ、すべてのネットが「定義 → 使用」の順に並んでいる
ことを確認したので、順序に依存しない Verilog の連続代入に置き換えても動作は変わりません。

**リセット**: `rst=1` で全 FF を 0、`PC` だけ `RESET_PC` にします。C 版が PC に開始番地を入れ
他を 0 から始めていたのと同じで、`START_TRIGGER_BAR=0` なので最初のサイクルで命令フェッチが始まります。

## 4. 回路の中身 (各 .ch の役割)

パイプラインは **IF → D → A → B → E → W** で、D で最大 2 命令を発行し、
LS パイプ (ロード/ストア、メモリオペランド演算) と EX パイプ (レジスタ演算) と JB (分岐) に振り分けます。

| ファイル | 内容 |
|---|---|
| 010-d-pre | 命令キュー IWQ-A/B (各 6 語) から、次に発行する 2 命令 I0/I1 を取り出す。分岐予測で 2 本の経路を持ち、`EID` がどちらを使うか選ぶ |
| 015-d-i01 | I0/I1 のフィールド解読 |
| 020-d-iss | 各命令が LS/EX/JB/特権のどれか、どのレジスタを読み書きするか |
| 030-d-sec | 2 命令目を同時発行できるか (CC/レジスタ依存、パイプ競合) を判定し、ILS/IEX/IJB に振り分け |
| 035-d-ixx | ILS/IEX/IJB のフィールド解読 |
| 040-d-bra | 分岐: 種類判定 (BA/JA/BL/JL/BC)、条件分岐が既に解決済みか、後方分岐なら taken と予測、分岐先 DD-TGT の計算 |
| 045-g-ram | レジスタファイルとメモリ (Verilog では別モジュール) |
| 050-op-lb1 | S ユニット (オペランドキャッシュ) の出力、割り込み/分岐予測ミスによるキャンセル、アドレス比較割り込み |
| 060-g-srq | 各ステージの有効フラグ、A サイクルのオペランド未到着検出 (A-EAB)、SU への要求の優先度 |
| 070-g-ilk | インタロック条件と各ステージの前進信号 (D/A/B/E-FWD) |
| 080-w-act | W サイクル: システムレジスタ・PC・PSW の更新、割り込み処理 |
| 090-e-act | E サイクル: LS パイプの ALU、割り込みの優先順位、W への受け渡し、ストアバッファ STB |
| 100-b-dat | B サイクル: バイパスを含むオペランド/ロードデータの選択 |
| 110-b-act | B → E の状態遷移、バイト/ハーフワードの opcode をアドレス下位で決定 |
| 120-a-dat | A サイクル: EX パイプの EXU、アドレス生成 (EAG)、システムレジスタ読み出し |
| 130-a-act | A → B の状態遷移 |
| 140-d-dat | D → A へオペランドを渡す。各ステージからのバイパス選択 |
| 150-d-act | D → A の状態遷移 |
| 160-op-lb2 | S ユニットの次状態 (WAIT/B 状態) |
| 170-if-req | 命令フェッチ要求のアドレス/ID |
| 180-if-lbs | 命令フェッチ応答 (キャッシュミス模擬を含む) |
| 190-if-stm | 命令フェッチ状態機械と NIP (キュー内の次命令位置) |
| 200-if-iwq | 命令キュー IWQ のシフト/取り込み |
| 210-g-bc | 条件分岐の解決状態を持つグローバル FF (G-BC-*) |

## 5. 判断が必要だった点 (元ソースとの差)

C 版と VHDL 版で記述が食い違う箇所は、すべて **C 版** に合わせました。C 版が回帰テスト
(`samples/subbup`) で実際に検証されていた方であり、下記の検証でも一致を確認しています。

1. **`is_legal_opc`** (fmt-ls-ex.h): VHDL 版の論理式はユーザーモードを見ず、命令範囲も C 版と少し違う簡略版。C 版を採用。
2. **`WW-STATECHANGE`** (050-op-lb1.ch): C 版は「WSR の書き込み先が 0〜3 番 (PSW 等)」、VHDL 版は逆の条件 (4 番以上) になっている。C 版を採用。
3. **レジスタファイル/メモリ**: C 版では `GR[..] :=` が即座に書き込まれ、同じサイクルの読み出しに反映される
   (write-through)。`stm_regfile` / `stm_memory` で読み出しバイパスを付けて再現。
4. **EXU の未定義動作**: C 版で値を設定しない場合 (未定義 opcode、バイト系命令の cc) は 0 を出力。
   シフト量 32 以上 (C では未定義動作) は SL/SRL → 0、SRA → 符号埋めとした。
5. **乱数によるキャッシュミス模擬** (`random()`): 入力ポート `RANDOM_FOR_OPCLH/IFRDY/IFCLH` にした。
   常に 1 ならキャッシュ常時ヒット、テストベンチの `+RANDOM` で C 版 `stmsiml -r` 相当になる。
6. **シミュレーション用プローブ** (`E-STAT` など) はそのまま wire として残した。

なお、元のアセンブラ `soft/asm.pl` は 32bit perl 前提で、今の 64bit perl では負の変位が
`80aeffff00000000fefc` のように壊れます。マスク計算 1 行だけを直したコピーを `tools/asm64.pl` に置きました。

さらに、Windows の Perl (Strawberry Perl など) は日本語を含むフォルダの中で
`Can't open perl script ...: Unicode 文字のマッピングがターゲットの マルチバイト コード ページにありません。`
というエラーになることがあるため、Python に移植した `tools/asm.py` を用意し、通常はこちらを使う
ようにしました。bup0/bup1/samples の全 67 ファイルで `asm64.pl` と同じ出力になることを確認しています。

## 6. 検証

* `iverilog -g2001 -Wall` で警告なしにコンパイルできることを確認。
* **回帰テスト**: `bup0` / `bup1` の全 64 本を、キャッシュミス無しとランダムキャッシュミス有りの
  両方で実行し、128/128 が SUCCESS (PC=0x3F0) で終了。
* **C 版とのサイクル単位比較**: 元の C シミュレータ (`soft/chc` で生成される `stmsiml`) を
  RISC-V クロスコンパイラ + QEMU で動かし、bup0/bup1 全 64 本と `samples/tst.s` の計 65 本で、
  毎サイクルの PC, 各ステージの FWD, I0/I1, IB-AD, LBS-AD, W-WDT1/2, PSW-CC, NIP-A/B
  を比較 → **全サイクル完全一致**。
  (ランダムモードは乱数列が C の `random()` と異なるため、サイクル比較はしていません)

## 7. 使い方

必要なもの: Python 3 と Icarus Verilog (iverilog / vvp)。Perl は不要です。

### 回帰テスト一式

Windows PowerShell の場合 (verilog フォルダで):

```powershell
powershell -ExecutionPolicy Bypass -File run_bup.ps1
```

Git Bash などの sh の場合:

```sh
sh run_bup.sh
```

### 1 本だけ動かす

```powershell
python tools/asm.py ../samples/tst.s 200 -o mem.dat
python tools/mem2hex.py mem.dat mem.hex          # "PC=300 CYCLES=200" と表示される
iverilog -g2001 -I rtl -o sim.vvp tb/tb_stm.v rtl/stm_sys.v rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v rtl/stm_memory.v
vvp sim.vvp +HEX=mem.hex +PC=300 +CYCLES=200 +TRACE
```

* アセンブラの出力は `-o` でファイルに書いてください。PowerShell 5 の `>` は UTF-16 で
  保存されます (`mem2hex.py` は UTF-16 も読めるようにしてありますが、`-o` が確実です)。
* `+RANDOM` (+`SEED=n`) でキャッシュミス模擬、`+CTRACE` で C 版の `siml.res` と同じ形式で出力します。
