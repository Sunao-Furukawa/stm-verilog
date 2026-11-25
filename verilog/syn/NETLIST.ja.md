# Vivado が生成するネットリストの読み方

[English](NETLIST.md) | **日本語**

[`README.ja.md`](README.ja.md) の手順 (`create_bd.tcl`) でブロックデザインを作って合成すると、
`vivado/stm_bd/` の下に Verilog のネットリストがたくさんできます。これらは **Vivado が生成する
ファイル** で、git の管理外 (`.gitignore`) にあり、合成し直すたびに上書きされます。
そのためファイル自体にはコメントを書き込まず、ここで読み方をまとめます。

RTL (`rtl/*.v`, `rtl/ch/*.vh`) の各ファイルの先頭には、そのファイルが作る回路と
ネットのつながりを説明する **【ネットリスト解説】** を書いてあります。この文書はその続きで、
「RTL が実際にどんな部品の接続 (ネットリスト) になったか」を見るためのものです。

以下の数字と名前は、Vivado 2022.2, `xc7a35ticsg324-1L` (Arty A7-35),
`greet_uart.hex` で作ったときのものです。

## 1. ネットリストとは

ネットリストは「部品 (セル) の一覧」と「部品の端子どうしをつなぐ線 (ネット) の一覧」です。
RTL の `assign` や `always` は「何を計算するか」を書いたものですが、ネットリストでは
それが FPGA の具体的な部品 (LUT, FF, キャリー連鎖, ブロック RAM) の接続に置き換わっています。

```verilog
// RTL (rtl/ch/160_op_lb2.vh)
assign OP_B_OPC_NEW = OP_B_STAYS ? OP_B_OPC : OP_B_SHIFT ? OP_WAIT_OPC : ACCEPTING_OPC;
//   + stm_cntl.v の  always @(posedge clk) ... OP_B_OPC <= OP_B_OPC_NEW;

// ネットリスト (stm_system_cpu_0_sim_netlist.v)
LUT4 #(.INIT(16'hB8BB)) \OP_B_OPC[0]_i_1          // 組合せ回路 = 4 入力の真理値表
   (.I0(OP_WAIT_OPC[0]), .I1(p_49_in), .I2(WW_ST_GO), .I3(A_LS_ST_V),
    .O(\OP_B_OPC[0]_i_1_n_0 ));
FDRE \OP_B_OPC_reg[0]                             // FF
   (.C(aclk), .CE(\OP_B_OPC[1]_i_1_n_0 ), .D(\OP_B_OPC[0]_i_1_n_0 ),
    .Q(OP_B_OPC[0]), .R(rst));
```

`OP_B_STAYS` (保持) の分岐は LUT から消えて FF の CE (クロックイネーブル) 端子に移り、
残りの「OP-WAIT から移すか, 新しく受け付けるか」だけが LUT4 になっています。

## 2. どのファイルが何か

`vivado/stm_bd/stm_bd.gen/sources_1/bd/stm_system/` の下:

| ファイル | 中身 |
|---|---|
| `hdl/stm_system_wrapper.v` | ブロックデザインの最上位。外部ポート (クロック, リセット, UART, スイッチ, `bus_error`) を `stm_system` につなぐだけ |
| `synth/stm_system.v`, `sim/stm_system.v` | ブロックデザインそのもの。IP のインスタンス (`cpu`, `smartconnect`, `bram_ctrl`, `ram`, `uart`, `gpio`, `clk_wiz`, `rst`, `reset_pc`) と、それらをつなぐ AXI の線。**ブロックデザインの図をそのまま Verilog にしたネットリスト** |
| `ip/<IP 名>/synth/<IP 名>.v` | 各 IP の外側の殻。中で本体 (`stm_axi_top` など) をインスタンスする |
| `ip/<IP 名>/<IP 名>_stub.v` | ポートの宣言だけの空のモジュール (ブラックボックス)。上位を合成するときに中身を見せないために使う |
| `ip/<IP 名>/<IP 名>_sim_netlist.v` | **合成後のネットリスト** (`write_verilog -mode funcsim`)。FPGA の部品 (UNISIM の LUT6, FDRE など) の接続だけでできていて、そのままシミュレーションできる |

