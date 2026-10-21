# STM CPU 本体の論理合成

[English](README.md) | **日本語**

CPU 本体 `stm_cntl` (中の EXU 2 個を含む) と、AXI4 マスタ・ポートを持つ CPU 一式
`stm_axi_top` (最後の節) を合成するための設定です。

| フォルダ | ツール | 内容 |
|---|---|---|
| `quartus/` | Intel/Altera Quartus II (13.0sp1 で確認) | プロジェクト (`stm_cntl.qpf` / `.qsf`, `stm_axi_top.qpf` / `.qsf`) とタイミング制約 (`stm_cntl.sdc`, `stm_axi_top.sdc`) |
| `vivado/` | AMD/Xilinx Vivado (2022.2 で確認) | バッチ合成スクリプト (`synth.tcl`, `synth_axi.tcl`) と制約 (`stm_cntl.xdc`, `stm_axi_top.xdc`), IP Integrator のブロックデザインを作るスクリプト (`create_bd.tcl`, 最後の節) |

## 合成の対象

合成するのは `stm_cntl` だけです (元の VHDL 版の作者も制御部だけを合成対象にしていました)。
`stm_regfile` と `stm_memory` は **シミュレーション用のモデル** なので含めていません。

* `stm_memory` は同じサイクルで値を返す読み出しポートを 3 本持つため、FPGA のブロック RAM に
  なりません。そのまま合成するとメモリ全体が FF とマルチプレクサになります。実機で動かすには
  メモリとの接続部分の設計変更が必要です。
* そのため `stm_cntl` はレジスタファイル・メモリとの信号がすべてポートに出ていて、516 本あります。
  Quartus ではピン数の多いデバイスを選び、Vivado では out-of-context (I/O バッファを入れない) で合成しています。
* 実機では `RANDOM_FOR_OPCLH` / `RANDOM_FOR_IFRDY` / `RANDOM_FOR_IFCLH` を `1` に固定してください
  (シミュレーションでキャッシュミスを模擬するための入力です)。

## 実行方法

