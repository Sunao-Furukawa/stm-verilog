# STM CPU 本体の論理合成

[English](README.md) | **日本語**

CPU 本体 `stm_cntl` (中の EXU 2 個を含む) と、AXI4 マスタ・ポートを持つ CPU 一式
`stm_axi_top` (最後の節) を合成するための設定です。

| フォルダ | ツール | 内容 |
|---|---|---|
| `quartus/` | Intel/Altera Quartus II (13.0sp1 で確認) | プロジェクト (`stm_cntl.qpf` / `.qsf`, `stm_axi_top.qpf` / `.qsf`) とタイミング制約 (`stm_cntl.sdc`, `stm_axi_top.sdc`) |
| `vivado/` | AMD/Xilinx Vivado (2022.2 で確認) | バッチ合成スクリプト (`synth.tcl`, `synth_axi.tcl`) と制約 (`stm_cntl.xdc`, `stm_axi_top.xdc`) |

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