`.cache/ip/...` の下にも同じ名前のファイルがありますが、IP の合成結果のキャッシュです
(中身はほぼ同じで、ヘッダのパスなどが違います)。

このうち自分の設計 (STM) が入っているのは `stm_system_cpu_0` (CPU 一式 `stm_axi_top`) と
`stm_system_ram_0` (プログラムメモリ `stm_prog_ram`) の 2 つです。他は Xilinx の IP
(`smartconnect` だけで 11 万行) なので、読む必要はありません。

### ブロックデザインのネット (`synth/stm_system.v`)

ネットの名前は「<出す側のインスタンス>_<ポート>」になっています。例えば

```verilog
stm_system_cpu_0 cpu
   (.RESET_PC(reset_pc_dout),              // reset_pc (Constant 0x300) の出力
    .aclk(clk_wiz_clk_out1),               // Clocking Wizard の 24 MHz
    .aresetn(rst_peripheral_aresetn),      // Processor System Reset の出力
    .m_axi_araddr(cpu_m_axi_ARADDR),       // cpu が出し, smartconnect の S00_AXI が受ける
    ...
```

`cpu_m_axi_*` は cpu → SmartConnect, `smartconnect_M00_AXI_*` は SmartConnect → BRAM Controller,
`bram_ctrl_BRAM_PORTA_*` は BRAM Controller → `stm_prog_ram` の線です。

## 3. CPU のネットリスト (`stm_system_cpu_0_sim_netlist.v`)

### 3.1 モジュールの階層

```
stm_system_cpu_0                    IP の殻
└── stm_system_cpu_0_stm_axi_top     rtl/stm_axi_top.v
    ├── stm_system_cpu_0_stm_cntl     rtl/stm_cntl.v + rtl/ch/*.vh (stm_exu 2 個はここに展開される)
    ├── stm_system_cpu_0_stm_regfile  rtl/stm_regfile.v
    ├── stm_system_cpu_0_stm_icache   rtl/stm_icache.v
    └── stm_system_cpu_0_stm_axi_master rtl/stm_axi_master.v
```

モジュール名の頭に IP 名 (`stm_system_cpu_0_`) が付きます。`stm_exu` は小さいので
`stm_cntl` に溶け込んで (平坦化されて) 残りません。`function` (`stm_defs.vh` など) も同じで、
呼んだ場所の回路の一部になります。

### 3.2 部品の種類と数

| モジュール | FDRE | FDSE | LUT1〜6 | MUXF7 | MUXF8 | CARRY4 | ブロック RAM |
|---|---:|---:|---:|---:|---:|---:|---|
| `stm_cntl` | 1,623 | 0 | 4,286 | 49 | 0 | 65 | なし |
| `stm_regfile` | 512 | 0 | 640 | 320 | 64 | 0 | なし |
| `stm_icache` | 284 | 6 | 331 | 12 | 6 | 5 | RAMB36E1 × 1, RAMB18E1 × 1 |
| `stm_axi_master` | 136 | 3 | 128 | 0 | 0 | 0 | なし |
| `stm_axi_top` (自分の中) | 0 | 0 | 8 | 0 | 0 | 0 | なし |

部品の意味:

| 部品 | 意味 |
|---|---|
| `FDRE` | D フリップフロップ。CE (クロックイネーブル) と **同期リセット** R (リセット値 0) 付き |
| `FDSE` | 同じく, ただし同期 **セット** S (リセット値 1) |
| `LUT1`〜`LUT6` | 1〜6 入力の任意の論理関数。`INIT` が真理値表 (ビット番号 = 入力 {I5..I0} の値) |
| `MUXF7` / `MUXF8` | LUT の出力 2 本を選ぶ専用の MUX。LUT6 + MUXF7 で 7 入力, + MUXF8 で 8 入力の関数になる |
| `CARRY4` | 4bit ぶんの高速キャリー連鎖。加算器・比較器は 4bit ごとにこれをつなげる |
| `RAMB36E1` / `RAMB18E1` | ブロック RAM (36Kbit / 18Kbit) |

### 3.3 名前の付き方