> **注意: 日本語 (ASCII 以外の文字) を含まないフォルダで実行してください。**
> Quartus II 13.0 は日本語を含むパスでプロジェクトを開けません
> (「Can't create project … Specify a legal project name」)。Vivado 2022.2 も日本語を含むパスでは
> RTL 解析の直後に異常終了しました。合成する前に、リポジトリを `C:\work\stm-verilog` などへ
> コピーまたは clone してください。

### Quartus

GUI: *File → Open Project* で `quartus/stm_cntl.qpf` を開き、*Processing → Start Compilation*。

コマンドライン:

```sh
cd verilog/syn/quartus
quartus_sh --flow compile stm_cntl
```

結果は `quartus/output_files/` (`stm_cntl.fit.summary`, `stm_cntl.sta.rpt`) に出ます。
デバイスは Cyclone IV E EP4CE115F29C7 (DE2-115 搭載品)。変えるときは `.qsf` の `FAMILY` / `DEVICE` を編集します。

### Vivado

```sh
cd verilog/syn/vivado
vivado -mode batch -source synth.tcl                              # xc7a100tcsg324-1 (既定)
vivado -mode batch -source synth.tcl -tclargs xc7a35tcpg236-1     # 別のデバイス
```

結果は `vivado/reports/` (`utilization.rpt`, `timing_summary.rpt`)、チェックポイントは `stm_cntl_synth.dcp` に出ます。

## 結果 (確認時)

目標クロック 25 MHz (40 ns)。入出力にはそれぞれ外部回路の遅延として半周期を見込んでいます。

| ツール / デバイス | 使用量 | タイミング |
|---|---|---|
| Quartus II 13.0sp1, Cyclone IV E EP4CE115F29C7 (配置配線まで) | 5,514 LE, レジスタ 1,622, ピン 516 | 25 MHz で達成 (セットアップ余裕 +3.3 ns)。AXI4 版用のポートを足す前の版では、50 MHz で制約したときの Fmax は 38.6 MHz |
| Vivado 2022.2, Artix-7 xc7a100tcsg324-1 (合成のみ) | LUT 3,034, FF 1,623 | 25 MHz で達成 (WNS +11.2 ns, 合成後の見積もり) |

半周期の例外は `IB_AD_NXT` (次のフェッチ番地。AXI4 版の命令キャッシュが使う) で、出力側の
見込みを 5 ns にしています。フェッチのハンドシェークの入力からの組合せ回路で、そのまま
キャッシュ RAM の番地レジスタに入るため、両端に半周期ずつ取るとその経路自体の時間が残らない
からです。

残る警告は、C 風の定数 (`? 1 : 0` など) の切り詰めと、使われないデコード信号やタグの削除で、
どちらも問題ありません。

## AXI4 マスタ付きの CPU (`stm_axi_top`)

`stm_axi_top` ([../README.ja.md 8 章](../README.ja.md#8-axi4-マスタ版-stm_axi_top) 参照) は
`stm_cntl`, `stm_regfile`, 命令キャッシュ `stm_icache`, ブリッジ `stm_axi_master` を含む CPU 一式で、
外とのつながりは AXI4 マスタ・ポートだけです (観測用の `PC` / `bus_error` を含めて 281 ピン)。
命令キャッシュ (既定 4KB) はブロック RAM になります。レジスタファイルは同じサイクルで読める
読み出しポートが 4 本あるので FF で作られます。

```sh
cd verilog/syn/quartus
quartus_sh --flow compile stm_axi_top
cd ../vivado
vivado -mode batch -source synth_axi.tcl        # 結果は vivado/reports_axi/
```

| ツール / デバイス | 使用量 | タイミング |
|---|---|---|
| Quartus II 13.0sp1, Cyclone IV E EP4CE115F29C7 (配置配線まで) | 8,593 LE, レジスタ 2,562, メモリ 35,328 ビット, ピン 281 | 25 MHz で達成 (セットアップ余裕 +2.0 ns) |
| Vivado 2022.2, Artix-7 xc7a100tcsg324-1 (合成のみ, out-of-context) | LUT 4,875, FF 2,564, ブロック RAM 1.5 タイル | 25 MHz で達成 (WNS +10.4 ns, 合成後の見積もり) |

`stm_cntl` 単体より増える警告は、観測用にしか使わないパイプラインのタグが削除されるもの、
キャッシュが使わないアドレスのビット、レジスタファイルを FF で作るという通知です。

## IP Integrator のブロックデザイン (`vivado/create_bd.tcl`)

`stm_axi_top` を IP Integrator で使うプロジェクトを作るスクリプトです。Vivado 2022.2 で確認しました。

```sh
cd verilog
python tools/asm.py ../samples/hello_uart.s 1000 -o work/hello_uart.dat     # UART に Hello World を出すプログラム
python tools/mem2hex.py work/hello_uart.dat work/hello_uart.hex
cd syn/vivado
vivado -mode batch -source create_bd.tcl                                            # メモリは 0 のまま
vivado -mode batch -source create_bd.tcl -tclargs xc7a100tcsg324-1 ../../work/hello_uart.hex   # デバイスとプログラムを指定
vivado -mode batch -source create_bd.tcl -tclargs xc7a35ticsg324-1L ../../work/hello_uart.hex arty_a7_35.xdc   # Arty A7-35 (ピン配置も)
```

スイッチで選んだあいさつ (Hello / Nihao / Konnichiwa / annyeonghaseyo) を RTOS で出すプログラムは
[`rtos/greet_uart.s`](../rtos/greet_uart.s) です ([../rtos/README.ja.md](../rtos/README.ja.md) 参照)。

```sh
cd verilog
python tools/asm.py rtos/greet_uart.s 20000 -o work/greet_uart.dat
python tools/mem2hex.py work/greet_uart.dat work/greet_uart.hex
cd syn/vivado
vivado -mode batch -source create_bd.tcl -tclargs xc7a35ticsg324-1L ../../work/greet_uart.hex arty_a7_35.xdc
```

引数はどれも省略できます: 1 番目 = デバイス (既定 `xc7a100tcsg324-1`), 2 番目 = プログラムの `.hex`
(`-` なら無し), 3 番目 = ボードの XDC (プロジェクトに追加される)。

`vivado/stm_bd/stm_bd.xpr` ができます。GUI の Tcl コンソールからは
`cd <このフォルダ>; set argv {xc7a100tcsg324-1 ../../work/hello_uart.hex}; source create_bd.tcl` でも実行できます。

ブロックデザイン `stm_system` の中身:

```
sys_clk (100 MHz) ─▶ Clocking Wizard (24 MHz) ─▶ 全体の aclk
reset_n (L で有効) ─▶ Clocking Wizard, Processor System Reset ─▶ aresetn
Constant 0x300 ─▶ cpu/RESET_PC
cpu (stm_axi_top, モジュール参照) ──m_axi──▶ AXI SmartConnect
      M00 ─▶ AXI BRAM Controller + stm_prog_ram   0x0000_0000〜0x0000_1FFF (8KB)
      M01 ─▶ AXI UART Lite (115200 baud)         0xF000_0000〜0xF000_FFFF
      M02 ─▶ AXI GPIO (入力 4 ビット, スイッチ)   0xF001_0000〜0xF001_FFFF
bus_error, uart (rxd / txd), sw_tri_i[3:0] ─▶ 外部ポート
```

* CPU は RTL のまま **モジュール参照** (*Add Module*) で置いています。モジュール参照では include
  ファイルもプロジェクトに入っている必要があるので、`rtl/*.vh` と `rtl/ch/*.vh` を追加しています。
  `rtl/ch/*.vh` は `stm_cntl` の本体の一部で単独では構文エラーになるため、`used_in` を空にして
  単独では解析させず、`` `include `` からだけ読ませています。
* プログラムメモリは Block Memory Generator ではなく [`vivado/stm_prog_ram.v`](vivado/stm_prog_ram.v)
  (モジュール参照) です。ブロックデザインの中で AXI BRAM Controller につないだ Block Memory
  Generator には初期値ファイルを設定できなかったためです。`stm_prog_ram` は `tools/mem2hex.py`
  の出力をそのまま `$readmemh` で読み、ブロック RAM になります (8KB で RAMB36 × 2)。
* クロックは 24 MHz です (CPU 単体の確認は 25 MHz)。UART Lite はクロックを 16 × ボーレートで割るので、
  25 MHz では 115200 baud に対して 3.1% ずれ (25 MHz / (16 × 115200) = 13.56)、Vivado は何も言わずに
  110 baud にしてしまいました。24 MHz なら 13.02 で、ずれは 0.16% です。スクリプトは、ボーレートと
  プログラムメモリの `INIT_FILE` が設定どおりかを最後に確かめ、違えばエラーで止まります。
* UART Lite は CPU の I/O 領域 (`0xF000_0000`〜) に置いています。I/O 領域のロードは投機的に
  実行されないので、読むと中身が減る受信 FIFO を安全に読めます。レジスタは +0x0 受信 FIFO,
  +0x4 送信 FIFO, +0x8 ステータス (ビット 3 = 送信 FIFO が満杯), +0xC 制御。語単位で書いてください。
* GPIO (すべて入力, 4 ビット) もスライドスイッチ用に I/O 領域 (`0xF001_0000`) に置いています。
  +0x0 を読むと、ビット 0〜3 に `sw_tri_i[0]`〜`[3]` が入ります。
* [`samples/hello_uart.s`](../../samples/hello_uart.s) は、ステータスを見て送信 FIFO に空きがあれば
  `F000_0004` に 1 文字ずつ書き、`Hello World` (CR LF 付き) を出して無限ループで止まります。
  `samples/hello.s` のほうはテストベンチのコンソール (`F000_0008`) に書くので、実機の UART には
  出ません。テストベンチには UART が無いので、`hello_uart.s` をシミュレーションすると何も表示
  されず TIMEOUT になります (AXI4 版で、`F000_0004` に `Hello World
` の 13 バイトが書かれ、
  ステータスがちょうど 13 回読まれることは確認済み)。
* `sys_clk`, `reset_n`, `uart_rxd`, `uart_txd`, `bus_error`, `sw_tri_i[3:0]` のピン配置はボードごとに違います。
  Digilent Arty A7-35 用は [`vivado/arty_a7_35.xdc`](vivado/arty_a7_35.xdc) です (Arty A7-100 も同じピン)。
  100 MHz の発振器 (E3), RESET ボタン (C2, 押すと L), USB-UART (A9 / D10), `bus_error` を LD4 (H5),
  `sw_tri_i[0]`〜`[3]` をスライドスイッチ SW0〜SW3 (A8, C11, C10, A10) に割り当てています。ピンは Digilent の `Arty-A7-35-Master.xdc` から取りました。他のボードでは、
  これを参考に XDC を作って 3 番目の引数に渡すか、配置配線の前に追加してください。

確認したこと:

* `xc7a100tcsg324-1` と `hello.hex` で、プロジェクトの作成と合成 (エラー・クリティカル警告無し)。
  プログラムメモリには `.hex` が読み込まれ、ブロック RAM になっています。
* Arty A7-35 (`xc7a35ticsg324-1L`, `hello_uart.hex`, `arty_a7_35.xdc`) で、ビットストリームまで
  (エラー・クリティカル警告無し, DRC 違反無し)。24 MHz で WNS +22.8 ns / WHS +0.024 ns。
  LUT 7,651 (37%), FF 5,582 (13%), ブロック RAM 3.5 タイル, MMCM 1。
* 生成された回路 (SmartConnect, BRAM コントローラ, UART Lite を含む) を Vivado のシミュレータ (xsim) で
  動かし、`uart_txd` に `Hello World
` が 115200 baud で出ることを確認。
* **実機**: Arty A7-35 にこのビットストリームを書き込み、RESET ボタンを押すと、PC のターミナル
  (115200 baud) に `Hello World` が表示されることを確認しました。
* GPIO を足した後、Arty A7-35 (`xc7a35ticsg324-1L`, `rtos/greet_uart.s`, `arty_a7_35.xdc`) で
  ビットストリームまで (エラー・クリティカル警告無し, DRC 違反無し)。24 MHz で WNS +22.7 ns /
  WHS +0.015 ns。LUT 8,406 (40%), FF 6,383 (15%), ブロック RAM 3.5 タイル, MMCM 1。
* 同じ回路を xsim で動かし (`DELAY` だけ短くしたプログラム)、スイッチを 0 → 1 → 2 → 3 と変えると
  `uart_txd` に `Hello`, `Nihao`, `Konnichiwa`, `annyeonghaseyo` が 115200 baud で出ることを確認
  (フレーミングエラー無し, `bus_error` = 0)。実機では未確認です。

> Vivado 2022.2 では、ブロックデザインを作るとき (`create_bd_design`) に、Vivado 自身の IP の
> スクリプトが読めないというエラー (`couldn't read file ...`, `Failed to load feature 'ipintegrator'`
> など) でまれに止まることがありました。スクリプトの内容とは関係がなく、もう一度実行すると通ります。

### 自分のプロジェクトで *Add Module* を使う場合

`create_bd.tcl` を使わず、自分のプロジェクトのブロックデザインに *Add Module* で `stm_axi_top`
を置こうとすると、次のエラーになることがあります。

```
[filemgmt 56-591] Given include File '.../verilog/rtl/ch/130_a_act.vh' needs to be addded to the project in order to use it as an RTL module.
```

モジュール参照では、`` `include `` で読み込むファイルもすべてプロジェクトに入っている必要が
あるためです。`stm_cntl.v` は `rtl/*.vh` (4 個) と `rtl/ch/*.vh` (23 個) を読み込んでいます。
プロジェクトを開いた状態で、Tcl Console に次を入力してください (`rtl` のパスは自分の環境に合わせる)。

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

* `rtl/*.vh` と `rtl/ch/*.vh` を Verilog Header としてプロジェクトに追加します。
* `rtl/ch/*.vh` は `stm_cntl` の本体を分けたもので、単独では Verilog として成り立ちません。
  追加しただけだと Vivado が 1 つずつ解析して `Syntax error near 'assign'` の CRITICAL WARNING を
  23 個出すので、`used_in` を空にして単独では解析させないようにします (`` `include `` からは読まれます)。
* `stm_cntl.v` は `"ch/010_d_pre.vh"` のように `rtl/` からの相対パスで読み込むので、`rtl/` を
  include の検索パスにします。

GUI で行う場合は、*Add Sources* で上の 27 個の `.vh` を追加し、Type が *Verilog Header* か確かめ、
`ch/` の 23 個の *Source File Properties* で *Used In* のチェックをすべて外し、*Settings →
General → Verilog options → Include Search Paths* に `verilog/rtl` を追加します。
