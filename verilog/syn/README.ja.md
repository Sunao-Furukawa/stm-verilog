# STM CPU 本体の論理合成

[English](README.md) | **日本語**

CPU 本体 `stm_cntl` (中の EXU 2 個を含む) を合成するための設定です。

| フォルダ | ツール | 内容 |
|---|---|---|
| `quartus/` | Intel/Altera Quartus II (13.0sp1 で確認) | プロジェクト (`stm_cntl.qpf` / `.qsf`) とタイミング制約 (`stm_cntl.sdc`) |
| `vivado/` | AMD/Xilinx Vivado (2022.2 で確認) | バッチ合成スクリプト (`synth.tcl`) と制約 (`stm_cntl.xdc`) |

## 合成の対象

合成するのは `stm_cntl` だけです (元の VHDL 版の作者も制御部だけを合成対象にしていました)。
`stm_regfile` と `stm_memory` は **シミュレーション用のモデル** なので含めていません。

* `stm_memory` は同じサイクルで値を返す読み出しポートを 3 本持つため、FPGA のブロック RAM に
  なりません。そのまま合成するとメモリ全体が FF とマルチプレクサになります。実機で動かすには
  メモリとの接続部分の設計変更が必要です。
* そのため `stm_cntl` はレジスタファイル・メモリとの信号がすべてポートに出ていて、480 本あります。
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
| Quartus II 13.0sp1, Cyclone IV E EP4CE115F29C7 (配置配線まで) | 5,550 LE, レジスタ 1,621, ピン 480 | 25 MHz で達成 (セットアップ余裕 +2.1 ns)。50 MHz で制約したときの Fmax は 38.6 MHz |
| Vivado 2022.2, Artix-7 xc7a100tcsg324-1 (合成のみ) | LUT 2,998, FF 1,622 | 25 MHz で達成 (WNS +11.7 ns, 合成後の見積もり) |

残る警告は、C 風の定数 (`? 1 : 0` など) の切り詰めと、使われないデコード信号やタグの削除で、
どちらも問題ありません。