合成ツールは RTL の名前をできるだけ残すので、ネットリストから RTL へ戻れます。

| ネットリストの名前 | 意味 | 例 |
|---|---|---|
| `X_reg` / `X_reg[i]` | RTL の `reg X` (の i ビット目) の FF | `\PC_reg[0]`, `START_TRIGGER_BAR_reg` |
| `X` | その FF の出力 (Q) のネット | `OP_B_OPC[0]` |
| `X[i]_i_N` | `X[i]` の FF の D 入力を作る LUT。N が大きいほど FF から遠い (前の段) | `\PC[0]_i_1`, `\PC[0]_i_2` |
| `..._n_0` | 上の LUT / CARRY4 の出力ネット | `\PC[0]_i_1_n_0` |
| `X_NEW` など | RTL の wire がそのまま 1 本のネットとして残ったもの | `START_TRIGGER_BAR_NEW` |
| `p_NN_in`, `..._0` | 元の名前が残らなかったネット (論理の途中) | `p_49_in` |
| `func_return` | `function` の戻り値 | `add_32_5_20_return[12:9]` |
| `FSM_onehot_X_reg[k]` | 状態機械 `X` をワンホットに作り直したときの状態 k の FF | `FSM_onehot_if_st_reg[0]` |
| `g_cache.X` | `generate` のブロック名 `g_cache` の中の `X` | `\g_cache.dram_reg` |

### 3.4 読んでみる

**PC のリセット**。`stm_cntl.v` では PC だけリセット値が入力 `RESET_PC` です。

```verilog
FDRE \PC_reg[0] (.C(aclk), .CE(\PC[31]_i_1_n_0 ), .D(\PC[0]_i_1_n_0 ),
                 .Q(\PC_reg[31]_0 [0]), .R(1'b0));          // R は使っていない
LUT5 #(.INIT(32'hB8FFB800)) \PC[0]_i_1
   (.I0(TBR[0]), .I1(\PC[31]_i_3_n_0 ), .I2(\PC[0]_i_2_n_0 ),
    .I3(aresetn), .I4(RESET_PC[0]), .O(\PC[0]_i_1_n_0 ));
```

`INIT = 32'hB8FFB800` を真理値表として読むと
`O = !aresetn ? RESET_PC[0] : (I1 ? TBR[0] : I2)` です。
リセット値が定数でないので FF の R 端子は使えず (`.R(1'b0)`)、**D 入力の手前に
「リセット中なら RESET_PC」を選ぶ論理が入っています**。同じ LUT に
`PC_NEW = WW_INTERRUPTION ? TBR : ...` (080_w_act.vh) の最初の選択も詰め込まれています。
I1 の `PC[31]_i_3` は

```verilog
LUT5 #(.INIT(32'hFFFFFFFE)) \PC[31]_i_3
   (.I0(W_LS_INTCODE[0]), .I1(W_LS_INTCODE[2]), .I2(W_LS_INTCODE[1]),
    .I3(\W_EX_INTCODE_reg_n_0_[2] ), .I4(\W_EX_INTCODE_reg_n_0_[0] ), ...);
```

で、5 入力の OR = `WW_INTERRUPTION` (= `W_LS_INTCODE != 0 | W_EX_INTCODE != 0`, 050_op_lb1.vh) です。
`W_EX_INTCODE[1]` が入っていないのは、EX パイプの割り込みコードが 1 (不正命令) と 4 (オーバーフロー)
だけで bit1 が常に 0 だと合成ツールが見抜き、その FF を消したからです (下の 3.5)。
I2 は残りの選択 (RFE なら XPC, 完了なら MODIFIED_PC, …) の結果です。
他の FF (例えば `START_TRIGGER_BAR_reg`) は `.R(rst)` で、リセットは FF の端子で済んでいます。

**レジスタファイルの読み出し**。`stm_regfile` の中の MUX には、行き先の FF の名前が付いています。

```verilog
MUXF8 \A_EX_OP2_DT_reg[0]_i_7 (.I0(...), .I1(...), .O(...), .S(dd_rad2[3]));
MUXF7 \A_EX_OP2_DT_reg[0]_i_8 (.I0(...), .I1(...), .O(...), .S(dd_rad2[2]));
```

`dd_rad2` (030_d_sec.vh の `DD_RAD2`) で `gr_reg[0..15]` から 1 語を選ぶ 16:1 MUX が
LUT6 → MUXF7 → MUXF8 の木になっていて、その先が `A_EX_OP2_DT` (140_d_dat.vh) の FF です。
RTL の「DD_RAD2 → レジスタファイル → バイパス → A_EX_OP2_DT」という経路が、そのまま
部品の名前に表れています。読み出し 4 ポート・書き込み 2 ポートなので RAM にはならず、
16 語 × 32bit = 512 個の FDRE (`gr_reg[k][i]`) になっています。

**加算器**。分岐先 `DD_TGT` (040_d_bra.vh) は `A_TGT` の FF に入るので、

```verilog
CARRY4 \A_TGT_reg[12]_i_1 (.CI(\A_TGT_reg[8]_i_1_n_0 ), ..., .O(add_32_5_20_return[12:9]), ...);
```

のように `A_TGT_reg[..]_i_1` という名前の CARRY4 が 4bit ごとにつながっています。

**命令キャッシュの RAM**。

```verilog
RAMB36E1 #(.RAM_MODE("SDP"), .READ_WIDTH_A(72), .WRITE_WIDTH_B(72), ...) \g_cache.dram_reg
RAMB18E1 #(.RAM_MODE("SDP"), .READ_WIDTH_A(36), .WRITE_WIDTH_B(36), ...) \g_cache.tram_reg
```

SDP (Simple Dual Port) は「書き 1 ポート + 読み 1 ポート」の使い方で、`stm_icache.v` の
2 つの `always` がそのままこの形になっています。データ RAM は 64bit 幅 (72bit のうち 64bit を使用) × 512,
タグ RAM は 20bit 幅 × 128 です。

**状態機械**。`stm_axi_master.v` の `if_st` (2bit, 3 状態) は `FSM_onehot_if_st_reg[0..2]` の
3 本の FF に作り直されています (ワンホット)。リセットで IDLE の FF だけが 1 になるので、
それが `FDSE` です。

### 3.5 RTL にあってネットリストに無いもの

使われないネットは合成で消えます。RTL には元の CHDL との対応を取るために残してありますが、
ネットリストを探しても見つかりません。

* 命令語のフィールドのうち使われないもの (`I0_JB_IMM12`, `I0_LS_DISP16`, `ILS_RB`, `IEX_RS2` など)
* シミュレーション観測用の `E_STAT` / `B_STAT` / `A_STAT` / `D_STAT`
* 自分自身の保持にしか使われない FF: `W_LATTER_IS_JB`, `E_LS_RADS`, `E_LS_OPS_IS_GR`, `B_EX_RAD2`
* 値が定数だと分かった FF: `W_EX_INTCODE[1]` (EX パイプの割り込みコードは
  `INTCODE_OP` = 1 か `INTCODE_OVF` = 4 なので bit1 は常に 0。`E_EX_INTCODE` などの
  前の段も同じ)

逆に、RTL に名前の無い FF がネットリストに現れることもあります (ワンホットの状態機械, 
ファンアウトを減らすための FF の複製など)。

## 4. プログラムメモリ (`stm_system_ram_0_sim_netlist.v`)

`stm_prog_ram` (`AW=11`, 8KB) は `RAMB36E1` 2 個だけになり、FF も LUT もありません。
`INIT_FILE` で読んだプログラムは、ブロック RAM の `INIT_00`〜`INIT_7F` 属性として
ネットリストの中に 16 進で埋め込まれています。プログラムを変えたら合成し直す必要があるのはこのためです。

## 5. ネットリストを使ったシミュレーション

`*_sim_netlist.v` は UNISIM ライブラリ (`LUT6`, `FDRE` などの振る舞いモデル) があれば
シミュレーションできます (UNISIM が使う `glbl` モジュールはファイルの末尾に入っています)。RTL と同じテストベンチを使えば、合成で動作が変わっていないかを
確かめられます (ただし `-mode funcsim` なので遅延は入っていません。ファイルの先頭のコメントの通り、
SDF による遅延付きのシミュレーションには使えません)。
