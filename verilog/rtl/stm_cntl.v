// =====================================================================
//  stm_cntl.v  -  STM (2-way superscalar 32bit RISC) 本体
//
//  hard/*.ch (CHDL) を Verilog HDL 2001 に変換したもの。
//  CHDL の 1 ファイル = ch/ 以下の 1 つのインクルードファイル。
//
//  CHDL -> Verilog の対応
//    NAME  = 式      (ネット)       ->  assign NAME = 式;
//    NAME := 式      (FF への代入)  ->  assign NAME_NEW = 式;   と
//                                       always @(posedge clk) NAME <= NAME_NEW;
//      (C シミュレータが NAME_NEW に計算してサイクルの最後に NAME へ
//       コピーしていたのと同じ構造)
//    名前中の '-'                    ->  '_'   (例 DD-RAD1 -> DD_RAD1)
//    マクロ (bit_ext, cc_match ...)   ->  function (stm_defs.vh, stm_fmt_*.vh)
//    exu() 関数                       ->  stm_exu モジュール (2 個)
//    GR[] / Mem[]  (045-g-ram.ch)     ->  外部の stm_regfile / stm_memory
//
//  CHDL では各ネットはソース順に評価されるが、元ソースは「使う前に
//  定義する」順序になっている (確認済み) ので、順序に依存しない
//  Verilog の連続代入にそのまま置き換えても同じ動作になる。
//
//  リセット: rst=1 の間のクロックで全 FF を 0 にし, PC だけ RESET_PC にする (同期リセット)。
//            (C 版で PC に開始番地を入れ, 他を 0 から始めたのと同じ。
//             START-TRIGGER-BAR=0 なので最初のサイクルで命令フェッチが始まる)
//
//  stm_cntl.v  -  the core of STM (2-way superscalar 32-bit RISC)
//
//  hard/*.ch (CHDL) converted to Verilog HDL 2001.
//  One CHDL file = one include file under ch/.
//
//  CHDL -> Verilog
//    NAME  = expr    (net)              ->  assign NAME = expr;
//    NAME := expr    (assignment to FF) ->  assign NAME_NEW = expr;   and
//                                           always @(posedge clk) NAME <= NAME_NEW;
//      (the same structure as the C simulator, which computed NAME_NEW and copied it
//       to NAME at the end of the cycle)
//    '-' in names                       ->  '_'   (e.g. DD-RAD1 -> DD_RAD1)
//    macros (bit_ext, cc_match ...)     ->  functions (stm_defs.vh, stm_fmt_*.vh)
//    the exu() function                 ->  the stm_exu module (2 of them)
//    GR[] / Mem[]  (045-g-ram.ch)       ->  the external stm_regfile / stm_memory
//
//  In CHDL each net is evaluated in source order, but the original source is ordered
//  "define before use" (checked), so replacing it with order-independent Verilog
//  continuous assignments gives the same behaviour.
//
//  Reset: on clocks while rst=1, every FF becomes 0 and only PC becomes RESET_PC (synchronous reset).
//         (The same as the C version, which put the start address in PC and started everything
//          else from 0. START-TRIGGER-BAR=0, so instruction fetch starts in the first cycle.)
// =====================================================================
//
// 【解説】パイプラインの構成
//
//   IF : 命令フェッチ。8 バイト (2 命令) ずつ命令キュー IWQ-A/B へ  (170〜200)
//   D  : デコードと発行。最大 2 命令を LS / EX / JB に振り分け     (010〜040, 140, 150)
//   A  : EX パイプの演算 (EXU), LS パイプのアドレス計算 (EAG)       (120, 130)
//   B  : オペランドキャッシュへのアクセス (S ユニット)             (050, 100, 110, 160)
//   E  : LS パイプの ALU (メモリオペランド演算, サブワード整形)    (090)
//   W  : 完了。GR / PC / PSW の更新, 割り込み                       (080)
//   インタロック・取り消し・分岐予測の制御は 060, 070, 210。
//
// [Note] Pipeline structure
//
//   IF : instruction fetch. 8 bytes (2 instructions) at a time into the queues IWQ-A/B (170-200)
//   D  : decode and issue. Up to 2 instructions sorted into LS / EX / JB         (010-040, 140, 150)
//   A  : EX-pipe operation (EXU), LS-pipe address computation (EAG)              (120, 130)
//   B  : operand cache access (S unit)                                           (050, 100, 110, 160)
//   E  : LS-pipe ALU (memory-operand operations, sub-word shaping)               (090)
//   W  : completion. Updates GR / PC / PSW, interrupts                           (080)
//   Interlock, cancellation and branch prediction are controlled in 060, 070, 210.
//
// 【解説】信号名の付け方 (元の CHDL の慣習)
//
//   X_...  (X = A, B, E, W)  : X サイクルにいる命令のタグ。ほとんどが FF で、
//                              命令が次のステージへ進むと次の段の FF へコピーされる
//   XX_... (DD, AA, BB, EE, WW, GG) : X サイクルの組合せ回路 (その場で計算するネット)
//                              GG はステージに属さないグローバルな回路
//   G_...                    : グローバルな FF (分岐の解決状態など)
//   I0, I1                   : 発行候補の 1 命令目, 2 命令目
//   ILS, IEX, IJB            : LS パイプ / EX パイプ / 分岐へ振り分けた命令
//   ..._V                    : 有効ビット (valid)
//   ..._NOCAN                : 有効かつ取り消されていない
//   ..._FWD / ..._INTLK      : 次へ進む / 留まる (インタロック)
//   WAD / RAD                : レジスタの書き込み / 読み出しアドレス (番号)
//   WDT / DT                 : データ
//   ..1 / ..2 (WE1, WAD1 …) : 1 = LS パイプ側, 2 = EX パイプ側 (W_WE1 / W_WE2 など)
//
// [Note] Naming conventions (from the original CHDL)
//
//   X_...  (X = A, B, E, W)  : tags of the instruction in cycle X. Mostly FFs; when the
//                              instruction moves on they are copied to the next stage's FFs
//   XX_... (DD, AA, BB, EE, WW, GG) : combinational logic of cycle X (nets computed on the spot)
//                              GG is global logic that belongs to no stage
//   G_...                    : global FFs (branch resolution state etc.)
//   I0, I1                   : first and second issue candidates
//   ILS, IEX, IJB            : instructions sorted to the LS pipe / EX pipe / branch
//   ..._V                    : valid bit
//   ..._NOCAN                : valid and not cancelled
//   ..._FWD / ..._INTLK      : moves on / stays (interlock)
//   WAD / RAD                : register write / read address (number)
//   WDT / DT                 : data
//   ..1 / ..2 (WE1, WAD1 ...) : 1 = LS-pipe side, 2 = EX-pipe side (W_WE1 / W_WE2 etc.)
//
// 【ネットリスト解説】このモジュールが回路としてどうなるか
//
//   ・このモジュールの中身は「FF の列」と「その D 入力を作る巨大な組合せ回路」
//     の 2 つだけでできている。ch/*.vh の assign はすべて組合せ回路 (LUT) になり、
//     末尾の always ブロックが FF (Xilinx なら FDRE) の列になる。ラッチや
//     クロックゲートは無く、クロックは clk 1 本だけの完全同期回路。
//   ・FF は X と X_NEW の対で宣言してある。ネットリスト上では
//         X_NEW (LUT の出力) --D--> [FF X] --Q--> X (次の段の LUT の入力)
//     という形になり、FF の名前は合成後も "X_reg" (多ビットなら "X_reg[i]")
//     として残るので、合成結果やタイミングレポートで RTL の名前を追える。
//   ・ch/*.vh 同士は、ある .vh の出力ネットを別の .vh が入力として使う形で
//     つながっている (各 .vh の先頭の【ネットリスト解説】に、そのファイルが作る
//     ネットと使い先・使っているネットと作り元を書いた)。
//     ファイルの境界は回路の境界ではなく、合成すると 1 つの組合せ回路に溶け合う。
//   ・おおまかな信号の流れ (矢印 = ネットの向き。[] は FF, 数字は ch/ のファイル):
//
//      命令フェッチ:  [PC] / DD_TGT / AA_EAG_OUTPUT --> 170 --IF_REQ_*--> 190 --> [IB_*] --IB_AD--> メモリ
//                     MEM_DT_IF_H/L --> 180 --I_LBS_H/L--> 200 --> [IWQ_A/B_*]
//      D サイクル:    [IWQ_*] --> 010 --I0,I1--> 015 --> 020 --> 030 --ILS/IEX/IJB--> 035 --> 040
//                     030 --DD_RAD1/2/B--> レジスタファイル --GR_DT_1/2/B--> 140
//                     140 / 150 --> [A_*]
//      A サイクル:    [A_*] --> 120 (EXU, EAG) --AA_EX_RES, AA_EAG_OUTPUT--> 130 --> [B_*]
//                     AA_EAG_OUTPUT --> 060 / 160 (S ユニットの受付) --> [OP_B_*, LBS_*] --> メモリ
//      B サイクル:    MEM_DT_OP --> 050 --OP_LBS_DATA--> 100 ;  [B_*] --> 100 / 110 --> [E_*]
//                     B_LS_RADS --> レジスタファイル --GR_DT_S--> 100
//      E サイクル:    [E_*] --> 090 (ALU) --> [W_*, STB_*]
//      W サイクル:    [W_*] --> 080 --> [PC, PSW_*, TBR, XPC ...] ;  W_WE/WAD/WDT --> レジスタファイル
//
//      070 (インタロック) は E→B→A→D の順に xx_FWD / xx_INTLK を作り、
//      ほぼすべてのステージの FF の「保持 / 更新 / クリア」のマルチプレクサを選ぶ。
//      050 の CANCEL_BY_INT / CANCEL_BY_BC と 210 の G_BC_* も全ステージに配られる
//      (ファンアウトが大きく、合成すると配線遅延の効く信号になる)。
//
//   ・参考: Vivado 2022.2 で xc7a35t (Arty A7-35) 向けに合成した結果
//     (syn/vivado のブロックデザイン, stm_axi_top の中の stm_cntl 部分) は
//     FDRE 約 1600 個, LUT 約 4300 個 (LUT6 が約半分), CARRY4 65 個, MUXF7 49 個。
//     (EXT_BUS=1 の場合。EXT_BUS=0 で stm_cntl だけを合成すると LUT 3,034 / FF 1,623。
//      syn/README.ja.md 参照。差の多くは EXT_BUS=1 で増えるフォワーディングと I/O の回路)
//     CARRY4 (高速キャリー連鎖) は PC の加算, 分岐先 (add_32_5_20),
//     EAG (add_32_16), フェッチ番地 (add_32_4), 2 個の stm_exu の加減算に使われる。
//     LUT の大半はバイパス (140_d_dat.vh) とステージ間の「保持 / 更新」選択。
//
// [Netlist notes] What this module becomes as a circuit
//   - The module consists of just two things: a row of FFs and a huge combinational circuit
//     that builds their D inputs. Every assign in ch/*.vh becomes combinational logic (LUTs),
//     and the always block at the end becomes the row of FFs (FDRE on Xilinx). There are no
//     latches or clock gates; it is a fully synchronous circuit with the single clock clk.
//   - FFs are declared as pairs X and X_NEW. In the netlist they look like
//         X_NEW (LUT output) --D--> [FF X] --Q--> X (input of the LUTs of the next stage)
//     and the FF keeps the name "X_reg" ("X_reg[i]" for multi-bit) after synthesis, so the RTL
//     names can be followed in synthesis results and timing reports.
//   - The ch/*.vh files are connected by one .vh using the output nets of another as inputs
//     (the notes at the top of each .vh list the nets the file makes and who uses them, and the
//     nets it uses and who makes them). File boundaries are not circuit boundaries; after
//     synthesis everything melts into one combinational circuit.
//   - Rough signal flow (arrows = direction of the nets, [] = FFs, numbers = files in ch/):
//
//      Fetch:    [PC] / DD_TGT / AA_EAG_OUTPUT --> 170 --IF_REQ_*--> 190 --> [IB_*] --IB_AD--> memory
//                MEM_DT_IF_H/L --> 180 --I_LBS_H/L--> 200 --> [IWQ_A/B_*]
//      D cycle:  [IWQ_*] --> 010 --I0,I1--> 015 --> 020 --> 030 --ILS/IEX/IJB--> 035 --> 040
//                030 --DD_RAD1/2/B--> register file --GR_DT_1/2/B--> 140
//                140 / 150 --> [A_*]
//      A cycle:  [A_*] --> 120 (EXU, EAG) --AA_EX_RES, AA_EAG_OUTPUT--> 130 --> [B_*]
//                AA_EAG_OUTPUT --> 060 / 160 (S-unit accept) --> [OP_B_*, LBS_*] --> memory
//      B cycle:  MEM_DT_OP --> 050 --OP_LBS_DATA--> 100 ;  [B_*] --> 100 / 110 --> [E_*]
//                B_LS_RADS --> register file --GR_DT_S--> 100
//      E cycle:  [E_*] --> 090 (ALU) --> [W_*, STB_*]
//      W cycle:  [W_*] --> 080 --> [PC, PSW_*, TBR, XPC ...] ;  W_WE/WAD/WDT --> register file
//
//      070 (interlock) makes xx_FWD / xx_INTLK in the order E -> B -> A -> D, and they select
//      the "hold / update / clear" muxes of the FFs of almost every stage.
//      CANCEL_BY_INT / CANCEL_BY_BC from 050 and G_BC_* from 210 also go to every stage
//      (large fan-out; after synthesis they are signals where routing delay matters).
//
//   - For reference: the result of Vivado 2022.2 for xc7a35t (Arty A7-35)
//     (the stm_cntl part inside stm_axi_top in the block design of syn/vivado) is
//     about 1,600 FDRE, about 4,300 LUTs (about half of them LUT6), 65 CARRY4 and 49 MUXF7.
//     (That is with EXT_BUS=1. Synthesizing stm_cntl alone with EXT_BUS=0 gives 3,034 LUTs /
//      1,623 FFs, see syn/README.md. Most of the difference is the forwarding and I/O logic
//      added with EXT_BUS=1.)
//     The CARRY4s (fast carry chains) are used for the PC add, the branch target (add_32_5_20),
//     the EAG (add_32_16), the fetch address (add_32_4) and the add/sub of the two stm_exu.
//     Most LUTs are the bypass (140_d_dat.vh) and the "hold / update" selection between stages.
//
// =====================================================================
module stm_cntl #(                                      // CPU本体: 約1600本のFFとそのD入力を作る組合せ回路だけでできた完全同期回路 / CPU core: ~1600 FFs plus the logic for their D inputs, fully synchronous
  // 0: 元の動作 (メモリは同じサイクルに応答する。stm_sys / stm_memory 用)
  // 1: 外部バス (AXI4) 用。メモリの応答が何サイクル遅れてもよいように、
  //    RANDOM_FOR_OPCLH / RANDOM_FOR_IFCLH を「バスのデータが揃った」合図として
  //    使い、ST2 の書き込みも完了 (RANDOM_FOR_OPCLH) を待つ。stm_axi_top 用。
  // 0: original behaviour (memory answers in the same cycle; for stm_sys / stm_memory)
  // 1: for an external bus (AXI4). So that memory responses may be any number of cycles late,
  //    RANDOM_FOR_OPCLH / RANDOM_FOR_IFCLH are used as "the bus data is ready" signals,
  //    and the ST2 write also waits for completion (RANDOM_FOR_OPCLH). For stm_axi_top.
  parameter EXT_BUS = 0,                                // 0=理想メモリ (stm_sys), 1=外部バス (stm_axi_top). 定数なので使わない回路は合成で消える / 0 ideal memory (stm_sys), 1 external bus (stm_axi_top). A constant, so unused logic is removed
  // I/O 領域 (EXT_BUS=1 のときだけ使う): (番地 & IO_MASK) == IO_BASE の番地。
  // ここへのロードは投機的に実行せず, 先行するストアがすべて終わってから出す。
  // ストアの B サイクルの読み出しもしない (050_op_lb1.vh, 060_g_srq.vh)。
  // I/O region (used only with EXT_BUS=1): addresses with (address & IO_MASK) == IO_BASE.
  // Loads from it are not executed speculatively; they go out after all earlier stores finish.
  // Stores to it do not do the B-cycle read either (050_op_lb1.vh, 060_g_srq.vh).
  parameter        IO_EN   = 1,                         // I/O領域の特別扱いを有効にする (EXT_BUS=1のときだけ効く) / enable special handling of the I/O region (only with EXT_BUS=1)
  parameter [31:0] IO_BASE = 32'hF000_0000,             // I/O領域の先頭 (マスクした比較値) / I/O region base (compare value after masking)
  parameter [31:0] IO_MASK = 32'hF000_0000              // 比較するビット (既定は上位4bit → a[31:28]==Fの4入力AND) / bits compared (default top 4 -> 4-input AND for a[31:28]==F)
) (                                                     // パラメータの終わり, ポートの始まり / end of parameters, start of ports
  input              clk,                               // クロック: 全FFのC端子 (クロックはこの1本だけ) / clock: C pin of every FF (the only clock)
  input              rst,                               // 同期リセット: FDREのR端子へ (高ファンアウト) / synchronous reset: to the FDRE R pins (high fan-out)
  input      [31:0]  RESET_PC,                          // リセット後の開始番地 → PCのFFのD入力の前のMUX / start address after reset -> mux in front of the PC FFs' D

  // キャッシュミス模擬 (C 版の random_clh)。常時 1 ならミス無し。
  // EXT_BUS=1 のときは stm_axi_master からの応答:
  //   RANDOM_FOR_OPCLH = OP-B の要求 (LD/ST の読み出し, ST2 の書き込み) が完了
  //   RANDOM_FOR_IFCLH = IB の命令フェッチ (8 バイト) が届いた (stm_icache から)
  //   RANDOM_FOR_IFRDY = 1 に固定
  // Cache-miss simulation (random_clh of the C version). Always 1 means no misses.
  // With EXT_BUS=1 these are responses from stm_axi_master:
  //   RANDOM_FOR_OPCLH = the OP-B request (LD/ST read, ST2 write) has completed
  //   RANDOM_FOR_IFCLH = the instruction fetch of IB (8 bytes) has arrived (from stm_icache)
  //   RANDOM_FOR_IFRDY = tied to 1
  input              RANDOM_FOR_OPCLH,                  // オペランドの応答 (ヒット/バス完了) → 050, 160 / operand response (hit / bus done) -> 050, 160
  input              RANDOM_FOR_IFRDY,                  // フェッチ要求の受け付け可 → 180 / fetch request ready -> 180
  input              RANDOM_FOR_IFCLH,                  // 命令データが届いた → 180 / fetch data arrived -> 180

  // レジスタファイル (stm_regfile) とのインタフェース
  // interface to the register file (stm_regfile)
  // 【ネットリスト解説】ポートの種類とタイミング
  //   DD_RAD1/2/B   : 組合せ出力 (D サイクルの命令語から作る読み出し番号, 030)。
  //                   stm_regfile の読み出しも組合せなので、同じサイクルのうちに
  //                   GR_DT_1/2/B が戻ってきて 140 のバイパス選択を通り A_*_DT の
  //                   FF に入る。IWQ の FF → デコード → レジスタファイル → バイパス
  //                   → FF が 1 サイクルに収まる必要があり、長い経路の 1 つになる。
  //   B_LS_RADS     : FF 出力 (B サイクルの命令のストアデータ等の番号) → GR_DT_S (100)。
  //   W_WE/WAD/WDT  : FF 出力。W サイクルの命令の書き込み。stm_regfile が次の
  //                   クロックで書き、同じサイクルの読み出しにはバイパスで見せる。
  //
  // [Netlist notes] Kind and timing of the ports
  //   DD_RAD1/2/B   : combinational outputs (register numbers to read, made from the D-cycle
  //                   instruction words, 030). The read of stm_regfile is combinational too, so
  //                   GR_DT_1/2/B come back in the same cycle, go through the bypass selection of
  //                   140 and enter the A_*_DT FFs. IWQ FFs -> decode -> register file -> bypass
  //                   -> FFs has to fit in one cycle, which makes it one of the long paths.
  //   B_LS_RADS     : FF output (register number of the store data etc. of the instruction in B) -> GR_DT_S (100).
  //   W_WE/WAD/WDT  : FF outputs: the writes of the instruction in W. stm_regfile writes them at
  //                   the next clock and shows them to reads in the same cycle through a bypass.
  output     [3:0]   DD_RAD1,                           // 出力ポート=組合せ (030): R1の読み出し番号→rad1: 4bit 2:1 MUX / output port = combinational (030): R1 read number -> rad1: 4-bit 2:1 mux
  output     [3:0]   DD_RAD2,                           // 出力ポート=組合せ (030): R2の読み出し番号→rad2 (特権命令はI0固定): 4bit 2:1 MUX, 選択はLUT1個 / output port = combinational (030): R2 read number -> rad2 (I0 for priv ops): 4-bit 2:1 mux, select in 1 LUT
  output     [3:0]   DD_RADB,                           // 出力ポート=組合せ (030): RBの読み出し番号→stm_regfileのradb: 4bit 2:1 MUX / output port = combinational (030): RB read number -> radb of stm_regfile: 4-bit 2:1 mux
  output reg [3:0]   B_LS_RADS,                         // 出力ポート=FF x4 (D=B_LS_RADS_NEW, 130): RSの番号: CE付きFF4本 → stm_regfileのrads, 100の比較 / output port = 4 FFs (D=B_LS_RADS_NEW, 130): RS number: 4 FFs with CE -> rads of stm_regfile, compares in 100
  input      [31:0]  GR_DT_1,                           // R1の読み出しデータ (stm_regfileの組合せ出力) → 140のバイパスMUX / R1 read data (combinational from stm_regfile) -> bypass mux in 140
  input      [31:0]  GR_DT_2,                           // R2の読み出しデータ → 140 / R2 read data -> 140
  input      [31:0]  GR_DT_B,                           // RBの読み出しデータ → 140 / RB read data -> 140
  input      [31:0]  GR_DT_S,                           // RSの読み出しデータ (Bサイクル) → 100 / RS read data (B cycle) -> 100
  output reg         W_WE1,                             // 出力ポート=FF x1 (D=W_WE1_NEW, 090): LS側のGR書き込み許可: E_FWDとのAND (割り込み/隠しで0) → stm_regfileのwe1 / output port = 1 FF (D=W_WE1_NEW, 090): LS GR write enable: AND with E_FWD (0 on interrupt / hide) -> we1 of stm_regfile
  output reg         W_WE2,                             // 出力ポート=FF x1 (D=W_WE2_NEW, 090): EX側のGR書き込み許可 → we2 / output port = 1 FF (D=W_WE2_NEW, 090): EX GR write enable -> we2
  output reg [3:0]   W_WAD1,                            // 出力ポート=FF x4 (D=W_WAD1_NEW, 090): LS側の書き込み番号をWへ: FF 4本 (D=E_WAD1, 保持無し) / output port = 4 FFs (D=W_WAD1_NEW, 090): LS write number to W: 4 FFs (D = E_WAD1, no hold)
  output reg [3:0]   W_WAD2,                            // 出力ポート=FF x4 (D=W_WAD2_NEW, 090): EX側の書き込み番号をWへ: FF 4本 / output port = 4 FFs (D=W_WAD2_NEW, 090): EX write number to W: 4 FFs
  output reg [31:0]  W_WDT1,                            // 出力ポート=FF x32 (D=W_WDT1_NEW, 090): LS側の書き込みデータ: 通常はALU出力 / output port = 32 FFs (D=W_WDT1_NEW, 090): LS write data: normally the ALU output
  output reg [31:0]  W_WDT2,                            // 出力ポート=FF x32 (D=W_WDT2_NEW, 090): EX側の結果 (Aで計算済み) をWへ: FF32本 / output port = 32 FFs (D=W_WDT2_NEW, 090): EX result (computed in A) to W: 32 FFs

  // メモリ (stm_memory) とのインタフェース
  // interface to the memory (stm_memory)
  // 【ネットリスト解説】LBS_WE/AD/DT と IB_AD はすべて FF 出力 (160, 190)。
  //   メモリへ出る要求は 1 サイクル前に FF に確定しているので、外側の回路
  //   (stm_memory / stm_axi_master / stm_icache) から見てグリッチの無いきれいな信号。
  //   戻りの MEM_DT_OP / MEM_DT_IF_H/L は組合せで 050 / 180 に入り、同じサイクルに
  //   E_LS_LD_DT (100) や IWQ (200) の FF へ取り込まれる。
  //
  // [Netlist notes] LBS_WE/AD/DT and IB_AD are all FF outputs (160, 190).
  //   Requests going out to memory are settled in FFs one cycle earlier, so for the logic
  //   outside (stm_memory / stm_axi_master / stm_icache) they are clean, glitch-free signals.
  //   The returning MEM_DT_OP / MEM_DT_IF_H/L enter 050 / 180 combinationally and are taken
  //   into the E_LS_LD_DT (100) and IWQ (200) FFs in the same cycle.
  output reg         LBS_WE,                            // 出力ポート=FF x1 (D=LBS_WE_NEW, 160): メモリ書き込み許可 → stm_memory / output port = 1 FF (D=LBS_WE_NEW, 160): stm_axi_master (FF) / memory write enable -> stm_memory / stm_axi_master (FF)
  output reg [31:0]  LBS_AD,                            // 出力ポート=FF x32 (D=LBS_AD_NEW, 160): メモリ番地: 保持 / OP-WAITから / output port = 32 FFs (D=LBS_AD_NEW, 160): ... / memory address: hold / from OP-WAIT /
  output reg [31:0]  LBS_DT,                            // 出力ポート=FF x32 (D=LBS_DT_NEW, 160): メモリ書き込みデータ: 32bit 2:1 MUX (OP-WAIT/STB) + CE / output port = 32 FFs (D=LBS_DT_NEW, 160): memory write data: 32-bit 2:1 mux (OP-WAIT / STB) + CE
  input      [31:0]  MEM_DT_OP,                         // オペランドの読み出しデータ → 050のOP_LBS_DATA / operand read data -> OP_LBS_DATA in 050
  input              MEM_OP_ERR,     // EXT_BUS=1: OP-B の読み出しがエラー応答 (RANDOM_FOR_OPCLH と同時)
                                     // EXT_BUS=1: the OP-B read got an error response (together with RANDOM_FOR_OPCLH)
  output reg [31:0]  IB_AD,                             // 出力ポート=FF x32 (D=IB_AD_NEW, 190): 要求中の番地: 受け付けたらIF_REQ_AD, それ以外は保持 (CE付きFF32本) → メモリの番地 / output port = 32 FFs (D=IB_AD_NEW, 190): pending address: IF_REQ_AD when accepted, else hold (32 FFs with CE) -> memory address
  input      [31:0]  MEM_DT_IF_H,                       // フェッチした1語目 → 180 → IWQ_x_4 / first fetched word -> 180 -> IWQ_x_4
  input      [31:0]  MEM_DT_IF_L,                       // フェッチした2語目 → 180 → IWQ_x_5 / second fetched word -> 180 -> IWQ_x_5

  // 外部バス (EXT_BUS=1) 用の要求信号 (stm_axi_master へ)。EXT_BUS=0 では未使用。
  // request signals for the external bus (EXT_BUS=1, to stm_axi_master). Unused with EXT_BUS=0.
  // 【ネットリスト解説】IB_VALID と OP_B_NEW は FF 出力 (IB_V, OP_B_NEW の FF)。
  //   IB_AD_NXT は IB_AD の FF の D 入力 (IB_AD_NEW) をそのまま外へ出した組合せ出力で、
  //   stm_icache はこれをブロック RAM の読み出し番地に使う (RAM の出力レジスタと
  //   IB_AD の FF が同じクロックで更新されるので、次のサイクルに両者が揃う)。
  //   OP_B_BUSREQ は OP-B の FF とアドレス比較から作る組合せ出力 (050)。
  //   stm_sys のように何もつながないと、これらを作る回路は合成で消える。
  //
  // [Netlist notes] IB_VALID and OP_B_NEW are FF outputs (the IB_V and OP_B_NEW FFs).
  //   IB_AD_NXT is a combinational output that brings the D input of the IB_AD FFs (IB_AD_NEW)
  //   out as it is. stm_icache uses it as the read address of its block RAMs (the RAM output
  //   register and the IB_AD FFs update on the same clock, so both match in the next cycle).
  //   OP_B_BUSREQ is a combinational output made from the OP-B FFs and address compares (050).
  //   When nothing is connected, as in stm_sys, the logic making these disappears in synthesis.
  output             IB_VALID,      // IB の命令フェッチ要求が有効 (= IB_V)
                                    // the instruction fetch request of IB is valid (= IB_V)
  output     [31:0]  IB_AD_NXT,     // 次のサイクルの IB_AD (命令キャッシュの先読み用)
                                    // IB_AD of the next cycle (for read-ahead in the instruction cache)
  output reg         OP_B_NEW,      // OP-B に新しい要求が入った最初のサイクル
                                    // the first cycle a new request is in OP-B
  output             OP_B_BUSREQ,   // OP-B の要求にバスアクセスが要る
                                    // the OP-B request needs a bus access

  // 観測用
  // for observation
  output reg [31:0]  PC                                 // 出力ポート=FF x32 (D=PC_NEW, 080): PCの更新: 割り込みでTBR(ハンドラ) / output port = 32 FFs (D=PC_NEW, 080): PC update: TBR (handler) on an interrupt
);                                                      // ポート宣言の終わり / end of ports

`include "stm_const.vh"                                 // 定数 (opcode, 割り込みコードなど) を取り込む / pull in the constants (opcodes, interrupt codes ...)
`include "stm_defs.vh"                                  // 共通の関数 (符号拡張, 加算器, cc_matchなど) / shared functions (sign extension, adders, cc_match ...)
`include "stm_fmt_ls_ex.vh"                             // LS/EX形式のフィールド抽出関数 / field functions of the LS/EX formats
`include "stm_fmt_jb.vh"                                // JB/特権形式のフィールド抽出関数 / field functions of the JB/privileged formats

// (Verilog 版で追加) 番地が I/O 領域か。EXT_BUS=0 では常に 0。
// (added in the Verilog version) Is the address in the I/O region? Always 0 with EXT_BUS=0.
// 【ネットリスト解説】EXT_BUS / IO_EN / IO_MASK / IO_BASE はすべてパラメータ (定数)
//         なので、合成時に「マスクで 1 のビットだけを比べる」比較器に縮む
//         (既定値なら a[31:28] == 4'hF の 4 入力 AND 1 段)。EXT_BUS=0 では
//         定数 0 になり、is_io() を使う回路はまるごと消える。
//
// [Netlist notes] EXT_BUS / IO_EN / IO_MASK / IO_BASE are all parameters (constants),
//         so synthesis shrinks this to a comparator of only the bits that are 1 in the mask
//         (with the defaults, one 4-input AND for a[31:28] == 4'hF). With EXT_BUS=0 it is
//         the constant 0, and every circuit that uses is_io() disappears.
function is_io(input [31:0] a);                         // 番地がI/O領域か (050, 060で使う) / is the address in the I/O region (used in 050, 060)
  is_io = EXT_BUS && IO_EN && ((a & IO_MASK) == IO_BASE); // 定数のマスク比較: 既定ならa[31:28]==Fの4入力AND, EXT_BUS=0なら定数0 / constant masked compare: 4-input AND on a[31:28]==F by default, constant 0 with EXT_BUS=0
endfunction                                             // 関数の終わり / end of function

// ---------------------------------------------------------------------
//  宣言 (元の .ch ファイルごと)。ビット幅は vh/prop.tab, vh/assi.tab による。
//    wire      : CHDL の '='  (組合せ回路のネット)
//    reg       : CHDL の ':=' (FF)。 *_NEW がその D 入力
//  Declarations (grouped by the original .ch file). Bit widths come from vh/prop.tab, vh/assi.tab.
//    wire      : CHDL '='  (a net of combinational logic)
//    reg       : CHDL ':=' (an FF); *_NEW is its D input
//
// 【ネットリスト解説】宣言の読み方
//    ・reg X と wire X_NEW の組が 1 本の FF (多ビットならそのビット数ぶん)。
//    ・wire だけのもの (X_NEW の無いもの) は組合せ回路の途中のネット。
//      FF を通らないので、同じサイクルのうちに別の .vh の式へ伝わる。
//    ・ここで宣言しても、どこからも使われないネットは合成で消える。たとえば
//        - 015 の I0_JB_IMM12 / I0_LS_DISP16 などのフィールド (命令語の一部を
//          切り出すだけで、使われないもの)
//        - 070 の E_STAT など (シミュレーション観測用。tb からも見ていない)
//        - W_LATTER_IS_JB, E_LS_RADS, E_LS_OPS_IS_GR, B_EX_RAD2 の FF
//          (自分自身の保持にしか使われていない。合成結果にも *_reg が無い)
//      これらは元の CHDL にあったものを対応を取りやすくするため残してある。
//
// [Netlist notes] How to read the declarations
//    - A pair reg X / wire X_NEW is one FF (as many as the number of bits).
//    - A wire alone (with no X_NEW) is a net in the middle of the combinational logic.
//      It does not pass through an FF, so it reaches the expressions of other .vh files in the same cycle.
//    - Nets declared here but used nowhere disappear in synthesis. For example
//        - fields of 015 such as I0_JB_IMM12 / I0_LS_DISP16 (they only cut out part of the
//          instruction word, and nothing uses them)
//        - E_STAT etc. in 070 (simulation probes; not even the testbenches look at them)
//        - the FFs W_LATTER_IS_JB, E_LS_RADS, E_LS_OPS_IS_GR, B_EX_RAD2
//          (used only to hold their own value; there is no *_reg for them in the synthesis result)
//      They come from the original CHDL and are kept so the two can be matched easily.
// ---------------------------------------------------------------------

// ---- 010-d-pre.ch
wire           EID;                                     // 組合せ (010): 予測ミスなら現キューを反転: FF4本→XOR/AND→LUT4 1個, 192本のMUX選択線へ高ファンアウト / comb (010): flip queue on mispredict: 4 FFs -> one LUT4, high fan-out select of 192 mux bits
wire [31:0]    IWQ_0;                                   // 組合せ 32bit (010): キューA/Bの0語目を選ぶ: 32bit 2:1 MUX (後段I0/I1のMUXと合成で融合) / comb 32-bit (010): word 0 of queue A/B: 32-bit 2:1 mux (merged with the I0/I1 mux)
wire [31:0]    IWQ_1;                                   // 組合せ 32bit (010): 1語目の2:1 MUX (選択=EID, 32本のLUT入力) / comb 32-bit (010): 2:1 mux for word 1 (select = EID, 32 LUT inputs)
wire [31:0]    IWQ_2;                                   // 組合せ 32bit (010): 2語目の2:1 MUX (選択=EID) / comb 32-bit (010): 2:1 mux for word 2 (select = EID)
wire [31:0]    IWQ_3;                                   // 組合せ 32bit (010): 3語目の2:1 MUX (選択=EID) / comb 32-bit (010): 2:1 mux for word 3 (select = EID)
wire [31:0]    IWQ_4;                                   // 組合せ 32bit (010): 4語目の2:1 MUX (新しく届いた8バイトの前半) / comb 32-bit (010): 2:1 mux for word 4 (first half of the newest 8 bytes)
wire [31:0]    IWQ_5;                                   // 組合せ 32bit (010): 5語目の2:1 MUX (新しく届いた8バイトの後半) / comb 32-bit (010): 2:1 mux for word 5 (second half of the newest 8 bytes)
wire [2:0]     NIP_A;                                   // 組合せ 3bit (010): FFの値^6で本当のNIP: 定数XORはビット1,2の反転(NOT)だけで、LUTに吸収される / comb 3-bit (010): real NIP = FF ^ 6: only bits 1,2 inverted, absorbed into LUTs
wire [2:0]     NIP;                                     // 組合せ 3bit (010): 使うキューの3bit NIP: 3bit 2:1 MUX (LUT3 x3) / comb 3-bit (010): 3-bit NIP of the used queue: 3-bit 2:1 mux (3 LUT3s)
wire           NIP_0;                                   // 組合せ (010): NIP==0 のデコード: 3入力AND (後段MUXの選択線) / comb (010): decode NIP==0: 3-input AND (mux select)
wire           NIP_1;                                   // 組合せ (010): NIP==1 のデコード / comb (010): decode NIP==1
wire           NIP_2;                                   // 組合せ (010): NIP==2 のデコード / comb (010): decode NIP==2
wire           NIP_3;                                   // 組合せ (010): NIP==3 のデコード / comb (010): decode NIP==3
wire           NIP_4;                                   // 組合せ (010): NIP==4 のデコード / comb (010): decode NIP==4
wire           NIP_5;                                   // 組合せ (010): NIP==5 のデコード (6,7はどれも0=キュー空) / comb (010): decode NIP==5 (6,7 give all 0 = queue empty)
wire           V01;                                     // 組合せ (010): 0,1語目の有効ビット: 1bit 2:1 MUX / comb (010): valid bit of words 0,1: 1-bit 2:1 mux
wire           V23;                                     // 組合せ (010): 2,3語目の有効ビット: 1bit 2:1 MUX / comb (010): valid bit of words 2,3: 1-bit 2:1 mux
wire           V45;                                     // 組合せ (010): 4,5語目の有効ビット: 1bit 2:1 MUX / comb (010): valid bit of words 4,5: 1-bit 2:1 mux
wire           I0_V;                                    // 組合せ (010): I0が入る語ペアの有効ビット: NIP(3bit)+V(3本)の6入力→LUT6 1個 / comb (010): valid of I0's word pair: NIP(3)+V(3) = 6 inputs -> one LUT6
wire           I1_V;                                    // 組合せ (010): I1(=NIP+1)の語ペアの有効ビット, NIP>=5で0: LUT6 1個 / comb (010): valid of I1 (=NIP+1), 0 for NIP>=5: one LUT6
wire [31:0]    I0_CANDID;                               // 組合せ 32bit (010): NIPの位置の語を選ぶ優先MUXの前半: one-hotなので実際は6:1 MUX / comb 32-bit (010): first half of the priority mux at NIP: one-hot, so really a 6:1 mux
wire [31:0]    I0;                                      // 組合せ 32bit (010): 無効なら0にマスク: 32本のAND (MUXの最終段LUTに吸収) / comb 32-bit (010): mask to 0 when not valid: 32 ANDs (absorbed into the last mux LUT)
wire [31:0]    I1_CANDID;                               // 組合せ 32bit (010): NIP+1の位置の語を選ぶMUXの前半 (I0より1語ずれた配線) / comb 32-bit (010): first half of the mux at NIP+1 (wired one word later than I0)
wire [31:0]    I1;                                      // 組合せ 32bit (010): I1_Vで0にマスク→015/020のデコーダへ / comb 32-bit (010): mask with I1_V -> decoders in 015/020
// ---- 015-d-i01.ch
wire           I0_LS_STORE;                             // 組合せ (015): I0[28]=ストアか: 1本の配線に名前を付けるだけ(ゲート0) / comb (015): I0[28] = store?: just a name for one wire (no gate)
wire [3:0]     I0_LS_LENG;                              // 組合せ 4bit (015): I0[27:24]=アクセス長(0=語,他=サブワード): 4本の配線 / comb 4-bit (015): I0[27:24] = access length (0 = word): 4 wires
wire [3:0]     I0_LS_RD_RS;                             // 組合せ 4bit (015): I0[23:20]=ロード先/ストア元のGR番号: 配線 / comb 4-bit (015): I0[23:20] = load dest / store source GR: wires
wire [3:0]     I0_LS_RB;                                // 組合せ 4bit (015): I0[19:16]=ベースレジスタ番号: 配線 (EXのRB1と同じビット) / comb 4-bit (015): I0[19:16] = base register: wires (same bits as EX RB1)
wire [15:0]    I0_LS_DISP16;                            // 組合せ 16bit (015): I0[15:0]=変位: どこからも使われず合成で消える (035でILSから取り直す) / comb 16-bit (015): I0[15:0] = displacement: unused, removed by synthesis (035 takes it from ILS)
wire [1:0]     I0_EX_OP2MODE;                           // 組合せ 2bit (015): I0[30:29]=第2オペランド(3=即値,1=レジスタ,2=メモリ): 配線 / comb 2-bit (015): I0[30:29] = operand-2 mode (3 imm, 1 reg, 2 mem): wires
wire           I0_EX_SETCC;                             // 組合せ (015): I0[28]=CCを更新するか (LSのSTOREと同じビット): 配線 / comb (015): I0[28] = set CC? (same bit as LS STORE): wire
wire [3:0]     I0_EX_EXU_OPC;                           // 組合せ 4bit (015): I0[27:24]=演算の種類 (OPC_A..SETHI): 配線 / comb 4-bit (015): I0[27:24] = operation (OPC_A..SETHI): wires
wire [3:0]     I0_EX_RB1;                               // 組合せ 4bit (015): I0[19:16]=第1オペランド/ベースのGR番号: 配線→020,030 / comb 4-bit (015): I0[19:16] = operand 1 / base GR: wires -> 020, 030
wire [3:0]     I0_EX_RS2;                               // 組合せ 4bit (015): I0[15:12]=第2オペランドのGR番号: 配線→020,030 / comb 4-bit (015): I0[15:12] = operand-2 GR: wires -> 020, 030
wire [3:0]     I0_EX_RD;                                // 組合せ 4bit (015): I0[23:20]=書き込み先GR番号: 配線 / comb 4-bit (015): I0[23:20] = destination GR: wires
wire [11:0]    I0_EX_DISP12;                            // 組合せ 12bit (015): I0[11:0]=メモリオペランドの変位: 未使用で消える / comb 12-bit (015): I0[11:0] = memory-operand displacement: unused, removed
wire           I0_JB_COND;                              // 組合せ (015): I0[27]=条件分岐か: 配線 / comb (015): I0[27] = conditional?: wire
wire           I0_JB_REG;                               // 組合せ (015): I0[26]=レジスタ+変位の分岐か (0=PC相対): 配線 / comb (015): I0[26] = register+disp branch? (0 = PC-relative): wire
wire           I0_JB_LINK;                              // 組合せ (015): I0[25]=戻り番地をGRへ保存するか: 配線 / comb (015): I0[25] = save return address to GR?: wire
wire           I0_JB_CMP;                               // 組合せ (015): I0[24]=2つのGRを比較して分岐するか: 配線 / comb (015): I0[24] = compare two GRs and branch?: wire
wire [3:0]     I0_JB_RD_MASK;                           // 組合せ 4bit (015): I0[23:20]=リンク先GRまたはCCマスク: 配線 / comb 4-bit (015): I0[23:20] = link GR or CC mask: wires
wire [3:0]     I0_JB_RB1;                               // 組合せ 4bit (015): I0[19:16]=ベース/比較の第1GR: 配線 / comb 4-bit (015): I0[19:16] = base / first compare GR: wires
wire [3:0]     I0_JB_R2_IMM4;                           // 組合せ 4bit (015): I0[15:12]=比較の第2GR: 配線 / comb 4-bit (015): I0[15:12] = second compare GR: wires
wire [11:0]    I0_JB_IMM12;                             // 組合せ 12bit (015): I0[11:0]=比較分岐の変位: 未使用で消える / comb 12-bit (015): I0[11:0] = compare-branch displacement: unused, removed
wire           I1_LS_STORE;                             // 組合せ (015): I1[28]=ストアか: 配線 / comb (015): I1[28] = store?: wire
wire [3:0]     I1_LS_LENG;                              // 組合せ 4bit (015): I1[27:24]=アクセス長: 配線 / comb 4-bit (015): I1[27:24] = access length: wires
wire [3:0]     I1_LS_RD_RS;                             // 組合せ 4bit (015): I1[23:20]=ロード先/ストア元: 配線 / comb 4-bit (015): I1[23:20] = load dest / store source: wires
wire [3:0]     I1_LS_RB;                                // 組合せ 4bit (015): I1[19:16]=ベースレジスタ: 配線 / comb 4-bit (015): I1[19:16] = base register: wires
wire [15:0]    I1_LS_DISP16;                            // 組合せ 16bit (015): I1[15:0]=変位: 未使用で消える / comb 16-bit (015): I1[15:0] = displacement: unused, removed
wire [1:0]     I1_EX_OP2MODE;                           // 組合せ 2bit (015): I1[30:29]=第2オペランドの種類: 配線 / comb 2-bit (015): I1[30:29] = operand-2 mode: wires
wire           I1_EX_SETCC;                             // 組合せ (015): I1[28]=CC更新: 配線 / comb (015): I1[28] = set CC: wire
wire [3:0]     I1_EX_EXU_OPC;                           // 組合せ 4bit (015): I1[27:24]=演算の種類: 配線 / comb 4-bit (015): I1[27:24] = operation: wires
wire [3:0]     I1_EX_RB1;                               // 組合せ 4bit (015): I1[19:16]=第1オペランドGR: 配線 / comb 4-bit (015): I1[19:16] = operand-1 GR: wires
wire [3:0]     I1_EX_RS2;                               // 組合せ 4bit (015): I1[15:12]=第2オペランドGR: 配線 / comb 4-bit (015): I1[15:12] = operand-2 GR: wires
wire [3:0]     I1_EX_RD;                                // 組合せ 4bit (015): I1[23:20]=書き込み先GR: 配線 / comb 4-bit (015): I1[23:20] = destination GR: wires
wire [11:0]    I1_EX_DISP12;                            // 組合せ 12bit (015): I1[11:0]=変位: 未使用で消える / comb 12-bit (015): I1[11:0] = displacement: unused, removed
wire           I1_JB_COND;                              // 組合せ (015): I1[27]=条件分岐: 配線 / comb (015): I1[27] = conditional: wire
wire           I1_JB_REG;                               // 組合せ (015): I1[26]=レジスタ相対: 配線 / comb (015): I1[26] = register-relative: wire
wire           I1_JB_LINK;                              // 組合せ (015): I1[25]=リンク: 配線 / comb (015): I1[25] = link: wire
wire           I1_JB_CMP;                               // 組合せ (015): I1[24]=比較分岐: 配線 / comb (015): I1[24] = compare branch: wire
wire [3:0]     I1_JB_RD_MASK;                           // 組合せ 4bit (015): I1[23:20]=リンク先/CCマスク: 配線 / comb 4-bit (015): I1[23:20] = link GR / CC mask: wires
wire [3:0]     I1_JB_RB1;                               // 組合せ 4bit (015): I1[19:16]=ベース/比較の第1GR: 配線 / comb 4-bit (015): I1[19:16] = base / first compare GR: wires
wire [3:0]     I1_JB_R2_IMM4;                           // 組合せ 4bit (015): I1[15:12]=比較の第2GR: 配線 / comb 4-bit (015): I1[15:12] = second compare GR: wires
wire [11:0]    I1_JB_IMM12;                             // 組合せ 12bit (015): I1[11:0]=変位: 未使用で消える / comb 12-bit (015): I1[11:0] = displacement: unused, removed
wire           I0_IS_LEGAL;                             // 組合せ (015): I0の上位8bit+PSW_USERの9入力→LUT2~3個の正当性判定 / comb (015): legality of I0 from top 8 bits + PSW_USER (9 inputs -> 2-3 LUTs)
wire           I1_IS_LEGAL;                             // 組合せ (015): I1の正当性判定 (I0と同じ回路をもう1組) / comb (015): legality of I1 (a second copy of the same logic)
wire [2:0]     I0_LS_OPC_H;                             // 組合せ 3bit (015): I0[31:29]: 100ならLS形式 (020で比較) / comb 3-bit (015): I0[31:29]: 100 means LS format (compared in 020)
wire           I0_EX_OPC_H;                             // 組合せ (015): I0[31]: 0ならEX形式の候補 / comb (015): I0[31]: 0 means EX-format candidate
wire [3:0]     I0_INSN_OPC;                             // 組合せ 4bit (015): I0[31:28]: 1011=JB, 1100=特権命令 / comb 4-bit (015): I0[31:28]: 1011 = JB, 1100 = privileged
wire [1:0]     I0_PRIV_OPC;                             // 組合せ 2bit (015): I0[25:24]: 特権命令の種類 1=RFE 2=RSR 3=WSR / comb 2-bit (015): I0[25:24]: privileged kind 1 RFE, 2 RSR, 3 WSR
wire [2:0]     I1_LS_OPC_H;                             // 組合せ 3bit (015): I1[31:29]: LS形式判定用 / comb 3-bit (015): I1[31:29]: for LS-format decode
wire           I1_EX_OPC_H;                             // 組合せ (015): I1[31]: EX形式判定用 / comb (015): I1[31]: for EX-format decode
wire [3:0]     I1_INSN_OPC;                             // 組合せ 4bit (015): I1[31:28]: JB/特権の判定用 (I1のPRIV_OPCは不要なので無い) / comb 4-bit (015): I1[31:28]: JB / priv decode (I1 needs no PRIV_OPC)
// ---- 020-d-iss.ch
wire           DD_I0_LS_FMT;                            // 組合せ (020): I0[31:29]==100ならLS形式: 3入力AND (LUT3) / comb (020): LS format if I0[31:29]==100: 3-input AND (LUT3)
wire           DD_I0_EX_FMT;                            // 組合せ (020): I0[31]=0かつOP2MODE!=0ならEX形式: 3入力のLUT / comb (020): EX format if I0[31]=0 and OP2MODE!=0: 3-input LUT
wire           DD_I0_JB_FMT;                            // 組合せ (020): I0[31:28]==1011ならJB形式: 4入力AND (LUT4) / comb (020): JB format if I0[31:28]==1011: 4-input AND (LUT4)
wire           DD_I1_LS_FMT;                            // 組合せ (020): I1のLS形式判定 (I0と同じデコーダの2組目) / comb (020): LS format of I1 (second copy of the decoder)
wire           DD_I1_EX_FMT;                            // 組合せ (020): I1のEX形式判定 / comb (020): EX format of I1
wire           DD_I1_JB_FMT;                            // 組合せ (020): I1のJB形式判定 / comb (020): JB format of I1
wire           DD_FIRST_IS_LS;                          // 組合せ (020): I0がLSパイプへ: LS形式またはEXのRMモード (LUT1個) / comb (020): I0 goes to the LS pipe: LS format or EX RM mode (1 LUT)
wire           DD_SECOND_IS_LS;                         // 組合せ (020): I1がLSパイプへ (同上) / comb (020): I1 goes to the LS pipe (same)
wire           DD_FIRST_IS_EX;                          // 組合せ (020): I0がEXパイプへ: EX形式でRM以外 (RR/RI) / comb (020): I0 goes to the EX pipe: EX format, not RM (RR/RI)
wire           DD_SECOND_IS_EX;                         // 組合せ (020): I1がEXパイプへ / comb (020): I1 goes to the EX pipe
wire           DD_FIRST_IS_JB;                          // 組合せ (020): I0が分岐: DD_I0_JB_FMTの別名 (ゲート無し) / comb (020): I0 is a branch: alias of DD_I0_JB_FMT (no gate)
wire           DD_SECOND_IS_JB;                         // 組合せ (020): I1が分岐: 別名 / comb (020): I1 is a branch: alias
wire [1:0]     DD_PRIVCODE;                             // 組合せ 2bit (020): I0が特権命令(1100)なら種類, 違えば0: 2bit x (4入力一致AND) / comb 2-bit (020): kind if I0 is privileged (1100), else 0: 2 bits gated by a 4-input match
wire           DD_SECOND_PRIV_V;                        // 組合せ (020): I1が特権命令か: LUT4 (030で同時発行を止める) / comb (020): is I1 privileged: LUT4 (030 blocks dual issue)
wire           DD_FIRST_SETCC;                          // 組合せ (020): I0がCCを変える: EX形式 & SETCCビット (AND) / comb (020): I0 sets CC: EX format AND SETCC bit
wire [3:0]     DD_FIRST_WAD;                            // 組合せ 4bit (020): I0の書き込み先番号 = I0[23:20] (配線) / comb 4-bit (020): I0 write register number = I0[23:20] (wires)
wire           DD_FIRST_WAD_V;                          // 組合せ (020): I0がGRへ書くか: ロード(非ストア) / comb (020): does I0 write a GR: a load (not a store)
wire           DD_FIRST_RADB_V;                         // 組合せ (020): I0がベースレジスタRBを読む: LSパイプ行き or レジスタ間接分岐 / comb (020): I0 reads base RB: LS pipe or register-indirect branch
wire           DD_FIRST_RAD2_V;                         // 組合せ (020): I0が第2オペランドR2を読む: RRモード / comb (020): I0 reads operand R2: RR mode
wire           DD_FIRST_RAD1_V;                         // 組合せ (020): I0がR1を読む: RIモード or R2を読む命令すべて (OR 1段) / comb (020): I0 reads R1: RI mode or anything that reads R2 (one OR)
wire [3:0]     DD_FIRST_RADB1;                          // 組合せ 4bit (020): I0のR1/RB番号 I0[19:16]: 未使用で合成で消える / comb 4-bit (020): I0 R1/RB number I0[19:16]: unused, removed by synthesis
wire [3:0]     DD_FIRST_RAD2;                           // 組合せ 4bit (020): I0のR2番号 I0[15:12]: 未使用で消える / comb 4-bit (020): I0 R2 number I0[15:12]: unused, removed
wire           DD_SECOND_SETCC;                         // 組合せ (020): I1がCCを変える (I0と同じ形) / comb (020): I1 sets CC (same form as I0)
wire [3:0]     DD_SECOND_WAD;                           // 組合せ 4bit (020): I1の書き込み先番号 I1[23:20] (配線) / comb 4-bit (020): I1 write register number I1[23:20] (wires)
wire           DD_SECOND_WAD_V;                         // 組合せ (020): I1がGRへ書くか: ロード / comb (020): does I1 write a GR: a load
wire           DD_SECOND_RADB_V;                        // 組合せ (020): I1がRBを読む / comb (020): I1 reads RB
wire           DD_SECOND_RAD2_V;                        // 組合せ (020): I1がR2を読む: RRモード / comb (020): I1 reads R2: RR mode
wire           DD_SECOND_RAD1_V;                        // 組合せ (020): I1がR1を読む / comb (020): I1 reads R1
wire [3:0]     DD_SECOND_RADB1;                         // 組合せ 4bit (020): I1のR1/RB番号: 未使用で消える / comb 4-bit (020): I1 R1/RB number: unused, removed
wire [3:0]     DD_SECOND_RAD2;                          // 組合せ 4bit (020): I1のR2番号: 未使用で消える / comb 4-bit (020): I1 R2 number: unused, removed
// ---- 030-d-sec.ch
wire           I0_V_NOINT;                              // 組合せ (030): I0が有効かつ合法 (AND 1個): 発行してよい1命令目 / comb (030): I0 valid and legal (one AND): first insn may issue
wire [2:0]     DD_INTCODE;                              // 組合せ 3bit (030): 不正ならINTCODE_OP(=1): 3bitのうちbit0だけがNOT(I0_IS_LEGAL), 残りは0固定 / comb 3-bit (030): INTCODE_OP (=1) if illegal: only bit 0 = NOT legal, the rest tied to 0
wire           DD_ISSUE_SECOND_INSN;                    // 組合せ (030): 2命令目も発行するか: 下の全条件のAND (Dサイクルで最も深い論理, LUT 3~4段) / comb (030): dual issue?: AND of all terms below (deepest D-cycle logic, 3-4 LUT levels)
wire           ILS_V;                                   // 組合せ (030): LSパイプへ発行する命令がある: AND-OR (LUT1個) → 150のA_LS_V / comb (030): an insn issues to the LS pipe: AND-OR (1 LUT) -> A_LS_V in 150
wire [31:0]    ILS;                                     // 組合せ 32bit (030): LSパイプの命令語: I0優先 / comb 32-bit (030): LS-pipe insn word: I0 first
wire           IEX_V;                                   // 組合せ (030): EXパイプへ発行する命令がある → 150のA_EX_V / comb (030): an insn issues to the EX pipe -> A_EX_V in 150
wire [31:0]    IEX;                                     // 組合せ 32bit (030): EXパイプの命令語: I0優先 / comb 32-bit (030): EX-pipe insn word: I0 first
wire           IJB_V;                                   // 組合せ (030): 分岐命令を発行する → 040/150/210 / comb (030): a branch issues -> 040/150/210
wire [31:0]    IJB;                                     // 組合せ 32bit (030): 分岐の命令語: I0優先 / comb 32-bit (030): branch insn word: I0 first
// ---- 035-d-ixx.ch
wire           ILS_STORE;                               // 組合せ (035): ILS[28]=ストアか: 配線 → 150のA_LS_STORE / comb (035): ILS[28] = store?: wire -> A_LS_STORE in 150
wire [3:0]     ILS_LENG;                                // 組合せ 4bit (035): ILS[27:24]=アクセス長: 配線 / comb 4-bit (035): ILS[27:24] = access length: wires
wire [3:0]     ILS_RD_RS;                               // 組合せ 4bit (035): ILS[23:20]=ロード先/ストア元: 配線 / comb 4-bit (035): ILS[23:20] = load dest / store source: wires
wire [3:0]     ILS_RB;                                  // 組合せ 4bit (035): ILS[19:16]=ベース: 未使用で消える (番号はDD_RADBで読み済み) / comb 4-bit (035): ILS[19:16] = base: unused, removed (already read via DD_RADB)
wire [15:0]    ILS_DISP16;                              // 組合せ 16bit (035): ILS[15:0]=変位 → 040のDD_DISP (EAGの加算器入力) / comb 16-bit (035): ILS[15:0] = displacement -> DD_DISP in 040 (EAG adder input)
wire [1:0]     ILS_OP2MODE;                             // 組合せ 2bit (035): ILS[30:29]: EX-RM形式の判定に使う / comb 2-bit (035): ILS[30:29]: used for the EX-RM format check
wire           ILS_SETCC;                               // 組合せ (035): ILS[28]: メモリオペランド演算がCCを変えるか / comb (035): ILS[28]: does the mem-operand op set CC
wire [3:0]     ILS_EXU_OPC;                             // 組合せ 4bit (035): ILS[27:24]: メモリオペランド演算の種類 (EのALUへ) / comb 4-bit (035): ILS[27:24]: mem-operand operation (to the E ALU)
wire [3:0]     ILS_RS2;                                 // 組合せ 4bit (035): ILS[15:12]: EX-RMのレジスタ側オペランドRS → 150のA_LS_RADS (Bで読む) / comb 4-bit (035): ILS[15:12]: EX-RM register operand RS -> A_LS_RADS in 150 (read in B)
wire [3:0]     ILS_RD;                                  // 組合せ 4bit (035): ILS[23:20]: 未使用で消える (RD_RSと同じビット) / comb 4-bit (035): ILS[23:20]: unused, removed (same bits as RD_RS)
wire [11:0]    ILS_DISP12;                              // 組合せ 12bit (035): ILS[11:0]: EX-RMの変位 → 040のDD_DISP / comb 12-bit (035): ILS[11:0]: EX-RM displacement -> DD_DISP in 040
wire [1:0]     IEX_OP2MODE;                             // 組合せ 2bit (035): IEX[30:29]: RR/RIの区別 → 140 (即値かレジスタか) / comb 2-bit (035): IEX[30:29]: RR or RI -> 140 (immediate or register)
wire           IEX_SETCC;                               // 組合せ (035): IEX[28]: CCを変えるか → 150 / comb (035): IEX[28]: set CC -> 150
wire [3:0]     IEX_EXU_OPC;                             // 組合せ 4bit (035): IEX[27:24]: EXUの演算 → 150のA_EX_OPC / comb 4-bit (035): IEX[27:24]: EXU operation -> A_EX_OPC in 150
wire [3:0]     IEX_RB1;                                 // 組合せ 4bit (035): IEX[19:16]: 未使用で消える / comb 4-bit (035): IEX[19:16]: unused, removed
wire [3:0]     IEX_RS2;                                 // 組合せ 4bit (035): IEX[15:12]: 未使用で消える / comb 4-bit (035): IEX[15:12]: unused, removed
wire [3:0]     IEX_RD;                                  // 組合せ 4bit (035): IEX[23:20]: 書き込み先 → 150のA_EX_WAD / comb 4-bit (035): IEX[23:20]: destination -> A_EX_WAD in 150
wire [11:0]    IEX_DISP12;                              // 組合せ 12bit (035): IEX[11:0]: 未使用で消える / comb 12-bit (035): IEX[11:0]: unused, removed
wire           IJB_COND;                                // 組合せ (035): IJB[27]: 条件分岐 → 040, 210 / comb (035): IJB[27]: conditional -> 040, 210
wire           IJB_REG;                                 // 組合せ (035): IJB[26]: レジスタ相対 → 040 (EAGを使うか) / comb (035): IJB[26]: register-relative -> 040 (uses the EAG)
wire           IJB_LINK;                                // 組合せ (035): IJB[25]: リンク → 140, 150 (戻り番地をEXパイプで書く) / comb (035): IJB[25]: link -> 140, 150 (return address written via EX pipe)
wire           IJB_CMP;                                 // 組合せ (035): IJB[24]: 比較分岐 / comb (035): IJB[24]: compare branch
wire [3:0]     IJB_RD_MASK;                             // 組合せ 4bit (035): IJB[23:20]: リンク先GRまたはCCマスク → 150, 210 / comb 4-bit (035): IJB[23:20]: link GR or CC mask -> 150, 210
wire [3:0]     IJB_RB1;                                 // 組合せ 4bit (035): IJB[19:16]: 未使用で消える / comb 4-bit (035): IJB[19:16]: unused, removed
wire [3:0]     IJB_R2_IMM4;                             // 組合せ 4bit (035): IJB[15:12]: 未使用で消える / comb 4-bit (035): IJB[15:12]: unused, removed
wire [11:0]    IJB_IMM12;                               // 組合せ 12bit (035): IJB[11:0]: 未使用で消える (比較分岐は未完成) / comb 12-bit (035): IJB[11:0]: unused, removed (compare branch unfinished)
wire [15:0]    IEX_IMM16;                               // 組合せ 16bit (035): IEX[15:0]: RIモードの即値 → 140で符号拡張 / comb 16-bit (035): IEX[15:0]: RI-mode immediate -> sign-extended in 140
wire [15:0]    IJB_IMM16;                               // 組合せ 16bit (035): IJB[15:0]: レジスタ相対分岐の変位 → 040 / comb 16-bit (035): IJB[15:0]: register-relative displacement -> 040
wire [19:0]    IJB_IMM20;                               // 組合せ 20bit (035): IJB[19:0]: PC相対の変位 → 040のDD_TGT加算器 / comb 20-bit (035): IJB[19:0]: PC-relative displacement -> DD_TGT adder in 040
wire           IJB_BACKWARD;                            // 組合せ (035): IJB[19]: 変位の符号=後ろ向き分岐 → 静的予測 (後ろ向きは成立と予測) / comb (035): IJB[19]: sign = backward -> static prediction (backward = taken)
wire [2:0]     ILS_LS_OPC_H;                            // 組合せ 3bit (035): ILS[31:29]: LS形式判定用 / comb 3-bit (035): ILS[31:29]: for LS-format check
wire           ILS_EX_OPC_H;                            // 組合せ (035): ILS[31]: EX形式判定用 / comb (035): ILS[31]: for EX-format check
wire           ILS_LS_FMT;                              // 組合せ (035): 本物のロード/ストア: 3bit一致とILS_VのAND (LUT4) / comb (035): a real load/store: 3-bit match AND ILS_V (LUT4)
wire           ILS_EXRM_FMT;                            // 組合せ (035): メモリオペランド演算: ILS[31]=0 & OP2MODE!=0 & ILS_V (LUT4) / comb (035): mem-operand op: ILS[31]=0 & OP2MODE!=0 & ILS_V (LUT4)
// ---- 040-d-bra.ch
wire [31:0]    DD_JB_INSN_AD_PART1;                     // 組合せ 32bit (040): 最後に入れた8バイトのフェッチ番地(下位3bitを0): 29bit 2:1 MUX, 下位3bitはGND / comb 32-bit (040): fetch address of the last 8 bytes (low 3 bits 0): 29-bit 2:1 mux, low 3 bits tied to GND
wire [5:0]     DD_JB_INSN_AD_PART2;                     // 組合せ 6bit (040): 相対位置(6bit) = -(16|8)+4*NIP+(2命令目なら4): 入力5本だけなのでLUT5 x6の真理値表 (加算器にならない) / comb 6-bit (040): relative offset (6 bits): only 5 inputs, so a truth table of 6 LUT5s (no adder)
wire           IJB_IS_BA;                               // 組合せ (040): 無条件・PC相対 (BA): 4入力AND → 170 / comb (040): unconditional, PC-relative (BA): 4-input AND -> 170
wire           IJB_IS_JA;                               // 組合せ (040): 無条件・レジスタ間接 (JA): 4入力AND → 170 (分岐先はAのEAGで計算) / comb (040): unconditional, register-indirect (JA): 4-input AND -> 170 (target from the EAG in A)
wire           IJB_IS_BL;                               // 組合せ (040): リンク付き・PC相対 (BL): 3入力AND / comb (040): with link, PC-relative (BL): 3-input AND
wire           IJB_IS_JL;                               // 組合せ (040): リンク付き・レジスタ間接 (JL): 3入力AND / comb (040): with link, register-indirect (JL): 3-input AND
wire           IJB_IS_BC;                               // 組合せ (040): 条件分岐 (BC): 2入力AND / comb (040): conditional branch (BC): 2-input AND
wire           DD_SETCC;                                // 組合せ (040): 同時発行する1命令目がCCを変えるか: 別名 (ゲート無し) / comb (040): does the co-issued first insn set CC: alias (no gate)
wire           DD_ISSUEING_SOLVED_BC;                   // 組合せ (040): BCのCCが確定済み: A/B/EのSETCC FF 4本と / comb (040): BC's CC already known: 4 SETCC FFs of A/B/E and
wire [1:0]     DD_CC_FOR_SOLVED_BC;                     // 組合せ 2bit (040): CCのフォワーディング: B(EX)の結果を最優先 / comb 2-bit (040): CC forwarding: B (EX) result first
wire           DD_SOLVED_BC_TAKEN;                      // 組合せ (040): mask[3-cc]: CC(2bit)でマスク4bitの1本を選ぶ4:1 MUX → LUT6 1個 / comb (040): mask[3-cc]: CC picks 1 of 4 mask bits, a 4:1 mux in one LUT6
wire           DD_ISSUEING_TAKEN_BRANCH;                // 組合せ (040): Dで成立が確定する分岐: 解決済みBCで成立 / comb (040): branch known taken in D: solved BC taken
wire           DD_ISSUEING_UNTAKEN_BC;                  // 組合せ (040): 解決済みで不成立のBC (そのまま次の命令へ) / comb (040): solved BC not taken (go straight on)
wire           DD_ISSUEING_UNSOLVED_BC;                 // 組合せ (040): 未解決のBC: 予測で進め, 210のG_BCで答え合わせ / comb (040): unsolved BC: proceed by prediction, checked by G_BC in 210
wire           DD_ISSUEING_UNSOLVED_BC_ON_D_EX;         // 組合せ (040): CCを作るのは同時発行の1命令目(EX) / comb (040): CC comes from the co-issued first insn (EX)
wire           DD_ISSUEING_UNSOLVED_BC_ON_D_LS;         // 組合せ (040): CCを作るのは同時発行の1命令目(LS) / comb (040): CC comes from the co-issued first insn (LS)
wire           DD_ISSUEING_UNSOLVED_BC_ON_A_EX;         // 組合せ (040): AのEX命令がCCを作る / comb (040): the EX insn in A makes the CC
wire           DD_ISSUEING_UNSOLVED_BC_ON_A_LS;         // 組合せ (040): AのLS命令がCCを作る / comb (040): the LS insn in A makes the CC
wire           DD_ISSUEING_UNSOLVED_BC_ON_B_LS;         // 組合せ (040): BのLS命令が最新のCCを作る (A側は無し) / comb (040): the LS insn in B makes the latest CC (none in A)
wire           DD_ISSUEING_UNSOLVED_BC_ON_E_LS;         // 組合せ (040): EのLS命令が最新のCCを作る / comb (040): the LS insn in E makes the latest CC
wire           DD_PREDICTING_TAKEN;                     // 組合せ (040): 静的予測: 後方分岐(IJB[19]=1)なら成立と予測 (AND) / comb (040): static prediction: taken if backward (IJB[19]=1) (AND)
wire [15:0]    DD_DISP;                                 // 組合せ 16bit (040): EAGへの16bit変位: LSはDISP16 / comb 16-bit (040): 16-bit displacement to the EAG: LS uses DISP16
wire [31:0]    DD_TGT;                                  // 組合せ 32bit (040): 分岐先 = PART1+PART2+IMM20: 32bit 3入力加算 (CARRY4の連鎖2本 or 3:2圧縮+CARRY4) / comb 32-bit (040): target = PART1+PART2+IMM20: 32-bit 3-input add (CARRY4 chains)
// ---- 045-g-ram.ch
// ---- 050-op-lb1.ch
wire           WW_WSR;                                  // 組合せ (050): WにWSRがある: 2bit一致 (W_PRIVCODE==3, AND2) / comb (050): WSR in W: 2-bit match (W_PRIVCODE==3, AND2)
wire           WW_RFE;                                  // 組合せ (050): WにRFEがある: 2bit一致 (==1) / comb (050): RFE in W: 2-bit match (==1)
wire           WW_LS_INT_V;                             // 組合せ (050): LSパイプ側の割り込みあり: 3bitのOR / comb (050): LS-side interrupt: OR of 3 bits
wire           WW_EX_INT_V;                             // 組合せ (050): EXパイプ側の割り込みあり: 3bitのOR / comb (050): EX-side interrupt: OR of 3 bits
wire           WW_STATECHANGE;                          // 組合せ (050): WSRでSR0~3を書いた: WAD2[3:2]==0 & WSR (LUT4) / comb (050): WSR to SR 0-3: WAD2[3:2]==0 & WSR (LUT4)
wire           WW_INTERRUPTION;                         // 組合せ (050): Wで割り込みが起きる → 080/190/210 / comb (050): an interrupt happens in W -> 080/190/210
wire           CANCEL_BY_INT;                           // 組合せ (050): 全命令の取り消し: W段FFから2段程度のOR, 全ステージのNOCANへ巨大ファンアウト / comb (050): cancel everything: ~2 OR levels from W FFs, huge fan-out to every NOCAN
wire           CANCEL_BY_BC;                            // 組合せ (050): 予測ミス: G_BCのFF3本から XOR+AND (LUT3 1個), 投機命令を消す / comb (050): misprediction: XOR+AND of 3 G_BC FFs (one LUT3), kills speculative insns
wire           OP_B_CANCELLED;                          // 組合せ (050): OP-Bの要求を取り消す: ST2以外は割り込みで / comb (050): cancel the OP-B request: non-ST2 by interrupt
wire           OP_WAIT_CANCELLED;                       // 組合せ (050): OP-WAITの要求を取り消す (OP-Bと同じ形) / comb (050): cancel the OP-WAIT request (same as OP-B)
wire           OP_B_V_NOCAN;                            // 組合せ (050): OP-Bに有効で取り消されない要求 (AND) → 160, OP_B_BUSREQ / comb (050): live OP-B request (AND) -> 160, OP_B_BUSREQ
wire           OP_WAIT_V_NOCAN;                         // 組合せ (050): OP-WAITに有効で取り消されない要求 → 160 / comb (050): live OP-WAIT request -> 160
wire [2:0]     OP_B_INTCODE;                            // 組合せ 3bit (050): Sユニットの例外コード: 比較一致はCMP(2) / comb 3-bit (050): S-unit exception code: CMP (2) on a match
wire           B_OPCLH;                                 // 組合せ (050): キャッシュの応答(ヒット): LD/STで / comb (050): cache response (hit): LD/ST and
wire           SU_OP_RDY;                               // 組合せ (050): 新規L/STを受け付けられる = OP-WAITが空 (NOT 1個) / comb (050): can accept a new L/ST = OP-WAIT empty (one NOT)
wire           SU_ST_RDY;                               // 組合せ (050): ST2を受け付けられる (同じ信号, 合成で1本にまとまる) / comb (050): can accept ST2 (same signal, merged by synthesis)
wire [31:0]    OP_LBS_DATA;                             // 組合せ 32bit (050): ロードデータ: ミスなら目印0xdead0a0a / comb 32-bit (050): load data: marker 0xdead0a0a on a miss
wire           OP_FWD_E;                                // 組合せ (050): EのストアとLBS_ADが一致: 32bit比較器, Eのデータをロードへ転送 / comb (050): E store matches LBS_AD: 32-bit comparator, forward E data to the load
wire           OP_FWD_STB;                              // 組合せ (050): STBのストアと一致: 32bit比較器, STB_DTを転送 / comb (050): STB store matches: 32-bit comparator, forward STB_DT
wire           OP_B_CMP_INT;                            // 組合せ (050): アドレス比較割り込み: LD/STで / comb (050): address-compare interrupt: LD/ST and
wire           OP_B_BUS_ERR;                            // 組合せ (050): バスのエラー応答: EXT_BUS=0なら定数0で回路ごと消える / comb (050): bus error response: constant 0 (removed) when EXT_BUS=0
wire           OP_B_IO_ST;                              // 組合せ (050): I/O領域へのストア (読まずにヒット): is_ioは上位ビットのマスク比較 / comb (050): store to I/O space (hit without reading): is_io is a masked compare
// ---- 060-g-srq.ch
wire           AA_IO_LD_HOLD;                           // 組合せ (060): I/Oロードを確定まで待たせる: Aのロード番地がI/O (加算器出力の比較) で / comb (060): hold an I/O load until certain: A's load address is I/O (compare on adder output)
wire           E_V_NOCAN;                               // 組合せ (060): Eの命令が生きている: V & 予測ミスで消えない & 割り込みで消えない (LUT4) / comb (060): E insn alive: V & not killed by mispredict & not by interrupt (LUT4)
wire           B_V_NOCAN;                               // 組合せ (060): Bの命令が生きている (同じ形のLUT4) / comb (060): B insn alive (same LUT4)
wire           A_V_NOCAN;                               // 組合せ (060): Aの命令が生きている → 070, 170 / comb (060): A insn alive -> 070, 170
wire           A_EAB;                                   // 組合せ (060): Aが読むGRがまだ出来ていない (データハザード) = 下の2項のOR / comb (060): a GR read in A is not ready yet (data hazard) = OR of the two terms below
wire           AA_LD_REQ_VAL;                           // 組合せ (060): AのL/STがSユニットへ要求: 生きていてハザード無しで / comb (060): A's L/ST requests the S unit: alive, no hazard
wire           WW_ST_REQ_VAL;                           // 組合せ (060): STBにデータがあればST2を要求: 別名 (ゲート無し) / comb (060): request ST2 when STB holds data: alias (no gate)
wire           AA_LD_GO;                                // 組合せ (060): AのL/STが受け付けられた (AND) → 070, 160 / comb (060): A's L/ST accepted (AND) -> 070, 160
wire           WW_ST_GO;                                // 組合せ (060): ST2が受け付けられた (Aを優先する調停, AND3) → 070, 090, 160 / comb (060): ST2 accepted (arbitration favouring A, AND3) -> 070, 090, 160
// ---- 070-g-ilk.ch
wire           E_STB_INTLK;                             // 組合せ (070): Eのストアが進めない: STBが埋まりST2も通らない (AND4 = LUT4) / comb (070): E store stuck: STB full and ST2 not accepted (AND4 = LUT4)
wire           E_LMD_INTLK;                             // 組合せ (070): EのL/STがキャッシュの応答待ち (ミス): LUT3 / comb (070): E L/ST waiting for the cache (miss): LUT3
wire           A_SBS_INTLK;                             // 組合せ (070): AのL/STをSユニットが受け付けない (S busy): LUT3 / comb (070): S unit did not accept A's L/ST (S busy): LUT3
wire           D_V_NOCAN;                               // 組合せ (070): Dに発行できる命令がある: I0_V & !CANCEL_BY_INT / comb (070): an insn can issue in D: I0_V & !CANCEL_BY_INT
wire           D_BC_2ND_INTLK;                          // 組合せ (070): 2つ目の未解決BCは待たせる: 1命令目がBCで / comb (070): hold a second unsolved BC: first insn is a BC
wire           D_PIPECLR_INTLK;                         // 組合せ (070): RSRはパイプが空くまで待つ / comb (070): RSR waits for the pipe to drain
wire           E_INTLK;                                 // 組合せ (070): E: STBFUL,LMD -- Eが止まる → B_INTLK, 100/110のE側FFの保持(CE) / comb (070): E stalls -> B_INTLK, hold (CE) of E FFs in 100/110
wire           B_INTLK;                                 // 組合せ (070): B: no intlk -- Bの停止はEの停止だけが原因 / comb (070): B stalls only because E stalls
wire           A_INTLK;                                 // 組合せ (070): A:EAB,SUBUSY -- Sビジー/データハザード/後段停止 → 140/150のA_* FF約200本の保持 / comb (070): S busy, hazard or later stall -> hold of ~200 A_* FFs in 140/150
wire           D_INTLK;                                 // 組合せ (070): D:BC2ND,PCLR -- 2つ目のBC / RSRのパイプ空け待ち / comb (070): second BC / RSR drain
wire           E_FWD;                                   // 組合せ (070): Eの命令がWへ進む → 090のW_* FF / comb (070): E insn moves to W -> W_* FFs in 090
wire           B_FWD;                                   // 組合せ (070): Bの命令がEへ進む → 110 / comb (070): B insn moves to E -> 110
wire           A_FWD;                                   // 組合せ (070): Aの命令がBへ進む → 130, 170, 210 / comb (070): A insn moves to B -> 130, 170, 210
wire           D_FWD;                                   // 組合せ (070): Dの命令がAへ進む: 停止の連鎖(E→B→A→D)の終点, 最大ファンアウトのネット / comb (070): D insn moves to A: end of the stall chain (E->B->A->D), the largest fan-out net
wire [3:0]     E_STAT;                                  // 組合せ 4bit (070): 観測用 {FWD,0,0,V}: どこからも使われず合成で消える / comb 4-bit (070): probe {FWD,0,0,V}: unused, removed by synthesis
wire [3:0]     B_STAT;                                  // 組合せ 4bit (070): 観測用: 消える / comb 4-bit (070): probe: removed
wire [3:0]     A_STAT;                                  // 組合せ 4bit (070): 観測用: 消える / comb 4-bit (070): probe: removed
wire [3:0]     D_STAT;                                  // 組合せ 4bit (070): 観測用: 消える / comb 4-bit (070): probe: removed
// ---- 080-w-act.ch
reg  [31:0]    TBR;                                     // FF x32 (D=TBR_NEW, 080): WSRでTBR(2番)を書く: W_WAD2の4bit比較→FF32本のCE, D=W_WDT2 / 32 FFs (D=TBR_NEW, 080): WSR to TBR (#2): 4-bit compare of W_WAD2 -> CE of 32 FFs, D = W_WDT2
wire [31:0]    TBR_NEW;                                 // FF TBR のD入力 (080で作る組合せ回路の出力) / D input of FF TBR (output of the logic in 080)
reg  [31:0]    CMPR;                                    // FF x32 (D=CMPR_NEW, 080): WSRでCMPR(3番)を書く (同じ形: CE付きFF x32) / 32 FFs (D=CMPR_NEW, 080): WSR to CMPR (#3) (same: 32 FFs with CE)
wire [31:0]    CMPR_NEW;                                // FF CMPR のD入力 (080で作る組合せ回路の出力) / D input of FF CMPR (output of the logic in 080)
reg  [31:0]    SVR0;                                    // FF x32 (D=SVR0_NEW, 080): WSRでSVR0(8番)を書く / 32 FFs (D=SVR0_NEW, 080): WSR to SVR0 (#8)
wire [31:0]    SVR0_NEW;                                // FF SVR0 のD入力 (080で作る組合せ回路の出力) / D input of FF SVR0 (output of the logic in 080)
reg  [31:0]    SVR1;                                    // FF x32 (D=SVR1_NEW, 080): WSRでSVR1(9番)を書く / 32 FFs (D=SVR1_NEW, 080): WSR to SVR1 (#9)
wire [31:0]    SVR1_NEW;                                // FF SVR1 のD入力 (080で作る組合せ回路の出力) / D input of FF SVR1 (output of the logic in 080)
wire [4:0]     PC_INCR_AMOUNT;                          // 組合せ 5bit (080): PCの増分: 2命令完了(分岐・割り込み無し)なら8 / comb 5-bit (080): PC increment: 8 when two insns complete (no branch / interrupt)
wire [31:0]    INCREMENTED_PC;                          // 組合せ 32bit (080): PC+増分: 32bit加算器 (下位2bitは0のまま, CARRY4 x8) / comb 32-bit (080): PC + increment: 32-bit adder (low 2 bits stay 0, 8 CARRY4s)
wire [31:0]    MODIFIED_PC;                             // 組合せ 32bit (080): 分岐が完了したらW_TGT, そうでなければ次の番地: 32bit 2:1 MUX / comb 32-bit (080): W_TGT when a branch completes, else the next address: 32-bit 2:1 mux
wire [1:0]     MODIFIED_CC;                             // 組合せ 2bit (080): Wの命令がCCを変えたらW_CC, そうでなければPSW_CC: 2bit 2:1 MUX / comb 2-bit (080): W_CC if the W insn sets CC, else PSW_CC: 2-bit 2:1 mux
wire           WW_HIDE_LS;                              // 組合せ (080): 先の命令(EX)が割り込むならLS側の割り込みを隠す (AND) / comb (080): hide the LS interrupt when the earlier EX insn interrupts (AND)
wire [2:0]     WW_INTCODE;                              // 組合せ 3bit (080): 採用する割り込みコード: 3bit 2:1 MUX / comb 3-bit (080): interrupt code taken: 3-bit 2:1 mux
reg  [1:0]     PSW_CC;                                  // FF x2 (D=PSW_CC_NEW, 080): PSWのCC: 割り込みで0 / 2 FFs (D=PSW_CC_NEW, 080): PSW CC: 0 on an interrupt
wire [1:0]     PSW_CC_NEW;                              // FF PSW_CC のD入力 (080で作る組合せ回路の出力) / D input of FF PSW_CC (output of the logic in 080)
reg            PSW_USER;                                // FF x1 (D=PSW_USER_NEW, 080): ユーザーモードビット: 割り込みで0 (特権モードへ) / 1 FF (D=PSW_USER_NEW, 080): user bit: 0 on an interrupt (to supervisor)
wire           PSW_USER_NEW;                            // FF PSW_USER のD入力 (080で作る組合せ回路の出力) / D input of FF PSW_USER (output of the logic in 080)
reg  [7:0]     PSW_TYPE;                                // FF x8 (D=PSW_TYPE_NEW, 080): 割り込み種別8bit: 割り込みでWW_INTCODEを0拡張 / 8 FFs (D=PSW_TYPE_NEW, 080): 8-bit interrupt type: zero-extended WW_INTCODE on an interrupt
wire [7:0]     PSW_TYPE_NEW;                            // FF PSW_TYPE のD入力 (080で作る組合せ回路の出力) / D input of FF PSW_TYPE (output of the logic in 080)
wire [31:0]    PC_NEW;                                  // FF PC のD入力 (080で作る組合せ回路の出力) / D input of FF PC (output of the logic in 080)
reg  [31:0]    XPSW;                                    // FF x32 (D=XPSW_NEW, 080): 割り込み時に直前のPSWを退避: build_pswは配線だけ / 32 FFs (D=XPSW_NEW, 080): save the PSW on an interrupt: build_psw is only wiring
wire [31:0]    XPSW_NEW;                                // FF XPSW のD入力 (080で作る組合せ回路の出力) / D input of FF XPSW (output of the logic in 080)
reg  [31:0]    XPC;                                     // FF x32 (D=XPC_NEW, 080): 割り込み時に戻り番地(MODIFIED_PC)を退避 / 32 FFs (D=XPC_NEW, 080): save the return address (MODIFIED_PC) on an interrupt
wire [31:0]    XPC_NEW;                                 // FF XPC のD入力 (080で作る組合せ回路の出力) / D input of FF XPC (output of the logic in 080)
reg  [31:0]    XLA;                                     // FF x32 (D=XLA_NEW, 080): データアクセス例外(INTCODE_TLB)のとき / 32 FFs (D=XLA_NEW, 080): on a data access exception (INTCODE_TLB)
wire [31:0]    XLA_NEW;                                 // FF XLA のD入力 (080で作る組合せ回路の出力) / D input of FF XLA (output of the logic in 080)
reg            START_TRIGGER_BAR;                       // FF x1 (D=START_TRIGGER_BAR_NEW, 080): 割り込み/RFE/状態変更で0にする (反転で格納, リセット0→再開1) / 1 FF (D=START_TRIGGER_BAR_NEW, 080): 0 on interrupt / RFE / state change (stored inverted: reset 0 -> restart 1)
wire           START_TRIGGER_BAR_NEW;                   // FF START_TRIGGER_BAR のD入力 (080で作る組合せ回路の出力) / D input of FF START_TRIGGER_BAR (output of the logic in 080)
wire           START_TRIGGER;                           // 組合せ (080): フェッチをPCからやり直す合図: FFのQのNOT → 170/180/190 / comb (080): restart-fetch-from-PC strobe: NOT of the FF -> 170/180/190
// ---- 090-e-act.ch
wire [31:0]    EE_MEMOP;                                // 組合せ 32bit (090): ALUの第2入力=ロードデータ: E_LS_LD_DTのFF出力の別名 (ゲート無し) / comb 32-bit (090): ALU input y = load data: alias of the E_LS_LD_DT FFs (no gate)
wire [31:0]    EE_OPS;                                  // 組合せ 32bit (090): ALUの第1入力=レジスタオペランド: E_LS_OPS_DTのFFの別名 / comb 32-bit (090): ALU input x = register operand: alias of the E_LS_OPS_DT FFs
wire [2:0]     EE_LS_INTCODE;                           // 組合せ 3bit (090): LS側の割り込み: Sユニットの例外を優先, なければALUの例外 (3bit 2:1 MUX) / comb 3-bit (090): LS interrupt: S-unit exception first, else the ALU one (3-bit 2:1 mux)
wire           EE_LS_INT_V;                             // 組合せ (090): LS側に割り込みあり: 3bit OR / comb (090): LS interrupt present: 3-bit OR
wire           EE_EX_INT_V;                             // 組合せ (090): EX側に割り込みあり (Aで検出済みのFFを見る): 3bit OR / comb (090): EX interrupt present (FF from A): 3-bit OR
wire           EE_HIDE_EX;                              // 組合せ (090): 先のLSが割り込むので後のEXの結果を隠す (AND) / comb (090): earlier LS interrupts, so hide the later EX (AND)
wire           EE_HIDE_LS;                              // 組合せ (090): 先のEXが割り込むので後のLSの結果を隠す (AND) / comb (090): earlier EX interrupts, so hide the later LS (AND)
wire           EE_SET_CC_FROM_LS;                       // 組合せ (090): CCをLSの結果で更新: LSがSETCCで割り込み無し / comb (090): update CC from LS: LS sets CC without interrupt
wire           EE_SET_CC_FROM_EX;                       // 組合せ (090): CCをEXの結果で更新 / comb (090): update CC from EX
wire [3:0]     W_WAD1_NEW;                              // FF W_WAD1 のD入力 (090で作る組合せ回路の出力) / D input of FF W_WAD1 (output of the logic in 090)
wire [3:0]     W_WAD2_NEW;                              // FF W_WAD2 のD入力 (090で作る組合せ回路の出力) / D input of FF W_WAD2 (output of the logic in 090)
wire [31:0]    W_WDT1_NEW;                              // FF W_WDT1 のD入力 (090で作る組合せ回路の出力) / D input of FF W_WDT1 (output of the logic in 090)
wire [31:0]    W_WDT2_NEW;                              // FF W_WDT2 のD入力 (090で作る組合せ回路の出力) / D input of FF W_WDT2 (output of the logic in 090)
reg  [31:0]    W_TGT;                                   // FF x32 (D=W_TGT_NEW, 090): 分岐先をWへ: FF32本 → 080のMODIFIED_PC / 32 FFs (D=W_TGT_NEW, 090): branch target to W: 32 FFs -> MODIFIED_PC in 080
wire [31:0]    W_TGT_NEW;                               // FF W_TGT のD入力 (090で作る組合せ回路の出力) / D input of FF W_TGT (output of the logic in 090)
reg            W_IS_SUPERSCALAR;                        // FF x1 (D=W_IS_SUPERSCALAR_NEW, 090): 2命令の組か → 080のPC増分 / 1 FF (D=W_IS_SUPERSCALAR_NEW, 090): is it a pair -> PC increment in 080
wire           W_IS_SUPERSCALAR_NEW;                    // FF W_IS_SUPERSCALAR のD入力 (090で作る組合せ回路の出力) / D input of FF W_IS_SUPERSCALAR (output of the logic in 090)
reg            W_LATTER_IS_JB;                          // FF x1 (D=W_LATTER_IS_JB_NEW, 090): 組の後の命令が分岐か / 1 FF (D=W_LATTER_IS_JB_NEW, 090): is the latter insn of the pair a branch
wire           W_LATTER_IS_JB_NEW;                      // FF W_LATTER_IS_JB のD入力 (090で作る組合せ回路の出力) / D input of FF W_LATTER_IS_JB (output of the logic in 090)
reg            W_FIRST_IS_EX;                           // FF x1 (D=W_FIRST_IS_EX_NEW, 090): 組の先の命令がEXか (割り込みの優先順) / 1 FF (D=W_FIRST_IS_EX_NEW, 090): is the first insn EX (interrupt order)
wire           W_FIRST_IS_EX_NEW;                       // FF W_FIRST_IS_EX のD入力 (090で作る組合せ回路の出力) / D input of FF W_FIRST_IS_EX (output of the logic in 090)
reg  [1:0]     W_CC;                                    // FF x2 (D=W_CC_NEW, 090): WへのCC: LS由来ならALUのCC, そうでなければEXのCC (2bit 2:1 MUX) / 2 FFs (D=W_CC_NEW, 090): CC to W: ALU CC if from LS, else EX CC (2-bit 2:1 mux)
wire [1:0]     W_CC_NEW;                                // FF W_CC のD入力 (090で作る組合せ回路の出力) / D input of FF W_CC (output of the logic in 090)
wire           W_WE1_NEW;                               // FF W_WE1 のD入力 (090で作る組合せ回路の出力) / D input of FF W_WE1 (output of the logic in 090)
wire           W_WE2_NEW;                               // FF W_WE2 のD入力 (090で作る組合せ回路の出力) / D input of FF W_WE2 (output of the logic in 090)
reg            W_SETCC;                                 // FF x1 (D=W_SETCC_NEW, 090): WでCCを更新するか / 1 FF (D=W_SETCC_NEW, 090): does W update CC
wire           W_SETCC_NEW;                             // FF W_SETCC のD入力 (090で作る組合せ回路の出力) / D input of FF W_SETCC (output of the logic in 090)
reg            W_COMPLETE;                              // FF x1 (D=W_COMPLETE_NEW, 090): Wに命令がある(完了する) = E_FWD (FFにE_FWDを入れるだけ) / 1 FF (D=W_COMPLETE_NEW, 090): W holds a completing insn = E_FWD (the FF just latches E_FWD)
wire           W_COMPLETE_NEW;                          // FF W_COMPLETE のD入力 (090で作る組合せ回路の出力) / D input of FF W_COMPLETE (output of the logic in 090)
reg  [1:0]     W_PRIVCODE;                              // FF x2 (D=W_PRIVCODE_NEW, 090): 特権命令の種類をWへ (E_FWDでAND) / 2 FFs (D=W_PRIVCODE_NEW, 090): privileged kind to W (ANDed with E_FWD)
wire [1:0]     W_PRIVCODE_NEW;                          // FF W_PRIVCODE のD入力 (090で作る組合せ回路の出力) / D input of FF W_PRIVCODE (output of the logic in 090)
reg  [2:0]     W_EX_INTCODE;                            // FF x3 (D=W_EX_INTCODE_NEW, 090): EX側の割り込みコードをWへ / 3 FFs (D=W_EX_INTCODE_NEW, 090): EX interrupt code to W
wire [2:0]     W_EX_INTCODE_NEW;                        // FF W_EX_INTCODE のD入力 (090で作る組合せ回路の出力) / D input of FF W_EX_INTCODE (output of the logic in 090)
reg  [2:0]     W_LS_INTCODE;                            // FF x3 (D=W_LS_INTCODE_NEW, 090): LS側の割り込みコードをWへ / 3 FFs (D=W_LS_INTCODE_NEW, 090): LS interrupt code to W
wire [2:0]     W_LS_INTCODE_NEW;                        // FF W_LS_INTCODE のD入力 (090で作る組合せ回路の出力) / D input of FF W_LS_INTCODE (output of the logic in 090)
reg            W_JB_V;                                  // FF x1 (D=W_JB_V_NEW, 090): Wで分岐を実行: 無条件分岐 / 1 FF (D=W_JB_V_NEW, 090): execute the branch in W: unconditional
wire           W_JB_V_NEW;                              // FF W_JB_V のD入力 (090で作る組合せ回路の出力) / D input of FF W_JB_V (output of the logic in 090)
reg            STB_V;                                   // FF x1 (D=STB_V_NEW, 090): ストアバッファ有効: ST2が通るまで保持 / 1 FF (D=STB_V_NEW, 090): store buffer valid: held until ST2 is accepted
wire           STB_V_NEW;                               // FF STB_V のD入力 (090で作る組合せ回路の出力) / D input of FF STB_V (output of the logic in 090)
reg  [31:0]    STB_AD;                                  // FF x32 (D=STB_AD_NEW, 090): ストア番地: Eのストアが進む時だけ取り込む → CE付きFF32本 / 32 FFs (D=STB_AD_NEW, 090): store address: loaded only when an E store moves -> 32 FFs with CE
wire [31:0]    STB_AD_NEW;                              // FF STB_AD のD入力 (090で作る組合せ回路の出力) / D input of FF STB_AD (output of the logic in 090)
reg  [31:0]    STB_DT;                                  // FF x32 (D=STB_DT_NEW, 090): ストアデータ(ALUで整形済み): CE付きFF32本 / 32 FFs (D=STB_DT_NEW, 090): store data (shaped by the ALU): 32 FFs with CE
wire [31:0]    STB_DT_NEW;                              // FF STB_DT のD入力 (090で作る組合せ回路の出力) / D input of FF STB_DT (output of the logic in 090)
// ---- 100-b-dat.ch
reg  [31:0]    E_LS_OPS_DT;                             // FF x32 (D=E_LS_OPS_DT_NEW, 100): Eへ渡すレジスタオペランド: 新しい順の7:1優先MUX (32bit) / 32 FFs (D=E_LS_OPS_DT_NEW, 100): register operand to E: 7:1 priority mux, newest first (32 bits)
wire [31:0]    E_LS_OPS_DT_NEW;                         // FF E_LS_OPS_DT のD入力 (100で作る組合せ回路の出力) / D input of FF E_LS_OPS_DT (output of the logic in 100)
reg            E_OPCLH_LCH;                             // FF x1 (D=E_OPCLH_LCH_NEW, 100): Eの「データが揃った」: STB待ちでなければB_OPCLHを取り込む (CE付きFF) / 1 FF (D=E_OPCLH_LCH_NEW, 100): E "data ready": takes B_OPCLH unless waiting for STB (FF with CE)
wire           E_OPCLH_LCH_NEW;                         // FF E_OPCLH_LCH のD入力 (100で作る組合せ回路の出力) / D input of FF E_OPCLH_LCH (output of the logic in 100)
reg  [2:0]     E_LS_INTCODE;                            // FF x3 (D=E_LS_INTCODE_NEW, 100): Sユニットの例外コードをEへ (CE付きFF 3本) / 3 FFs (D=E_LS_INTCODE_NEW, 100): S-unit exception code to E (3 FFs with CE)
wire [2:0]     E_LS_INTCODE_NEW;                        // FF E_LS_INTCODE のD入力 (100で作る組合せ回路の出力) / D input of FF E_LS_INTCODE (output of the logic in 100)
wire [31:0]    BB_MEM_DATA;                             // 組合せ 32bit (100): Bのロードデータ: EXT_BUS=1なら050で処理済みでOP_LBS_DATAそのもの (配線) / comb 32-bit (100): B load data: with EXT_BUS=1 just OP_LBS_DATA (wire), handled in 050
reg  [31:0]    E_LS_LD_DT;                              // FF x32 (D=E_LS_LD_DT_NEW, 100): ロードデータをEのFFへ (STB待ち中は保持=CE) → 090のALU / 32 FFs (D=E_LS_LD_DT_NEW, 100): load data into E FFs (hold = CE while waiting for STB) -> ALU in 090
wire [31:0]    E_LS_LD_DT_NEW;                          // FF E_LS_LD_DT のD入力 (100で作る組合せ回路の出力) / D input of FF E_LS_LD_DT (output of the logic in 100)
// ---- 110-b-act.ch
reg            E_V;                                     // FF x1 (D=E_V_NEW, 110): Eの有効ビット: B_FWD→1 / E_INTLK→保持 / else 0. FF1本+LUT3 / 1 FF (D=E_V_NEW, 110): E valid: B_FWD -> 1, E_INTLK -> hold, else 0. 1 FF + LUT3
wire           E_V_NEW;                                 // FF E_V のD入力 (110で作る組合せ回路の出力) / D input of FF E_V (output of the logic in 110)
reg            E_JB_IS_BC;                              // FF x1 (D=E_JB_IS_BC_NEW, 110): EのBCが未解決か: Bから来た値 / 1 FF (D=E_JB_IS_BC_NEW, 110): is E's BC unsolved: value from B
wire           E_JB_IS_BC_NEW;                          // FF E_JB_IS_BC のD入力 (110で作る組合せ回路の出力) / D input of FF E_JB_IS_BC (output of the logic in 110)
reg            E_JB_SUBJECT_TO_BC;                      // FF x1 (D=E_JB_SUBJECT_TO_BC_NEW, 110): 未解決分岐の先の投機命令か: 同じ形 / 1 FF (D=E_JB_SUBJECT_TO_BC_NEW, 110): speculative behind an unsolved branch: same form
wire           E_JB_SUBJECT_TO_BC_NEW;                  // FF E_JB_SUBJECT_TO_BC のD入力 (110で作る組合せ回路の出力) / D input of FF E_JB_SUBJECT_TO_BC (output of the logic in 110)
reg            E_JB_V;                                  // FF x1 (D=E_JB_V_NEW, 110): Eに分岐があるか / 1 FF (D=E_JB_V_NEW, 110): branch present in E
wire           E_JB_V_NEW;                              // FF E_JB_V のD入力 (110で作る組合せ回路の出力) / D input of FF E_JB_V (output of the logic in 110)
reg            E_LS_SOLVING_BC;                         // FF x1 (D=E_LS_SOLVING_BC_NEW, 110): このLS命令が未解決BCのCCを作るか / 1 FF (D=E_LS_SOLVING_BC_NEW, 110): does this LS insn make the unsolved BC's CC
wire           E_LS_SOLVING_BC_NEW;                     // FF E_LS_SOLVING_BC のD入力 (110で作る組合せ回路の出力) / D input of FF E_LS_SOLVING_BC (output of the logic in 110)
reg            E_LS_LD_V;                               // FF x1 (D=E_LS_LD_V_NEW, 110): ロードか: 3:1 MUX (B値/保持/0) = FF1本+LUT3 / 1 FF (D=E_LS_LD_V_NEW, 110): load?: 3:1 mux (B / hold / 0) = 1 FF + LUT3
wire           E_LS_LD_V_NEW;                           // FF E_LS_LD_V のD入力 (110で作る組合せ回路の出力) / D input of FF E_LS_LD_V (output of the logic in 110)
reg            E_LS_ST_V;                               // FF x1 (D=E_LS_ST_V_NEW, 110): ストアか: 同じ形 / 1 FF (D=E_LS_ST_V_NEW, 110): store?: same form
wire           E_LS_ST_V_NEW;                           // FF E_LS_ST_V のD入力 (110で作る組合せ回路の出力) / D input of FF E_LS_ST_V (output of the logic in 110)
reg            E_WE1;                                   // FF x1 (D=E_WE1_NEW, 110): LS側GR書き込み: 同じ形 / 1 FF (D=E_WE1_NEW, 110): LS GR write: same
wire           E_WE1_NEW;                               // FF E_WE1 のD入力 (110で作る組合せ回路の出力) / D input of FF E_WE1 (output of the logic in 110)
reg            E_WE2;                                   // FF x1 (D=E_WE2_NEW, 110): EX側GR書き込み: 同じ形 / 1 FF (D=E_WE2_NEW, 110): EX GR write: same
wire           E_WE2_NEW;                               // FF E_WE2 のD入力 (110で作る組合せ回路の出力) / D input of FF E_WE2 (output of the logic in 110)
reg            E_LS_SETCC;                              // FF x1 (D=E_LS_SETCC_NEW, 110): LSがCCを変える: 同じ形 / 1 FF (D=E_LS_SETCC_NEW, 110): LS sets CC: same
wire           E_LS_SETCC_NEW;                          // FF E_LS_SETCC のD入力 (110で作る組合せ回路の出力) / D input of FF E_LS_SETCC (output of the logic in 110)
reg            E_EX_SETCC;                              // FF x1 (D=E_EX_SETCC_NEW, 110): EXがCCを変える: 同じ形 / 1 FF (D=E_EX_SETCC_NEW, 110): EX sets CC: same
wire           E_EX_SETCC_NEW;                          // FF E_EX_SETCC のD入力 (110で作る組合せ回路の出力) / D input of FF E_EX_SETCC (output of the logic in 110)
reg  [2:0]     E_EX_INTCODE;                            // FF x3 (D=E_EX_INTCODE_NEW, 110): EX側の割り込みコード: 3bit x 同じ形 / 3 FFs (D=E_EX_INTCODE_NEW, 110): EX interrupt code: 3 bits of the same form
wire [2:0]     E_EX_INTCODE_NEW;                        // FF E_EX_INTCODE のD入力 (110で作る組合せ回路の出力) / D input of FF E_EX_INTCODE (output of the logic in 110)
reg  [1:0]     E_PRIVCODE;                              // FF x2 (D=E_PRIVCODE_NEW, 110): 特権命令の種類: 2bit x 同じ形 / 2 FFs (D=E_PRIVCODE_NEW, 110): privileged kind: 2 bits of the same form
wire [1:0]     E_PRIVCODE_NEW;                          // FF E_PRIVCODE のD入力 (110で作る組合せ回路の出力) / D input of FF E_PRIVCODE (output of the logic in 110)
reg  [31:0]    E_LS_LOG_AD;                             // FF x32 (D=E_LS_LOG_AD_NEW, 110): L/ST番地: D=B_LS_LOG_ADのQ直結, CE=!E_INTLK (LUT無しのFF32本) / 32 FFs (D=E_LS_LOG_AD_NEW, 110): L/ST address: D wired to B_LS_LOG_AD, CE = !E_INTLK (32 FFs, no LUT)
wire [31:0]    E_LS_LOG_AD_NEW;                         // FF E_LS_LOG_AD のD入力 (110で作る組合せ回路の出力) / D input of FF E_LS_LOG_AD (output of the logic in 110)
reg  [3:0]     E_WAD1;                                  // FF x4 (D=E_WAD1_NEW, 110): LS側の書き込み番号: CE付きFF4本 / 4 FFs (D=E_WAD1_NEW, 110): LS write number: 4 FFs with CE
wire [3:0]     E_WAD1_NEW;                              // FF E_WAD1 のD入力 (110で作る組合せ回路の出力) / D input of FF E_WAD1 (output of the logic in 110)
reg  [3:0]     E_WAD2;                                  // FF x4 (D=E_WAD2_NEW, 110): EX側の書き込み番号: CE付きFF4本 / 4 FFs (D=E_WAD2_NEW, 110): EX write number: 4 FFs with CE
wire [3:0]     E_WAD2_NEW;                              // FF E_WAD2 のD入力 (110で作る組合せ回路の出力) / D input of FF E_WAD2 (output of the logic in 110)
reg            E_LS_OPS_IS_GR;                          // FF x1 (D=E_LS_OPS_IS_GR_NEW, 110): 旧版(#if 0)用: 使われず合成で消える / 1 FF (D=E_LS_OPS_IS_GR_NEW, 110): for the old #if 0 code: unused, removed
wire           E_LS_OPS_IS_GR_NEW;                      // FF E_LS_OPS_IS_GR のD入力 (110で作る組合せ回路の出力) / D input of FF E_LS_OPS_IS_GR (output of the logic in 110)
reg  [3:0]     E_LS_RADS;                               // FF x4 (D=E_LS_RADS_NEW, 110): 旧版用: 使われず消える / 4 FFs (D=E_LS_RADS_NEW, 110): for the old code: unused, removed
wire [3:0]     E_LS_RADS_NEW;                           // FF E_LS_RADS のD入力 (110で作る組合せ回路の出力) / D input of FF E_LS_RADS (output of the logic in 110)
reg  [31:0]    E_EX_RES;                                // FF x32 (D=E_EX_RES_NEW, 110): EXの結果: CE付きFF32本 → 090のW_WDT2, 100/140のバイパス / 32 FFs (D=E_EX_RES_NEW, 110): EX result: 32 FFs with CE -> W_WDT2 in 090, bypass in 100/140
wire [31:0]    E_EX_RES_NEW;                            // FF E_EX_RES のD入力 (110で作る組合せ回路の出力) / D input of FF E_EX_RES (output of the logic in 110)
reg  [1:0]     E_EX_CC;                                 // FF x2 (D=E_EX_CC_NEW, 110): EXのCC: CE付きFF2本 → 040のフォワード, 090のW_CC / 2 FFs (D=E_EX_CC_NEW, 110): EX CC: 2 FFs with CE -> forwarding in 040, W_CC in 090
wire [1:0]     E_EX_CC_NEW;                             // FF E_EX_CC のD入力 (110で作る組合せ回路の出力) / D input of FF E_EX_CC (output of the logic in 110)
reg  [31:0]    E_TGT;                                   // FF x32 (D=E_TGT_NEW, 110): 分岐先: CE付きFF32本 / 32 FFs (D=E_TGT_NEW, 110): branch target: 32 FFs with CE
wire [31:0]    E_TGT_NEW;                               // FF E_TGT のD入力 (110で作る組合せ回路の出力) / D input of FF E_TGT (output of the logic in 110)
reg            E_IS_SUPERSCALAR;                        // FF x1 (D=E_IS_SUPERSCALAR_NEW, 110): 2命令の組か: CE付きFF / 1 FF (D=E_IS_SUPERSCALAR_NEW, 110): pair?: FF with CE
wire           E_IS_SUPERSCALAR_NEW;                    // FF E_IS_SUPERSCALAR のD入力 (110で作る組合せ回路の出力) / D input of FF E_IS_SUPERSCALAR (output of the logic in 110)
reg            E_LATTER_IS_JB;                          // FF x1 (D=E_LATTER_IS_JB_NEW, 110): 後の命令が分岐か: CE付きFF / 1 FF (D=E_LATTER_IS_JB_NEW, 110): latter is a branch?: FF with CE
wire           E_LATTER_IS_JB_NEW;                      // FF E_LATTER_IS_JB のD入力 (110で作る組合せ回路の出力) / D input of FF E_LATTER_IS_JB (output of the logic in 110)
reg            E_FIRST_IS_EX;                           // FF x1 (D=E_FIRST_IS_EX_NEW, 110): 先の命令がEXか: CE付きFF / 1 FF (D=E_FIRST_IS_EX_NEW, 110): first is EX?: FF with CE
wire           E_FIRST_IS_EX_NEW;                       // FF E_FIRST_IS_EX のD入力 (110で作る組合せ回路の出力) / D input of FF E_FIRST_IS_EX (output of the logic in 110)
reg  [4:0]     E_LS_OPCODE;                             // FF x5 (D=E_LS_OPCODE_NEW, 110): ALUのopcode: CE=!E_INTLK, Dは次の式 / 5 FFs (D=E_LS_OPCODE_NEW, 110): ALU opcode: CE = !E_INTLK, D is
wire [4:0]     E_LS_OPCODE_NEW;                         // FF E_LS_OPCODE のD入力 (110で作る組合せ回路の出力) / D input of FF E_LS_OPCODE (output of the logic in 110)
// ---- 120-a-dat.ch
wire [31:0]    AA_OPB;                                  // 組合せ 32bit (120): EAGのベース値: A_LS_OPB_DTのFFそのもの (Dの時点でバイパス済み) / comb 32-bit (120): EAG base: the A_LS_OPB_DT FFs (bypassed already in D)
wire [31:0]    AA_OP1;                                  // 組合せ 32bit (120): EXUの第1オペランド: FFの別名 / comb 32-bit (120): EXU operand 1: alias of FFs
wire [31:0]    AA_OP2;                                  // 組合せ 32bit (120): EXUの第2オペランド: FFの別名 / comb 32-bit (120): EXU operand 2: alias of FFs
wire [31:0]    AA_EAG_OUTPUT;                           // 組合せ 32bit (120): 実効アドレス = ベース + 符号拡張16bit変位: 32bit加算器 (CARRY4 x8). ファンアウト大 / comb 32-bit (120): effective address = base + sign-extended disp16: 32-bit adder (8 CARRY4s), large fan-out
wire [31:0]    A_SR_READ_DATA;                          // 組合せ 32bit (120): RSRで読むシステムレジスタ: A_EX_RAD2(4bit)で選ぶ32bit 9:1 MUX / comb 32-bit (120): system register read by RSR: 32-bit 9:1 mux on A_EX_RAD2 (4 bits)
wire [31:0]    AA_EX_RES;                               // 組合せ 32bit (120): EXの結果: RSRならSRの値, そうでなければEXU出力 (32bit 2:1 MUX) → 130, 140 / comb 32-bit (120): EX result: SR value for RSR, else EXU output (32-bit 2:1 mux) -> 130, 140
// ---- 130-a-act.ch
reg            B_V;                                     // FF x1 (D=B_V_NEW, 130): Bの有効ビット: Aから来る or Bが留まる (OR, FF1本) / 1 FF (D=B_V_NEW, 130): B valid: comes from A or B stays (OR, 1 FF)
wire           B_V_NEW;                                 // FF B_V のD入力 (130で作る組合せ回路の出力) / D input of FF B_V (output of the logic in 130)
reg            B_JB_IS_BC;                              // FF x1 (D=B_JB_IS_BC_NEW, 130): BのBCが未解決か: Aからの値 / 1 FF (D=B_JB_IS_BC_NEW, 130): is B's BC unsolved: value from A
wire           B_JB_IS_BC_NEW;                          // FF B_JB_IS_BC のD入力 (130で作る組合せ回路の出力) / D input of FF B_JB_IS_BC (output of the logic in 130)
reg            B_JB_SUBJECT_TO_BC;                      // FF x1 (D=B_JB_SUBJECT_TO_BC_NEW, 130): 投機中フラグ: 同じ形 / 1 FF (D=B_JB_SUBJECT_TO_BC_NEW, 130): speculative flag: same form
wire           B_JB_SUBJECT_TO_BC_NEW;                  // FF B_JB_SUBJECT_TO_BC のD入力 (130で作る組合せ回路の出力) / D input of FF B_JB_SUBJECT_TO_BC (output of the logic in 130)
reg            B_JB_V;                                  // FF x1 (D=B_JB_V_NEW, 130): Bに分岐があるか / 1 FF (D=B_JB_V_NEW, 130): branch present in B
wire           B_JB_V_NEW;                              // FF B_JB_V のD入力 (130で作る組合せ回路の出力) / D input of FF B_JB_V (output of the logic in 130)
reg            B_LS_SOLVING_BC;                         // FF x1 (D=B_LS_SOLVING_BC_NEW, 130): このLS命令が未解決BCのCCを作るか / 1 FF (D=B_LS_SOLVING_BC_NEW, 130): does this LS insn make the unsolved BC's CC
wire           B_LS_SOLVING_BC_NEW;                     // FF B_LS_SOLVING_BC のD入力 (130で作る組合せ回路の出力) / D input of FF B_LS_SOLVING_BC (output of the logic in 130)
reg  [2:0]     B_INTCODE;                               // FF x3 (D=B_INTCODE_NEW, 130): Bの割り込みコード: 保持 / Aが進まなければ0 / 3 FFs (D=B_INTCODE_NEW, 130): ... / B interrupt code: hold / 0 if A does not move /
wire [2:0]     B_INTCODE_NEW;                           // FF B_INTCODE のD入力 (130で作る組合せ回路の出力) / D input of FF B_INTCODE (output of the logic in 130)
reg  [1:0]     B_PRIVCODE;                              // FF x2 (D=B_PRIVCODE_NEW, 130): 特権命令の種類: 3:1 MUX (A値/保持/0) x2bit / 2 FFs (D=B_PRIVCODE_NEW, 130): privileged kind: 3:1 mux (A / hold / 0) x 2 bits
wire [1:0]     B_PRIVCODE_NEW;                          // FF B_PRIVCODE のD入力 (130で作る組合せ回路の出力) / D input of FF B_PRIVCODE (output of the logic in 130)
reg            B_LS_LD_V;                               // FF x1 (D=B_LS_LD_V_NEW, 130): ロードか: 同じ形 (FF+LUT3) / 1 FF (D=B_LS_LD_V_NEW, 130): load?: same form (FF + LUT3)
wire           B_LS_LD_V_NEW;                           // FF B_LS_LD_V のD入力 (130で作る組合せ回路の出力) / D input of FF B_LS_LD_V (output of the logic in 130)
reg            B_LS_ST_V;                               // FF x1 (D=B_LS_ST_V_NEW, 130): ストアか: 同じ形 / 1 FF (D=B_LS_ST_V_NEW, 130): store?: same
wire           B_LS_ST_V_NEW;                           // FF B_LS_ST_V のD入力 (130で作る組合せ回路の出力) / D input of FF B_LS_ST_V (output of the logic in 130)
reg            B_WE1;                                   // FF x1 (D=B_WE1_NEW, 130): LS側GR書き込み: 同じ形 / 1 FF (D=B_WE1_NEW, 130): LS GR write: same
wire           B_WE1_NEW;                               // FF B_WE1 のD入力 (130で作る組合せ回路の出力) / D input of FF B_WE1 (output of the logic in 130)
reg            B_WE2;                                   // FF x1 (D=B_WE2_NEW, 130): EX側GR書き込み: 同じ形 / 1 FF (D=B_WE2_NEW, 130): EX GR write: same
wire           B_WE2_NEW;                               // FF B_WE2 のD入力 (130で作る組合せ回路の出力) / D input of FF B_WE2 (output of the logic in 130)
reg            B_LS_SETCC;                              // FF x1 (D=B_LS_SETCC_NEW, 130): LSがCCを変える: 同じ形 / 1 FF (D=B_LS_SETCC_NEW, 130): LS sets CC: same
wire           B_LS_SETCC_NEW;                          // FF B_LS_SETCC のD入力 (130で作る組合せ回路の出力) / D input of FF B_LS_SETCC (output of the logic in 130)
reg            B_EX_SETCC;                              // FF x1 (D=B_EX_SETCC_NEW, 130): EXがCCを変える: 同じ形 / 1 FF (D=B_EX_SETCC_NEW, 130): EX sets CC: same
wire           B_EX_SETCC_NEW;                          // FF B_EX_SETCC のD入力 (130で作る組合せ回路の出力) / D input of FF B_EX_SETCC (output of the logic in 130)
reg  [31:0]    B_LS_LOG_AD;                             // FF x32 (D=B_LS_LOG_AD_NEW, 130): L/ST番地: EAG加算器の出力をCE付きFF32本で受ける (Aサイクルの終点) / 32 FFs (D=B_LS_LOG_AD_NEW, 130): L/ST address: EAG adder output into 32 FFs with CE (end of the A cycle)
wire [31:0]    B_LS_LOG_AD_NEW;                         // FF B_LS_LOG_AD のD入力 (130で作る組合せ回路の出力) / D input of FF B_LS_LOG_AD (output of the logic in 130)
reg  [3:0]     B_WAD1;                                  // FF x4 (D=B_WAD1_NEW, 130): LS側書き込み番号: CE付きFF4本 / 4 FFs (D=B_WAD1_NEW, 130): LS write number: 4 FFs with CE
wire [3:0]     B_WAD1_NEW;                              // FF B_WAD1 のD入力 (130で作る組合せ回路の出力) / D input of FF B_WAD1 (output of the logic in 130)
reg  [3:0]     B_WAD2;                                  // FF x4 (D=B_WAD2_NEW, 130): EX側書き込み番号: CE付きFF4本 / 4 FFs (D=B_WAD2_NEW, 130): EX write number: 4 FFs with CE
wire [3:0]     B_WAD2_NEW;                              // FF B_WAD2 のD入力 (130で作る組合せ回路の出力) / D input of FF B_WAD2 (output of the logic in 130)
reg            B_LS_OPS_IS_GR;                          // FF x1 (D=B_LS_OPS_IS_GR_NEW, 130): RSがGRか: CE付きFF → 100のバイパス判定 / 1 FF (D=B_LS_OPS_IS_GR_NEW, 130): RS is a GR: FF with CE -> bypass check in 100
wire           B_LS_OPS_IS_GR_NEW;                      // FF B_LS_OPS_IS_GR のD入力 (130で作る組合せ回路の出力) / D input of FF B_LS_OPS_IS_GR (output of the logic in 130)
wire [3:0]     B_LS_RADS_NEW;                           // FF B_LS_RADS のD入力 (130で作る組合せ回路の出力) / D input of FF B_LS_RADS (output of the logic in 130)
reg  [4:0]     B_LS_OPCODE;                             // FF x5 (D=B_LS_OPCODE_NEW, 130): LSのopcode: CE付きFF5本 / 5 FFs (D=B_LS_OPCODE_NEW, 130): LS opcode: 5 FFs with CE
wire [4:0]     B_LS_OPCODE_NEW;                         // FF B_LS_OPCODE のD入力 (130で作る組合せ回路の出力) / D input of FF B_LS_OPCODE (output of the logic in 130)
reg            B_IS_SUPERSCALAR;                        // FF x1 (D=B_IS_SUPERSCALAR_NEW, 130): 2命令の組か: CE付きFF / 1 FF (D=B_IS_SUPERSCALAR_NEW, 130): pair?: FF with CE
wire           B_IS_SUPERSCALAR_NEW;                    // FF B_IS_SUPERSCALAR のD入力 (130で作る組合せ回路の出力) / D input of FF B_IS_SUPERSCALAR (output of the logic in 130)
reg            B_LATTER_IS_JB;                          // FF x1 (D=B_LATTER_IS_JB_NEW, 130): 後の命令が分岐か: CE付きFF / 1 FF (D=B_LATTER_IS_JB_NEW, 130): latter is a branch?: FF with CE
wire           B_LATTER_IS_JB_NEW;                      // FF B_LATTER_IS_JB のD入力 (130で作る組合せ回路の出力) / D input of FF B_LATTER_IS_JB (output of the logic in 130)
reg            B_FIRST_IS_EX;                           // FF x1 (D=B_FIRST_IS_EX_NEW, 130): 先の命令がEXか: CE付きFF / 1 FF (D=B_FIRST_IS_EX_NEW, 130): first is EX?: FF with CE
wire           B_FIRST_IS_EX_NEW;                       // FF B_FIRST_IS_EX のD入力 (130で作る組合せ回路の出力) / D input of FF B_FIRST_IS_EX (output of the logic in 130)
reg  [3:0]     B_EX_RAD2;                               // FF x4 (D=B_EX_RAD2_NEW, 130): R2の番号: どこからも使われず合成で消える / 4 FFs (D=B_EX_RAD2_NEW, 130): R2 number: unused, removed by synthesis
wire [3:0]     B_EX_RAD2_NEW;                           // FF B_EX_RAD2 のD入力 (130で作る組合せ回路の出力) / D input of FF B_EX_RAD2 (output of the logic in 130)
reg  [31:0]    B_TGT;                                   // FF x32 (D=B_TGT_NEW, 130): 分岐先: レジスタ間接ならEAG出力, PC相対ならA_TGT (32bit 2:1 MUX + CE) / 32 FFs (D=B_TGT_NEW, 130): target: EAG output if register-indirect, else A_TGT (32-bit 2:1 mux + CE)
wire [31:0]    B_TGT_NEW;                               // FF B_TGT のD入力 (130で作る組合せ回路の出力) / D input of FF B_TGT (output of the logic in 130)
reg  [31:0]    B_EX_RES;                                // FF x32 (D=B_EX_RES_NEW, 130): EXの結果: AA_EX_RES (EXU/RSR) をCE付きFF32本で受ける / 32 FFs (D=B_EX_RES_NEW, 130): EX result: AA_EX_RES (EXU / RSR) into 32 FFs with CE
wire [31:0]    B_EX_RES_NEW;                            // FF B_EX_RES のD入力 (130で作る組合せ回路の出力) / D input of FF B_EX_RES (output of the logic in 130)
reg  [1:0]     B_EX_CC;                                 // FF x2 (D=B_EX_CC_NEW, 130): EXのCC: EXUのCCをCE付きFF2本で受ける → 040のフォワード / 2 FFs (D=B_EX_CC_NEW, 130): EX CC: EXU CC into 2 FFs with CE -> forwarding in 040
wire [1:0]     B_EX_CC_NEW;                             // FF B_EX_CC のD入力 (130で作る組合せ回路の出力) / D input of FF B_EX_CC (output of the logic in 130)
// ---- 140-d-dat.ch
reg            A_LS_OPB_IS_GR;                          // FF x1 (D=A_LS_OPB_IS_GR_NEW, 140): ベースがGRか: 保持 / D_FWDで新値 / 0 (FF+LUT) → 060のA_EAB / 1 FF (D=A_LS_OPB_IS_GR_NEW, 140): base is a GR: hold / new on D_FWD / 0 (FF + LUT) -> A_EAB in 060
wire           A_LS_OPB_IS_GR_NEW;                      // FF A_LS_OPB_IS_GR のD入力 (140で作る組合せ回路の出力) / D input of FF A_LS_OPB_IS_GR (output of the logic in 140)
reg            A_EX_OP1_IS_GR;                          // FF x1 (D=A_EX_OP1_IS_GR_NEW, 140): R1がGRか (同じ形) / 1 FF (D=A_EX_OP1_IS_GR_NEW, 140): R1 is a GR (same form)
wire           A_EX_OP1_IS_GR_NEW;                      // FF A_EX_OP1_IS_GR のD入力 (140で作る組合せ回路の出力) / D input of FF A_EX_OP1_IS_GR (output of the logic in 140)
reg            A_EX_OP2_IS_GR;                          // FF x1 (D=A_EX_OP2_IS_GR_NEW, 140): R2がGRか (同じ形) / 1 FF (D=A_EX_OP2_IS_GR_NEW, 140): R2 is a GR (same form)
wire           A_EX_OP2_IS_GR_NEW;                      // FF A_EX_OP2_IS_GR のD入力 (140で作る組合せ回路の出力) / D input of FF A_EX_OP2_IS_GR (output of the logic in 140)
wire [5:0]     DD_JB_INSN_AD_PART2P4;                   // 組合せ 6bit (140): ... + 4  -- 6bitの+4: 入力6本→LUT6 x6 (加算器にならない) / comb 6-bit (140): 6-bit +4: 6 inputs -> 6 LUT6s (no adder)
reg  [31:0]    A_LS_OPB_DT;                             // FF x32 (D=A_LS_OPB_DT_NEW, 140): Aへ渡すベースレジスタ値: 新しい順の32bit優先MUX (バイパス網, CPUで最大の組合せ回路) / 32 FFs (D=A_LS_OPB_DT_NEW, 140): base register value to A: 32-bit priority mux, newest first (bypass network, the largest logic)
wire [31:0]    A_LS_OPB_DT_NEW;                         // FF A_LS_OPB_DT のD入力 (140で作る組合せ回路の出力) / D input of FF A_LS_OPB_DT (output of the logic in 140)
reg  [31:0]    A_EX_OP1_DT;                             // FF x32 (D=A_EX_OP1_DT_NEW, 140): Aへ渡す第1オペランド: 新しい順の32bit優先MUX (バイパス網, CPUで最大の組合せ回路) / 32 FFs (D=A_EX_OP1_DT_NEW, 140): operand 1 to A: 32-bit priority mux, newest first (bypass network, the largest logic)
wire [31:0]    A_EX_OP1_DT_NEW;                         // FF A_EX_OP1_DT のD入力 (140で作る組合せ回路の出力) / D input of FF A_EX_OP1_DT (output of the logic in 140)
reg  [31:0]    A_EX_OP2_DT;                             // FF x32 (D=A_EX_OP2_DT_NEW, 140): Aへ渡す第2オペランド: 新しい順の32bit優先MUX (バイパス網, CPUで最大の組合せ回路) / 32 FFs (D=A_EX_OP2_DT_NEW, 140): operand 2 to A: 32-bit priority mux, newest first (bypass network, the largest logic)
wire [31:0]    A_EX_OP2_DT_NEW;                         // FF A_EX_OP2_DT のD入力 (140で作る組合せ回路の出力) / D input of FF A_EX_OP2_DT (output of the logic in 140)
reg  [3:0]     A_LS_RADB;                               // FF x4 (D=A_LS_RADB_NEW, 140): ベースの番号をAへ (A_INTLK中は保持): FF4本+CE → 060, 140 / 4 FFs (D=A_LS_RADB_NEW, 140): base number to A (held during A_INTLK): 4 FFs + CE -> 060, 140
wire [3:0]     A_LS_RADB_NEW;                           // FF A_LS_RADB のD入力 (140で作る組合せ回路の出力) / D input of FF A_LS_RADB (output of the logic in 140)
reg  [3:0]     A_EX_RAD1;                               // FF x4 (D=A_EX_RAD1_NEW, 140): R1の番号をAへ: FF4本+CE / 4 FFs (D=A_EX_RAD1_NEW, 140): R1 number to A: 4 FFs + CE
wire [3:0]     A_EX_RAD1_NEW;                           // FF A_EX_RAD1 のD入力 (140で作る組合せ回路の出力) / D input of FF A_EX_RAD1 (output of the logic in 140)
reg  [3:0]     A_EX_RAD2;                               // FF x4 (D=A_EX_RAD2_NEW, 140): R2の番号をAへ: FF4本+CE → 120のRSRの選択 / 4 FFs (D=A_EX_RAD2_NEW, 140): R2 number to A: 4 FFs + CE -> RSR select in 120
wire [3:0]     A_EX_RAD2_NEW;                           // FF A_EX_RAD2 のD入力 (140で作る組合せ回路の出力) / D input of FF A_EX_RAD2 (output of the logic in 140)
reg  [15:0]    A_DISP;                                  // FF x16 (D=A_DISP_NEW, 140): EAGの16bit変位: FF16本+CE → 120の加算器 / 16 FFs (D=A_DISP_NEW, 140): 16-bit EAG displacement: 16 FFs + CE -> adder in 120
wire [15:0]    A_DISP_NEW;                              // FF A_DISP のD入力 (140で作る組合せ回路の出力) / D input of FF A_DISP (output of the logic in 140)
// ---- 150-d-act.ch
reg            A_V;                                     // FF x1 (D=A_V_NEW, 150): Aの有効ビット: 発行 (D_FWD) か保持 (A_INTLK) (OR, FF1本) / 1 FF (D=A_V_NEW, 150): A valid: issue (D_FWD) or hold (A_INTLK) (OR, 1 FF)
wire           A_V_NEW;                                 // FF A_V のD入力 (150で作る組合せ回路の出力) / D input of FF A_V (output of the logic in 150)
reg            A_JB_IS_BC;                              // FF x1 (D=A_JB_IS_BC_NEW, 150): Aの命令が未解決BCか: 発行時は040の判定 / 1 FF (D=A_JB_IS_BC_NEW, 150): is A's insn an unsolved BC: 040's decision on issue
wire           A_JB_IS_BC_NEW;                          // FF A_JB_IS_BC のD入力 (150で作る組合せ回路の出力) / D input of FF A_JB_IS_BC (output of the logic in 150)
reg            A_JB_SUBJECT_TO_BC;                      // FF x1 (D=A_JB_SUBJECT_TO_BC_NEW, 150): 投機的に発行された命令か: 発行時に未解決BCがあれば1 / 1 FF (D=A_JB_SUBJECT_TO_BC_NEW, 150): issued speculatively: 1 if a BC is pending at issue
wire           A_JB_SUBJECT_TO_BC_NEW;                  // FF A_JB_SUBJECT_TO_BC のD入力 (150で作る組合せ回路の出力) / D input of FF A_JB_SUBJECT_TO_BC (output of the logic in 150)
reg            A_JB_V;                                  // FF x1 (D=A_JB_V_NEW, 150): Aに実行する分岐があるか: 不成立と分かったBCは除く / 1 FF (D=A_JB_V_NEW, 150): A has a branch to execute: minus BCs known not taken
wire           A_JB_V_NEW;                              // FF A_JB_V のD入力 (150で作る組合せ回路の出力) / D input of FF A_JB_V (output of the logic in 150)
reg            A_LS_SOLVING_BC;                         // FF x1 (D=A_LS_SOLVING_BC_NEW, 150): 同時発行のBCのCCをLS側が作る: 保持/発行/0 / 1 FF (D=A_LS_SOLVING_BC_NEW, 150): LS side makes the co-issued BC's CC: hold / issue / 0
wire           A_LS_SOLVING_BC_NEW;                     // FF A_LS_SOLVING_BC のD入力 (150で作る組合せ回路の出力) / D input of FF A_LS_SOLVING_BC (output of the logic in 150)
reg            A_EX_SOLVING_BC;                         // FF x1 (D=A_EX_SOLVING_BC_NEW, 150): 同時発行のBCのCCをEX側が作る / 1 FF (D=A_EX_SOLVING_BC_NEW, 150): EX side makes the co-issued BC's CC
wire           A_EX_SOLVING_BC_NEW;                     // FF A_EX_SOLVING_BC のD入力 (150で作る組合せ回路の出力) / D input of FF A_EX_SOLVING_BC (output of the logic in 150)
reg  [2:0]     A_INTCODE;                               // FF x3 (D=A_INTCODE_NEW, 150): 不正命令の割り込みコード: 保持/発行/0 (bit0だけが意味を持つ) / 3 FFs (D=A_INTCODE_NEW, 150): illegal-insn code: hold / issue / 0 (only bit 0 matters)
wire [2:0]     A_INTCODE_NEW;                           // FF A_INTCODE のD入力 (150で作る組合せ回路の出力) / D input of FF A_INTCODE (output of the logic in 150)
reg  [1:0]     A_PRIVCODE;                              // FF x2 (D=A_PRIVCODE_NEW, 150): 特権命令の種類: 2bit, 保持/発行/0 / 2 FFs (D=A_PRIVCODE_NEW, 150): privileged kind: 2 bits, hold / issue / 0
wire [1:0]     A_PRIVCODE_NEW;                          // FF A_PRIVCODE のD入力 (150で作る組合せ回路の出力) / D input of FF A_PRIVCODE (output of the logic in 150)
reg            A_LS_LD_V;                               // FF x1 (D=A_LS_LD_V_NEW, 150): LSパイプがメモリを読むか / 1 FF (D=A_LS_LD_V_NEW, 150): does the LS pipe read memory
wire           A_LS_LD_V_NEW;                           // FF A_LS_LD_V のD入力 (150で作る組合せ回路の出力) / D input of FF A_LS_LD_V (output of the logic in 150)
reg            A_WE1;                                   // FF x1 (D=A_WE1_NEW, 150): LSパイプがGRに書くか / 1 FF (D=A_WE1_NEW, 150): does the LS pipe write a GR
wire           A_WE1_NEW;                               // FF A_WE1 のD入力 (150で作る組合せ回路の出力) / D input of FF A_WE1 (output of the logic in 150)
reg            A_LS_ST_V;                               // FF x1 (D=A_LS_ST_V_NEW, 150): ストアか: 保持/発行/0 (FF+LUT) / 1 FF (D=A_LS_ST_V_NEW, 150): store?: hold / issue / 0 (FF + LUT)
wire           A_LS_ST_V_NEW;                           // FF A_LS_ST_V のD入力 (150で作る組合せ回路の出力) / D input of FF A_LS_ST_V (output of the logic in 150)
reg            A_LS_OPS_IS_GR;                          // FF x1 (D=A_LS_OPS_IS_GR_NEW, 150): レジスタオペランドRSを使うか / 1 FF (D=A_LS_OPS_IS_GR_NEW, 150): uses register operand RS
wire           A_LS_OPS_IS_GR_NEW;                      // FF A_LS_OPS_IS_GR のD入力 (150で作る組合せ回路の出力) / D input of FF A_LS_OPS_IS_GR (output of the logic in 150)
reg            A_LS_SETCC;                              // FF x1 (D=A_LS_SETCC_NEW, 150): LSパイプがCCを変えるか (EX-RMのSETCC) / 1 FF (D=A_LS_SETCC_NEW, 150): LS pipe sets CC (EX-RM SETCC)
wire           A_LS_SETCC_NEW;                          // FF A_LS_SETCC のD入力 (150で作る組合せ回路の出力) / D input of FF A_LS_SETCC (output of the logic in 150)
reg            A_EX_SETCC;                              // FF x1 (D=A_EX_SETCC_NEW, 150): EXパイプがCCを変えるか / 1 FF (D=A_EX_SETCC_NEW, 150): EX pipe sets CC
wire           A_EX_SETCC_NEW;                          // FF A_EX_SETCC のD入力 (150で作る組合せ回路の出力) / D input of FF A_EX_SETCC (output of the logic in 150)
reg            A_WE2;                                   // FF x1 (D=A_WE2_NEW, 150): EXパイプがGRに書くか / 1 FF (D=A_WE2_NEW, 150): does the EX pipe write a GR
wire           A_WE2_NEW;                               // FF A_WE2 のD入力 (150で作る組合せ回路の出力) / D input of FF A_WE2 (output of the logic in 150)
reg  [3:0]     A_WAD1;                                  // FF x4 (D=A_WAD1_NEW, 150): LS側の書き込み番号 = ILSのRD: CE付きFF4本 (保持=CE, LUT無し) / 4 FFs (D=A_WAD1_NEW, 150): LS write number = ILS RD: 4 FFs with CE (hold = CE, no LUT)
wire [3:0]     A_WAD1_NEW;                              // FF A_WAD1 のD入力 (150で作る組合せ回路の出力) / D input of FF A_WAD1 (output of the logic in 150)
reg  [3:0]     A_LS_RADS;                               // FF x4 (D=A_LS_RADS_NEW, 150): RSの番号: LSならRD/RS, EX-RMならRS (4bit 2:1 MUX + CE) / 4 FFs (D=A_LS_RADS_NEW, 150): RS number: RD/RS for LS, RS for EX-RM (4-bit 2:1 mux + CE)
wire [3:0]     A_LS_RADS_NEW;                           // FF A_LS_RADS のD入力 (150で作る組合せ回路の出力) / D input of FF A_LS_RADS (output of the logic in 150)
reg  [3:0]     A_WAD2;                                  // FF x4 (D=A_WAD2_NEW, 150): EX側の書き込み番号 / 4 FFs (D=A_WAD2_NEW, 150): EX write number
wire [3:0]     A_WAD2_NEW;                              // FF A_WAD2 のD入力 (150で作る組合せ回路の出力) / D input of FF A_WAD2 (output of the logic in 150)
reg  [4:0]     A_LS_OPCODE;                             // FF x5 (D=A_LS_OPCODE_NEW, 150): EのALUに使う5bit opcode: 保持 (CE) / 5 FFs (D=A_LS_OPCODE_NEW, 150): 5-bit opcode for the E ALU: hold (CE)
wire [4:0]     A_LS_OPCODE_NEW;                         // FF A_LS_OPCODE のD入力 (150で作る組合せ回路の出力) / D input of FF A_LS_OPCODE (output of the logic in 150)
reg            A_IS_SUPERSCALAR;                        // FF x1 (D=A_IS_SUPERSCALAR_NEW, 150): 2命令同時発行したか: CE付きFF / 1 FF (D=A_IS_SUPERSCALAR_NEW, 150): dual issued?: FF with CE
wire           A_IS_SUPERSCALAR_NEW;                    // FF A_IS_SUPERSCALAR のD入力 (150で作る組合せ回路の出力) / D input of FF A_IS_SUPERSCALAR (output of the logic in 150)
reg            A_FIRST_IS_EX;                           // FF x1 (D=A_FIRST_IS_EX_NEW, 150): 1命令目がEXか: CE付きFF / 1 FF (D=A_FIRST_IS_EX_NEW, 150): first is EX?: FF with CE
wire           A_FIRST_IS_EX_NEW;                       // FF A_FIRST_IS_EX のD入力 (150で作る組合せ回路の出力) / D input of FF A_FIRST_IS_EX (output of the logic in 150)
reg            A_LATTER_IS_JB;                          // FF x1 (D=A_LATTER_IS_JB_NEW, 150): 2命令目が分岐か: CE付きFF / 1 FF (D=A_LATTER_IS_JB_NEW, 150): second is a branch?: FF with CE
wire           A_LATTER_IS_JB_NEW;                      // FF A_LATTER_IS_JB のD入力 (150で作る組合せ回路の出力) / D input of FF A_LATTER_IS_JB (output of the logic in 150)
reg  [31:0]    A_TGT;                                   // FF x32 (D=A_TGT_NEW, 150): PC相対の分岐先: 040のDD_TGT加算器の出力をCE付きFF32本で受ける / 32 FFs (D=A_TGT_NEW, 150): PC-relative target: DD_TGT adder output into 32 FFs with CE
wire [31:0]    A_TGT_NEW;                               // FF A_TGT のD入力 (150で作る組合せ回路の出力) / D input of FF A_TGT (output of the logic in 150)
reg  [3:0]     A_EX_OPCODE;                             // FF x4 (D=A_EX_OPCODE_NEW, 150): EXUのopcode (4bit): 保持 / 4 FFs (D=A_EX_OPCODE_NEW, 150): EXU opcode (4 bits): hold
wire [3:0]     A_EX_OPCODE_NEW;                         // FF A_EX_OPCODE のD入力 (150で作る組合せ回路の出力) / D input of FF A_EX_OPCODE (output of the logic in 150)
reg            A_SET_EAG_TO_TGT;                        // FF x1 (D=A_SET_EAG_TO_TGT_NEW, 150): レジスタ間接分岐: 分岐先をAのEAGで作る → 130, 170 / 1 FF (D=A_SET_EAG_TO_TGT_NEW, 150): register-indirect branch: target from the A EAG -> 130, 170
wire           A_SET_EAG_TO_TGT_NEW;                    // FF A_SET_EAG_TO_TGT のD入力 (150で作る組合せ回路の出力) / D input of FF A_SET_EAG_TO_TGT (output of the logic in 150)
// ---- 160-op-lb2.ch
wire           OP_B_FORWARDING;                         // 組合せ (160): OP-Bの要求が終わる: ST2は1サイクル (外部バスなら書き込み完了待ち) / comb (160): the OP-B request finishes: ST2 in 1 cycle (with an external bus, wait for the write)
wire           GO_SU;                                   // 組合せ (160): このサイクルに新しい要求を受け付ける (OR) / comb (160): a new request is accepted this cycle (OR)
wire [1:0]     ACCEPTING_OPC;                           // 組合せ 2bit (160): 受け付ける要求の種類: ST2 / comb 2-bit (160): ST / LD (2bit, LUT3 x2) / kind of the accepted request: ST2 / ST / LD (2 bits, two LUT3s)
wire [31:0]    ACCEPTING_AD;                            // 組合せ 32bit (160): 受け付ける番地: ST2ならSTB_AD, それ以外はAのEAG出力 (32bit 2:1 MUX) / comb 32-bit (160): accepted address: STB_AD for ST2, else the A EAG output (32-bit 2:1 mux)
wire           OP_WAIT_STAYS;                           // 組合せ (160): OP-WAITが留まる: OP-Bが終わらず待ち要求がある (AND3) / comb (160): OP-WAIT stays: OP-B not done and a waiting request (AND3)
wire           OP_WAIT_ACCEPT;                          // 組合せ (160): 新要求をOP-WAITへ入れる: OP-Bが終わらないうちに来た (AND3) / comb (160): put the new request into OP-WAIT: it came while OP-B is busy (AND3)
reg            OP_WAIT_V;                               // FF x1 (D=OP_WAIT_V_NEW, 160): OP-WAITの有効ビット: 留まる/受け付け/空 (FF+LUT) / 1 FF (D=OP_WAIT_V_NEW, 160): OP-WAIT valid: stay / accept / empty (FF + LUT)
wire           OP_WAIT_V_NEW;                           // FF OP_WAIT_V のD入力 (160で作る組合せ回路の出力) / D input of FF OP_WAIT_V (output of the logic in 160)
reg  [1:0]     OP_WAIT_OPC;                             // FF x2 (D=OP_WAIT_OPC_NEW, 160): 要求の種類: 留まるなら保持 (CE), そうでなければ新要求 (2bit) / 2 FFs (D=OP_WAIT_OPC_NEW, 160): kind: hold (CE) if staying, else the new one (2 bits)
wire [1:0]     OP_WAIT_OPC_NEW;                         // FF OP_WAIT_OPC のD入力 (160で作る組合せ回路の出力) / D input of FF OP_WAIT_OPC (output of the logic in 160)
reg            OP_WAIT_WE;                              // FF x1 (D=OP_WAIT_WE_NEW, 160): 書き込みか (ST2なら1) / 1 FF (D=OP_WAIT_WE_NEW, 160): write? (1 for ST2)
wire           OP_WAIT_WE_NEW;                          // FF OP_WAIT_WE のD入力 (160で作る組合せ回路の出力) / D input of FF OP_WAIT_WE (output of the logic in 160)
reg  [31:0]    OP_WAIT_AD;                              // FF x32 (D=OP_WAIT_AD_NEW, 160): 番地: CE付きFF32本, D=ACCEPTING_AD / 32 FFs (D=OP_WAIT_AD_NEW, 160): address: 32 FFs with CE, D = ACCEPTING_AD
wire [31:0]    OP_WAIT_AD_NEW;                          // FF OP_WAIT_AD のD入力 (160で作る組合せ回路の出力) / D input of FF OP_WAIT_AD (output of the logic in 160)
reg  [31:0]    OP_WAIT_DT;                              // FF x32 (D=OP_WAIT_DT_NEW, 160): 書き込みデータ: CE付きFF32本, D=STB_DT (LUT無し) / 32 FFs (D=OP_WAIT_DT_NEW, 160): write data: 32 FFs with CE, D = STB_DT (no LUT)
wire [31:0]    OP_WAIT_DT_NEW;                          // FF OP_WAIT_DT のD入力 (160で作る組合せ回路の出力) / D input of FF OP_WAIT_DT (output of the logic in 160)
reg            OP_WAIT_SUBJECT_TO_BC;                   // FF x1 (D=OP_WAIT_SUBJECT_TO_BC_NEW, 160): 投機的な要求か: 留まるなら保持し解決で0 / 1 FF (D=OP_WAIT_SUBJECT_TO_BC_NEW, 160): speculative request: held, 0 once solved
wire           OP_WAIT_SUBJECT_TO_BC_NEW;               // FF OP_WAIT_SUBJECT_TO_BC のD入力 (160で作る組合せ回路の出力) / D input of FF OP_WAIT_SUBJECT_TO_BC (output of the logic in 160)
wire           OP_B_STAYS;                              // 組合せ (160): OP-Bが留まる: 有効で終わらない (AND) / comb (160): OP-B stays: valid and not finished (AND)
wire           OP_B_SHIFT;                              // 組合せ (160): OP-WAITからOP-Bへ移す (別名) / comb (160): move OP-WAIT into OP-B (alias)
reg            OP_B_V;                                  // FF x1 (D=OP_B_V_NEW, 160): OP-Bの有効ビット: 留まる/移す/新要求 (FF+LUT) / 1 FF (D=OP_B_V_NEW, 160): OP-B valid: stay / shift / new (FF + LUT)
wire           OP_B_V_NEW;                              // FF OP_B_V のD入力 (160で作る組合せ回路の出力) / D input of FF OP_B_V (output of the logic in 160)
reg  [1:0]     OP_B_OPC;                                // FF x2 (D=OP_B_OPC_NEW, 160): OP-Bの種類: 保持はCEに, 残りがLUT4 (NETLIST.mdの例) / 2 FFs (D=OP_B_OPC_NEW, 160): OP-B kind: hold goes to CE, the rest is a LUT4 (the NETLIST.md example)
wire [1:0]     OP_B_OPC_NEW;                            // FF OP_B_OPC のD入力 (160で作る組合せ回路の出力) / D input of FF OP_B_OPC (output of the logic in 160)
wire           LBS_WE_NEW;                              // FF LBS_WE のD入力 (160で作る組合せ回路の出力) / D input of FF LBS_WE (output of the logic in 160)
wire [31:0]    LBS_AD_NEW;                              // FF LBS_AD のD入力 (160で作る組合せ回路の出力) / D input of FF LBS_AD (output of the logic in 160)
wire [31:0]    LBS_DT_NEW;                              // FF LBS_DT のD入力 (160で作る組合せ回路の出力) / D input of FF LBS_DT (output of the logic in 160)
reg            OP_B_SUBJECT_TO_BC;                      // FF x1 (D=OP_B_SUBJECT_TO_BC_NEW, 160): OP-Bの要求が投機的か / 1 FF (D=OP_B_SUBJECT_TO_BC_NEW, 160): is the OP-B request speculative
wire           OP_B_SUBJECT_TO_BC_NEW;                  // FF OP_B_SUBJECT_TO_BC のD入力 (160で作る組合せ回路の出力) / D input of FF OP_B_SUBJECT_TO_BC (output of the logic in 160)
wire           OP_B_NEW_NEW;                            // FF OP_B_NEW のD入力 (160で作る組合せ回路の出力) / D input of FF OP_B_NEW (output of the logic in 160)
// ---- 170-if-req.ch
wire           IWQ_FULL;                                // 組合せ (170): キュー満杯: NIP<=1で6語すべて有効 (LUT5) → 続きのフェッチを止める / comb (170): queue full: NIP<=1 and all 6 words valid (LUT5) -> stop sequential fetch
wire [31:0]    IF_INCR_1;                               // 組合せ 32bit (170): 続きのフェッチの基準番地: 要求中IBの番地かキュー末尾の番地 (32bit 3:1 MUX) / comb 32-bit (170): base of the next sequential fetch: pending IB address or queue-tail address (32-bit 3:1 mux)
wire [4:0]     IF_INCR_2;                               // 組合せ 5bit (170): 増分: 要求中がこのキュー宛てか / comb 5-bit (170): increment: pending fetch is for this queue
wire [31:0]    IF_INCR_OUT;                             // 組合せ 32bit (170): 次のフェッチ番地 = 基準 + 0/8: 32bit加算器 (下位3bitは素通し, CARRY4 x8) / comb 32-bit (170): next fetch address = base + 0/8: 32-bit adder (low 3 bits pass through, 8 CARRY4s)
wire           IF_CASE_START;                           // 組合せ (170): 理由1: 再スタート (PCから) / comb (170): reason 1: restart (from PC)
wire           IF_CASE_J;                               // 組合せ (170): 理由2: Aのレジスタ間接分岐 (EAGの番地へ) / comb (170): reason 2: register-indirect branch in A (to the EAG address)
wire           IF_CASE_BA;                              // 組合せ (170): 理由3: Dで成立が確定した分岐 (DD_TGTへ) / comb (170): reason 3: branch known taken in D (to DD_TGT)
wire           IF_CASE_BC;                              // 組合せ (170): 理由4: 未解決BC (分岐先をもう一方のキューへ) / comb (170): reason 4: unsolved BC (target into the other queue)
wire           IF_CASE_NULL;                            // 組合せ (170): 理由5: JA/JL発行中 (分岐先がAで出るまで要求しない) / comb (170): reason 5: JA/JL issuing (no request until A has the target)
wire           IF_REQ_V;                                // 組合せ (170): フェッチ要求を出すか: 再スタートは必ず, Jは A_FWD / comb (170): issue a fetch: always on restart, J needs A_FWD
wire [31:0]    IF_REQ_AD;                               // 組合せ 32bit (170): フェッチ番地: PC / EAG出力 / comb 32-bit (170): ... / fetch address: PC / EAG output /
wire           IF_REQ_ID;                               // 組合せ (170): 入れるキュー: 再スタートはA(0), 未解決BCは反対側, それ以外は今のキュー (LUT3) / comb (170): target queue: A (0) on restart, the other one for an unsolved BC, else current (LUT3)
wire           CANCEL_IB;                               // 組合せ (170): 要求中のフェッチを捨てる: 再スタート, または同じキュー宛てで分岐した / comb (170): drop the pending fetch: restart, or a branch on the same queue
// ---- 180-if-lbs.ch
wire           SU_IF_CLH;                               // 組合せ (180): 要求中の命令データが届いた: IB_V & ポート入力 (AND) → 190, 200 / comb (180): pending fetch data arrived: IB_V & port input (AND) -> 190, 200
wire           SU_IF_RDY;                               // 組合せ (180): 新しいフェッチを受け付ける: 要求があり, IBが空か今届いた / comb (180): accept a new fetch: a request, and IB empty or just arrived
wire [31:0]    I_LBS_H;                                 // 組合せ 32bit (180): 届いた8バイトの前半(先の命令): 届いていなければ0xf0f0f0f0 (32bit 2:1 MUX, 定数側はLUT内に吸収) / comb 32-bit (180): first word of the 8 bytes (earlier insn): 0xf0f0f0f0 if none (32-bit 2:1 mux, constant folded into the LUT)
wire [31:0]    I_LBS_L;                                 // 組合せ 32bit (180): 後半(後の命令): 届いていなければ0xff0f0f0f → 200のIWQ_x_4/5 / comb 32-bit (180): second word (later insn): 0xff0f0f0f if none -> IWQ_x_4/5 in 200
// ---- 190-if-stm.ch
reg            IB_V;                                    // FF x1 (D=IB_V_NEW, 190): 要求中フラグ: 要求を受け付けたら1, 届いたか取り消しで0, それ以外は保持 (FF+LUT5) / 1 FF (D=IB_V_NEW, 190): pending flag: 1 when accepted, 0 when arrived or cancelled, else hold (FF + LUT5)
wire           IB_V_NEW;                                // FF IB_V のD入力 (190で作る組合せ回路の出力) / D input of FF IB_V (output of the logic in 190)
wire [31:0]    IB_AD_NEW;                               // FF IB_AD のD入力 (190で作る組合せ回路の出力) / D input of FF IB_AD (output of the logic in 190)
reg            IB_ID;                                   // FF x1 (D=IB_ID_NEW, 190): 要求中のフェッチの宛先キュー (CE付きFF) / 1 FF (D=IB_ID_NEW, 190): destination queue of the pending fetch (FF with CE)
wire           IB_ID_NEW;                               // FF IB_ID のD入力 (190で作る組合せ回路の出力) / D input of FF IB_ID (output of the logic in 190)
reg            CUR_IWQ_ID;                              // FF x1 (D=CUR_IWQ_ID_NEW, 190): 現在のキュー: 成立と予測したBCを発行したら反転, 割り込みで0 (FF+LUT4) / 1 FF (D=CUR_IWQ_ID_NEW, 190): current queue: flips when a BC predicted taken issues, 0 on interrupt (FF + LUT4)
wire           CUR_IWQ_ID_NEW;                          // FF CUR_IWQ_ID のD入力 (190で作る組合せ回路の出力) / D input of FF CUR_IWQ_ID (output of the logic in 190)
wire           SU_IF_CLH_NOCAN;                         // 組合せ (190): 届いた命令をキューに入れてよい: 取り消されず満杯でない (AND3) / comb (190): arrived insns may enter the queue: not cancelled and not full (AND3)
wire [1:0]     EMIT;                                    // 組合せ 2bit (190): このサイクルに発行した命令数 0/1/2 (2bit, LUT2本) / comb 2-bit (190): insns issued this cycle 0/1/2 (2 bits, 2 LUTs)
wire [1:0]     EMIT_FOR_A;                              // 組合せ 2bit (190): キューAから発行した数 (Bが使用中なら0): 2bit AND / comb 2-bit (190): insns issued from queue A (0 when B is used): 2-bit AND
wire [2:0]     NIP_AFTER_EMIT_A;                        // 組合せ 3bit (190): 発行後のNIP_A = NIP_A + EMIT: 3bit+2bitの加算 → LUT3本 (CARRY4は使わない) / comb 3-bit (190): NIP_A after issue = NIP_A + EMIT: 3-bit + 2-bit add -> 3 LUTs (no CARRY4)
wire [1:0]     EMIT_FOR_B;                              // 組合せ 2bit (190): キューBから発行した数 / comb 2-bit (190): insns issued from queue B
wire [2:0]     NIP_AFTER_EMIT_B;                        // 組合せ 3bit (190): 発行後のNIP_B (LUT3本) / comb 3-bit (190): NIP_B after issue (3 LUTs)
wire           SFTUP_A;                                 // 組合せ (190): キューAを2語シフト: 4,5番が有効で発行後のNIP>=2 (LUT) → 200の192本のCE / comb (190): shift queue A by 2 words: 4,5 valid and NIP after issue >= 2 (LUT) -> CE of 192 FFs in 200
wire           SFTUP_B;                                 // 組合せ (190): キューBを2語シフト (同じ形, 高ファンアウト) / comb (190): shift queue B by 2 words (same form, high fan-out)
wire           DD_JB_TKN;                               // 組合せ (190): Dで発行した分岐が成立確定 (未解決でも不成立でもない) (AND3) / comb (190): branch issued in D is surely taken (neither unsolved nor untaken) (AND3)
wire           CLEAR_NIP_A;                             // 組合せ (190): キューAをクリア: Aで成立分岐 / Bで未解決BC (Aに分岐先) / comb (190): clear queue A: taken branch on A / unsolved BC on B (target into A)
wire           CLEAR_NIP_B;                             // 組合せ (190): キューBをクリア (Aと対称) / comb (190): clear queue B (symmetric to A)
wire [2:0]     NIP_A_TMP;                               // 組合せ 3bit (190): 次のNIP_A (3bit): クリアなら6+(分岐先が後半なら1) / comb 3-bit (190): next NIP_A (3 bits): on clear 6 + (1 if the target is the second word)
reg  [2:0]     NIP_B;                                   // FF x3 (D=NIP_B_NEW, 190): 次のNIP_B (NIP_Aと同じ形) / 3 FFs (D=NIP_B_NEW, 190): next NIP_B (same as NIP_A)
wire [2:0]     NIP_B_NEW;                               // FF NIP_B のD入力 (190で作る組合せ回路の出力) / D input of FF NIP_B (output of the logic in 190)
reg  [2:0]     NIP_A_REG;                               // FF x3 (D=NIP_A_REG_NEW, 190): NIP_Aは^6して格納 (bit1,2の反転はLUTに吸収) → リセット0で空(6) / 3 FFs (D=NIP_A_REG_NEW, 190): NIP_A stored ^6 (inversion of bits 1,2 absorbed in LUTs) -> reset 0 means empty (6)
wire [2:0]     NIP_A_REG_NEW;                           // FF NIP_A_REG のD入力 (190で作る組合せ回路の出力) / D input of FF NIP_A_REG (output of the logic in 190)
reg  [31:0]    D_IF_AD_A;                               // FF x32 (D=D_IF_AD_A_NEW, 190): キューA末尾の8バイトの番地: クリア時はフェッチ番地 / 32 FFs (D=D_IF_AD_A_NEW, 190): address of the last 8 bytes of queue A: fetch address on clear
wire [31:0]    D_IF_AD_A_NEW;                           // FF D_IF_AD_A のD入力 (190で作る組合せ回路の出力) / D input of FF D_IF_AD_A (output of the logic in 190)
reg  [31:0]    D_IF_AD_B;                               // FF x32 (D=D_IF_AD_B_NEW, 190): キューB末尾の番地 / 32 FFs (D=D_IF_AD_B_NEW, 190): address of the tail of queue B
wire [31:0]    D_IF_AD_B_NEW;                           // FF D_IF_AD_B のD入力 (190で作る組合せ回路の出力) / D input of FF D_IF_AD_B (output of the logic in 190)
// ---- 200-if-iwq.ch
reg  [31:0]    IWQ_A_0;                                 // FF x32 (D=IWQ_A_0_NEW, 200): A0: シフトならA2を取り込む. D=A2のQ直結, CE=SFTUP_A (LUT無しのFF32本) / 32 FFs (D=IWQ_A_0_NEW, 200): A0: takes A2 on shift. D wired to A2, CE = SFTUP_A (32 FFs, no LUT)
wire [31:0]    IWQ_A_0_NEW;                             // FF IWQ_A_0 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_A_0 (output of the logic in 200)
reg  [31:0]    IWQ_A_1;                                 // FF x32 (D=IWQ_A_1_NEW, 200): A1 ← A3 (CE=SFTUP_A) / 32 FFs (D=IWQ_A_1_NEW, 200): A1 <- A3 (CE = SFTUP_A)
wire [31:0]    IWQ_A_1_NEW;                             // FF IWQ_A_1 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_A_1 (output of the logic in 200)
reg  [31:0]    IWQ_A_2;                                 // FF x32 (D=IWQ_A_2_NEW, 200): A2 ← A4 (CE=SFTUP_A) / 32 FFs (D=IWQ_A_2_NEW, 200): A2 <- A4 (CE = SFTUP_A)
wire [31:0]    IWQ_A_2_NEW;                             // FF IWQ_A_2 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_A_2 (output of the logic in 200)
reg  [31:0]    IWQ_A_3;                                 // FF x32 (D=IWQ_A_3_NEW, 200): A3 ← A5 (CE=SFTUP_A) / 32 FFs (D=IWQ_A_3_NEW, 200): A3 <- A5 (CE = SFTUP_A)
wire [31:0]    IWQ_A_3_NEW;                             // FF IWQ_A_3 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_A_3 (output of the logic in 200)
reg            IWQ_A_V01;                               // FF x1 (D=IWQ_A_V01_NEW, 200): 0,1番の有効ビット ← 2,3番の有効ビット (CE付きFF) / 1 FF (D=IWQ_A_V01_NEW, 200): valid of 0,1 <- valid of 2,3 (FF with CE)
wire           IWQ_A_V01_NEW;                           // FF IWQ_A_V01 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_A_V01 (output of the logic in 200)
reg            IWQ_A_V23;                               // FF x1 (D=IWQ_A_V23_NEW, 200): 2,3番の有効ビット ← 4,5番の有効ビット / 1 FF (D=IWQ_A_V23_NEW, 200): valid of 2,3 <- valid of 4,5
wire           IWQ_A_V23_NEW;                           // FF IWQ_A_V23 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_A_V23 (output of the logic in 200)
reg  [31:0]    IWQ_B_0;                                 // FF x32 (D=IWQ_B_0_NEW, 200): B0 ← B2 (CE=SFTUP_B) / 32 FFs (D=IWQ_B_0_NEW, 200): B0 <- B2 (CE = SFTUP_B)
wire [31:0]    IWQ_B_0_NEW;                             // FF IWQ_B_0 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_B_0 (output of the logic in 200)
reg  [31:0]    IWQ_B_1;                                 // FF x32 (D=IWQ_B_1_NEW, 200): B1 ← B3 / 32 FFs (D=IWQ_B_1_NEW, 200): B1 <- B3
wire [31:0]    IWQ_B_1_NEW;                             // FF IWQ_B_1 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_B_1 (output of the logic in 200)
reg  [31:0]    IWQ_B_2;                                 // FF x32 (D=IWQ_B_2_NEW, 200): B2 ← B4 / 32 FFs (D=IWQ_B_2_NEW, 200): B2 <- B4
wire [31:0]    IWQ_B_2_NEW;                             // FF IWQ_B_2 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_B_2 (output of the logic in 200)
reg  [31:0]    IWQ_B_3;                                 // FF x32 (D=IWQ_B_3_NEW, 200): B3 ← B5 / 32 FFs (D=IWQ_B_3_NEW, 200): B3 <- B5
wire [31:0]    IWQ_B_3_NEW;                             // FF IWQ_B_3 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_B_3 (output of the logic in 200)
reg            IWQ_B_V01;                               // FF x1 (D=IWQ_B_V01_NEW, 200): Bの0,1番の有効ビット ← 2,3番 / 1 FF (D=IWQ_B_V01_NEW, 200): B valid of 0,1 <- 2,3
wire           IWQ_B_V01_NEW;                           // FF IWQ_B_V01 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_B_V01 (output of the logic in 200)
reg            IWQ_B_V23;                               // FF x1 (D=IWQ_B_V23_NEW, 200): Bの2,3番の有効ビット ← 4,5番 / 1 FF (D=IWQ_B_V23_NEW, 200): B valid of 2,3 <- 4,5
wire           IWQ_B_V23_NEW;                           // FF IWQ_B_V23 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_B_V23 (output of the logic in 200)
reg  [31:0]    IWQ_A_4;                                 // FF x32 (D=IWQ_A_4_NEW, 200): A4: シフトしたか空なら届いた前半 I_LBS_H (D=I_LBS_H, CE=SFTUP|!V45) / 32 FFs (D=IWQ_A_4_NEW, 200): A4: arriving first word I_LBS_H if shifted or empty (D = I_LBS_H, CE = SFTUP | !V45)
wire [31:0]    IWQ_A_4_NEW;                             // FF IWQ_A_4 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_A_4 (output of the logic in 200)
reg  [31:0]    IWQ_A_5;                                 // FF x32 (D=IWQ_A_5_NEW, 200): A5: 届いた後半 I_LBS_L (同じCE) / 32 FFs (D=IWQ_A_5_NEW, 200): A5: arriving second word I_LBS_L (same CE)
wire [31:0]    IWQ_A_5_NEW;                             // FF IWQ_A_5 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_A_5 (output of the logic in 200)
reg  [31:0]    IWQ_B_4;                                 // FF x32 (D=IWQ_B_4_NEW, 200): B4: 同じI_LBS_Hを受ける (どちらに入るかは有効ビットだけで決まる) / 32 FFs (D=IWQ_B_4_NEW, 200): B4: gets the same I_LBS_H (which queue is decided only by the valid bits)
wire [31:0]    IWQ_B_4_NEW;                             // FF IWQ_B_4 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_B_4 (output of the logic in 200)
reg  [31:0]    IWQ_B_5;                                 // FF x32 (D=IWQ_B_5_NEW, 200): B5: 同じI_LBS_Lを受ける / 32 FFs (D=IWQ_B_5_NEW, 200): B5: gets the same I_LBS_L
wire [31:0]    IWQ_B_5_NEW;                             // FF IWQ_B_5 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_B_5 (output of the logic in 200)
reg            IWQ_A_V45;                               // FF x1 (D=IWQ_A_V45_NEW, 200): Aの4,5番の有効ビット: シフトで空, A宛ての命令が届けば1 (LUT4) → 010, 190 / 1 FF (D=IWQ_A_V45_NEW, 200): valid of A4,5: emptied by shift, 1 when insns for A arrive (LUT4) -> 010, 190
wire           IWQ_A_V45_NEW;                           // FF IWQ_A_V45 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_A_V45 (output of the logic in 200)
reg            IWQ_B_V45;                               // FF x1 (D=IWQ_B_V45_NEW, 200): Bの4,5番の有効ビット (IB_ID=1で届いたとき) / 1 FF (D=IWQ_B_V45_NEW, 200): valid of B4,5 (when insns arrive with IB_ID = 1)
wire           IWQ_B_V45_NEW;                           // FF IWQ_B_V45 のD入力 (200で作る組合せ回路の出力) / D input of FF IWQ_B_V45 (output of the logic in 200)
// ---- 210-g-bc.ch
wire           GG_SOLVING_CASE_ON_E;                    // 組合せ (210): EでBCが解決する: Eが進み / comb (210): BC solved in E: E moves on
wire           GG_SOLVING_CASE_ON_A;                    // 組合せ (210): AでBCが解決する: Aが進み / comb (210): BC solved in A: A moves on
wire           GG_SOLVING_CASE;                         // 組合せ (210): このサイクルにBCが解決する (OR) / comb (210): a BC is solved this cycle (OR)
wire [3:0]     GG_MASK_FOR_BC;                          // 組合せ 4bit (210): 判定に使うマスク: 発行済みBCは覚えたG_BC_MASK, 今発行するBCはIJBのマスク (4bit 2:1 MUX) / comb 4-bit (210): mask: stored G_BC_MASK for an issued BC, IJB's mask for one issuing now (4-bit 2:1 mux)
wire [1:0]     GG_CC_FOR_BC;                            // 組合せ 2bit (210): 判定に使うCC: EのALUかAのEXUの出力 (2bit 2:1 MUX, 演算器の直後) / comb 2-bit (210): CC used: E ALU or A EXU output (2-bit 2:1 mux right after the units)
wire           GG_ISSUEING_CASE;                        // 組合せ (210): Dで未解決BCを発行した (AND) / comb (210): an unsolved BC issued in D (AND)
reg            G_BC_PENDING;                            // FF x1 (D=G_BC_PENDING_NEW, 210): 未解決BCあり: 割り込みか解決で0, 発行で1 / 1 FF (D=G_BC_PENDING_NEW, 210): BC pending: 0 on interrupt or solve, 1 on issue
wire           G_BC_PENDING_NEW;                        // FF G_BC_PENDING のD入力 (210で作る組合せ回路の出力) / D input of FF G_BC_PENDING (output of the logic in 210)
reg            G_BC_JUST_SOLVED;                        // FF x1 (D=G_BC_JUST_SOLVED_NEW, 210): 解決した次の1サイクルだけ1 (FF1本, ファンアウト大) / 1 FF (D=G_BC_JUST_SOLVED_NEW, 210): 1 for one cycle after a solve (1 FF, large fan-out)
wire           G_BC_JUST_SOLVED_NEW;                    // FF G_BC_JUST_SOLVED のD入力 (210で作る組合せ回路の出力) / D input of FF G_BC_JUST_SOLVED (output of the logic in 210)
reg            G_BC_JUST_TAKEN;                         // FF x1 (D=G_BC_JUST_TAKEN_NEW, 210): 解決したBCが成立か / 1 FF (D=G_BC_JUST_TAKEN_NEW, 210): was the solved BC taken
wire           G_BC_JUST_TAKEN_NEW;                     // FF G_BC_JUST_TAKEN のD入力 (210で作る組合せ回路の出力) / D input of FF G_BC_JUST_TAKEN (output of the logic in 210)
reg            G_BC_TKN_PREDICTED;                      // FF x1 (D=G_BC_TKN_PREDICTED_NEW, 210): 発行時の予測を記憶 / 1 FF (D=G_BC_TKN_PREDICTED_NEW, 210): remember the prediction at issue
wire           G_BC_TKN_PREDICTED_NEW;                  // FF G_BC_TKN_PREDICTED のD入力 (210で作る組合せ回路の出力) / D input of FF G_BC_TKN_PREDICTED (output of the logic in 210)
reg  [3:0]     G_BC_MASK;                               // FF x4 (D=G_BC_MASK_NEW, 210): 発行時のCCマスクを記憶 (CE付きFF4本) → 090, 210 / 4 FFs (D=G_BC_MASK_NEW, 210): remember the CC mask at issue (4 FFs with CE) -> 090, 210
wire [3:0]     G_BC_MASK_NEW;                           // FF G_BC_MASK のD入力 (210で作る組合せ回路の出力) / D input of FF G_BC_MASK (output of the logic in 210)
// ---- EXU の出力 (090-e-act.ch / 120-a-dat.ch の exu() 呼び出し)
//      (outputs of the EXUs: the exu() calls of 090-e-act.ch / 120-a-dat.ch)
// 【ネットリスト解説】stm_exu のインスタンスは 2 個 (u_e_alu, u_a_exu)。
//   EE_* は E サイクルの LS パイプ ALU の出力, AA_* は A サイクルの EX パイプ EXU の
//   出力で、どちらも FF を通らない組合せ出力。AA_EXU_OUTPUT → (130) → B_EX_RES,
//   EE_ALU_OUTPUT → (090) → W_WDT1 / STB_DT のように次の段の FF の D 入力になるほか,
//   バイパス (140, 100) や分岐解決 (210) へも同じサイクルのうちに配られる。
//
// [Netlist notes] There are 2 instances of stm_exu (u_e_alu, u_a_exu).
//   EE_* are the outputs of the LS-pipe ALU in the E cycle, AA_* those of the EX-pipe EXU in the
//   A cycle; both are combinational outputs that do not pass through FFs. Besides becoming the
//   D inputs of the next stage's FFs, as in AA_EXU_OUTPUT -> (130) -> B_EX_RES and
//   EE_ALU_OUTPUT -> (090) -> W_WDT1 / STB_DT, they are also distributed in the same cycle to
//   the bypasses (140, 100) and to branch resolution (210).
wire [1:0]     EE_ALU_CC;                               // 組合せ 2bit (090): stm_exuの出力 結果のCC 2bit → W_CC, 210 (LSでBC解決) / comb 2-bit (090): stm_exu output result CC, 2 bits -> W_CC, 210 (BC solved by LS)
wire [31:0]    EE_ALU_OUTPUT;                           // 組合せ 32bit (090): stm_exuの出力 結果 32bit → W_WDT1, STB_DT, 050/100/140のバイパスMUX (組合せのまま) / comb 32-bit (090): stm_exu output result, 32 bits -> W_WDT1, STB_DT, bypass muxes in 050/100/140 (combinational)
wire [2:0]     EE_ALU_INT;                              // 組合せ 3bit (090): stm_exuの出力 オーバーフロー割り込みコード 3bit / comb 3-bit (090): stm_exu output overflow interrupt code, 3 bits
wire [1:0]     AA_EXU_CC;                               // 組合せ 2bit (120): stm_exuの出力 CC → 130のB_EX_CC, 210 (EXでBC解決) / comb 2-bit (120): stm_exu output CC -> B_EX_CC in 130, 210 (BC solved by EX)
wire [31:0]    AA_EXU_OUTPUT;                           // 組合せ 32bit (120): stm_exuの出力 演算結果 → AA_EX_RES / comb 32-bit (120): stm_exu output result -> AA_EX_RES
wire [2:0]     AA_EXU_INT;                              // 組合せ 3bit (120): stm_exuの出力 オーバーフロー → 130のB_INTCODE / comb 3-bit (120): stm_exu output overflow -> B_INTCODE in 130

// ---------------------------------------------------------------------
//  回路本体 (hard/*.ch を 1 対 1 に変換したもの)
//  The circuit itself (hard/*.ch converted one to one)
// ---------------------------------------------------------------------
`include "ch/010_d_pre.vh"                              // D(1): キューから発行候補I0/I1を取り出す / D(1): issue candidates I0/I1 from the queues
`include "ch/015_d_i01.vh"                              // D(2): I0/I1のフィールド解読 / D(2): fields of I0/I1
`include "ch/020_d_iss.vh"                              // D(3): 形式と使う資源の判定 / D(3): format and resources used
`include "ch/030_d_sec.vh"                              // D(4): 同時発行の判定とパイプへの振り分け / D(4): dual-issue decision and pipe sorting
`include "ch/035_d_ixx.vh"                              // D(5): ILS/IEX/IJBのフィールド / D(5): fields of ILS/IEX/IJB
`include "ch/040_d_bra.vh"                              // D(6): 分岐の番地・種類・予測 / D(6): branch address, kind, prediction
`include "ch/045_g_ram.vh"                              // GR/Memへのアクセス (回路は外のモジュール) / GR/Mem access (circuit lives in outer modules)
`include "ch/050_op_lb1.vh"                             // Sユニットの出力と取り消し信号 / S-unit outputs and cancel signals
`include "ch/060_g_srq.vh"                              // 有効フラグとSユニットへの要求 / valid flags and S-unit requests
`include "ch/070_g_ilk.vh"                              // インタロック (停止の連鎖) / interlocks (stall chain)
`include "ch/080_w_act.vh"                              // W: PC/PSW/システムレジスタの更新 / W: PC / PSW / system register updates
`include "ch/090_e_act.vh"                              // E: LSパイプのALUとWのタグ / E: LS-pipe ALU and W tags
`include "ch/100_b_dat.vh"                              // B: E用データの選択とバイパス / B: data selection and bypass for E
`include "ch/110_b_act.vh"                              // B→Eのパイプラインレジスタ / B -> E pipeline register
`include "ch/120_a_dat.vh"                              // A: EXUとEAG (アドレス加算器) / A: EXU and EAG (address adder)
`include "ch/130_a_act.vh"                              // A→Bのパイプラインレジスタ / A -> B pipeline register
`include "ch/140_d_dat.vh"                              // D→Aのオペランドとバイパス網 / D -> A operands and the bypass network
`include "ch/150_d_act.vh"                              // D→Aのタグ / D -> A tags
`include "ch/160_op_lb2.vh"                             // Sユニットの次状態 (OP-WAIT/OP-B) / S-unit next state (OP-WAIT / OP-B)
`include "ch/170_if_req.vh"                             // 命令フェッチ要求 / instruction fetch request
`include "ch/180_if_lbs.vh"                             // 命令データの受け取り / instruction data receive
`include "ch/190_if_stm.vh"                             // フェッチ状態とNIPの更新 / fetch state and NIP update
`include "ch/200_if_iwq.vh"                             // 命令キューのシフトと取り込み / instruction queue shift and fill
`include "ch/210_g_bc.vh"                               // 条件分岐の解決状態 / conditional-branch resolution state

// ---------------------------------------------------------------------
//  FF の更新 (C 版の「サイクルの最後に X = X_NEW」に相当)
//  FF update (equivalent of "X = X_NEW at the end of the cycle" in the C version)
// ---------------------------------------------------------------------
// 【解説】すべての FF をここで一斉に更新する。各 X_NEW は ch/*.vh で
//         CHDL の 'X := 式' から作った D 入力。
//         同期リセット: rst=1 の間のクロックで 0 (PC は RESET_PC) にする。
//         (PC のリセット値が定数ではなく入力 RESET_PC なので、非同期リセットに
//          すると FPGA ではラッチで代用されてしまう。そのため同期リセットにしている)
//
// [Note] All FFs are updated here at once. Each X_NEW is the D input made in ch/*.vh
//        from the CHDL 'X := expr'.
//        Synchronous reset: on clocks while rst=1, set to 0 (PC to RESET_PC).
//        (The PC reset value is the input RESET_PC, not a constant; with an asynchronous
//         reset an FPGA would substitute a latch, so the reset is synchronous.)
//
// 【ネットリスト解説】この always ブロックから作られる回路
//   ・各行が FF 1 本 (多ビットならビット数ぶん) になる。Xilinx 7 系では
//     「リセット値 0 の同期リセット付き FF」= FDRE で、rst は FF の R 端子に、
//     X_NEW は D 端子につながる (例: 合成結果の START_TRIGGER_BAR_reg は
//     .D(START_TRIGGER_BAR_NEW), .R(rst))。
//   ・X_NEW が「保持 (X のまま)」の場合を含む式 (例: TBR_NEW = 条件 ? W_WDT2 : TBR)
//     は、合成ツールが「保持」の分岐を FF の CE (クロックイネーブル) 端子に
//     置き換えることが多い。その分 LUT が減る。
//   ・PC だけはリセット値が入力 RESET_PC なので R 端子は使えない。合成結果では
//     PC_reg の R は 1'b0 に固定され、D 入力の前に「rst なら RESET_PC」を選ぶ
//     LUT が 1 段入る (PC[i]_i_1 が aresetn と RESET_PC[i] を入力に持つ)。
//   ・なお iverilog のシミュレーションでは、always @(posedge clk) の右辺は
//     このクロックの直前の値で評価されるので、C 版の「全 X_NEW を計算してから
//     一斉に X = X_NEW」と同じ意味になる。
//
// [Netlist notes] The circuit made from this always block
//   - Each line becomes one FF (as many as the number of bits). On Xilinx 7 series this is
//     an FF with synchronous reset to 0 = FDRE: rst goes to the FF's R pin and X_NEW to its
//     D pin (e.g. START_TRIGGER_BAR_reg in the synthesis result has
//     .D(START_TRIGGER_BAR_NEW), .R(rst)).
//   - When X_NEW contains a "hold (keep X)" case (e.g. TBR_NEW = cond ? W_WDT2 : TBR),
//     synthesis often replaces the hold branch with the FF's CE (clock enable) pin,
//     which saves LUTs.
//   - Only the PC has the input RESET_PC as its reset value, so the R pin cannot be used.
//     In the synthesis result the R of PC_reg is tied to 1'b0, and one LUT level choosing
//     "RESET_PC during rst" is added before the D input (PC[i]_i_1 has aresetn and
//     RESET_PC[i] as inputs).
//   - In the iverilog simulation the right-hand sides in always @(posedge clk) are evaluated
//     with the values just before this clock edge, which means the same as the C version's
//     "compute every X_NEW, then do X = X_NEW all at once".
always @(posedge clk) begin                             // 全FFの更新: 各行がFF (多ビットならビット数ぶん) / update of every FF: each line is FFs (one per bit)
  if (rst) begin                                        // 同期リセット: rstをFDREのR端子に (PCだけはDの前のMUX) / synchronous reset: rst to FDRE R (PC uses a mux before D)
    TBR                     <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    CMPR                    <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    SVR0                    <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    SVR1                    <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    PSW_CC                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    PSW_USER                <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    PSW_TYPE                <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    PC                      <= RESET_PC;                // PCのリセット値は入力ポートなのでR端子は使えず, D=rst?RESET_PC:PC_NEW のMUX / PC's reset value is a port, so R is unused: D = rst ? RESET_PC : PC_NEW
    XPSW                    <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    XPC                     <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    XLA                     <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    START_TRIGGER_BAR       <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_WAD1                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_WAD2                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_WDT1                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_WDT2                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_TGT                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_IS_SUPERSCALAR        <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_LATTER_IS_JB          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_FIRST_IS_EX           <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_CC                    <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_WE1                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_WE2                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_SETCC                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_COMPLETE              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_PRIVCODE              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_EX_INTCODE            <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_LS_INTCODE            <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    W_JB_V                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    STB_V                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    STB_AD                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    STB_DT                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_OPS_DT             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_OPCLH_LCH             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_INTCODE            <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_LD_DT              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_V                     <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_JB_IS_BC              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_JB_SUBJECT_TO_BC      <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_JB_V                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_SOLVING_BC         <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_LD_V               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_ST_V               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_WE1                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_WE2                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_SETCC              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_EX_SETCC              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_EX_INTCODE            <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_PRIVCODE              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_LOG_AD             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_WAD1                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_WAD2                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_OPS_IS_GR          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_RADS               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_EX_RES                <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_EX_CC                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_TGT                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_IS_SUPERSCALAR        <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LATTER_IS_JB          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_FIRST_IS_EX           <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    E_LS_OPCODE             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_V                     <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_JB_IS_BC              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_JB_SUBJECT_TO_BC      <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_JB_V                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_LS_SOLVING_BC         <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_INTCODE               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_PRIVCODE              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_LS_LD_V               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_LS_ST_V               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_WE1                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_WE2                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_LS_SETCC              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_EX_SETCC              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_LS_LOG_AD             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_WAD1                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_WAD2                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_LS_OPS_IS_GR          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_LS_RADS               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_LS_OPCODE             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_IS_SUPERSCALAR        <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_LATTER_IS_JB          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_FIRST_IS_EX           <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_EX_RAD2               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_TGT                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_EX_RES                <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    B_EX_CC                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_OPB_IS_GR          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_EX_OP1_IS_GR          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_EX_OP2_IS_GR          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_OPB_DT             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_EX_OP1_DT             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_EX_OP2_DT             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_RADB               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_EX_RAD1               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_EX_RAD2               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_DISP                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_V                     <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_JB_IS_BC              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_JB_SUBJECT_TO_BC      <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_JB_V                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_SOLVING_BC         <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_EX_SOLVING_BC         <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_INTCODE               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_PRIVCODE              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_LD_V               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_WE1                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_ST_V               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_OPS_IS_GR          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_SETCC              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_EX_SETCC              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_WE2                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_WAD1                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_RADS               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_WAD2                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LS_OPCODE             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_IS_SUPERSCALAR        <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_FIRST_IS_EX           <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_LATTER_IS_JB          <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_TGT                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_EX_OPCODE             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    A_SET_EAG_TO_TGT        <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_WAIT_V               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_WAIT_OPC             <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_WAIT_WE              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_WAIT_AD              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_WAIT_DT              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_WAIT_SUBJECT_TO_BC   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_B_V                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_B_OPC                <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    LBS_WE                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    LBS_AD                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    LBS_DT                  <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_B_SUBJECT_TO_BC      <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    OP_B_NEW                <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IB_V                    <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IB_AD                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IB_ID                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    CUR_IWQ_ID              <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    NIP_B                   <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    NIP_A_REG               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    D_IF_AD_A               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    D_IF_AD_B               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_A_0                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_A_1                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_A_2                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_A_3                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_A_V01               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_A_V23               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_B_0                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_B_1                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_B_2                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_B_3                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_B_V01               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_B_V23               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_A_4                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_A_5                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_B_4                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_B_5                 <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_A_V45               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    IWQ_B_V45               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    G_BC_PENDING            <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    G_BC_JUST_SOLVED        <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    G_BC_JUST_TAKEN         <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    G_BC_TKN_PREDICTED      <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
    G_BC_MASK               <= 0;                       // 同期リセットで0: FDREのR端子にrstがつながる / sync reset to 0: rst goes to the R pin of the FDRE
  end else begin                                        // 通常動作: 各FFにch/*.vhで作ったD入力を入れる / normal operation: each FF loads its D input from ch/*.vh
    TBR                     <= TBR_NEW;                 // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    CMPR                    <= CMPR_NEW;                // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    SVR0                    <= SVR0_NEW;                // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    SVR1                    <= SVR1_NEW;                // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    PSW_CC                  <= PSW_CC_NEW;              // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    PSW_USER                <= PSW_USER_NEW;            // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    PSW_TYPE                <= PSW_TYPE_NEW;            // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    PC                      <= PC_NEW;                  // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    XPSW                    <= XPSW_NEW;                // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    XPC                     <= XPC_NEW;                 // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    XLA                     <= XLA_NEW;                 // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    START_TRIGGER_BAR       <= START_TRIGGER_BAR_NEW;   // 080で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 080 (the hold branch becomes CE)
    W_WAD1                  <= W_WAD1_NEW;              // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_WAD2                  <= W_WAD2_NEW;              // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_WDT1                  <= W_WDT1_NEW;              // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_WDT2                  <= W_WDT2_NEW;              // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_TGT                   <= W_TGT_NEW;               // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_IS_SUPERSCALAR        <= W_IS_SUPERSCALAR_NEW;    // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_LATTER_IS_JB          <= W_LATTER_IS_JB_NEW;      // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_FIRST_IS_EX           <= W_FIRST_IS_EX_NEW;       // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_CC                    <= W_CC_NEW;                // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_WE1                   <= W_WE1_NEW;               // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_WE2                   <= W_WE2_NEW;               // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_SETCC                 <= W_SETCC_NEW;             // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_COMPLETE              <= W_COMPLETE_NEW;          // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_PRIVCODE              <= W_PRIVCODE_NEW;          // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_EX_INTCODE            <= W_EX_INTCODE_NEW;        // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_LS_INTCODE            <= W_LS_INTCODE_NEW;        // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    W_JB_V                  <= W_JB_V_NEW;              // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    STB_V                   <= STB_V_NEW;               // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    STB_AD                  <= STB_AD_NEW;              // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    STB_DT                  <= STB_DT_NEW;              // 090で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 090 (the hold branch becomes CE)
    E_LS_OPS_DT             <= E_LS_OPS_DT_NEW;         // 100で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 100 (the hold branch becomes CE)
    E_OPCLH_LCH             <= E_OPCLH_LCH_NEW;         // 100で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 100 (the hold branch becomes CE)
    E_LS_INTCODE            <= E_LS_INTCODE_NEW;        // 100で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 100 (the hold branch becomes CE)
    E_LS_LD_DT              <= E_LS_LD_DT_NEW;          // 100で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 100 (the hold branch becomes CE)
    E_V                     <= E_V_NEW;                 // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_JB_IS_BC              <= E_JB_IS_BC_NEW;          // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_JB_SUBJECT_TO_BC      <= E_JB_SUBJECT_TO_BC_NEW;  // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_JB_V                  <= E_JB_V_NEW;              // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_LS_SOLVING_BC         <= E_LS_SOLVING_BC_NEW;     // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_LS_LD_V               <= E_LS_LD_V_NEW;           // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_LS_ST_V               <= E_LS_ST_V_NEW;           // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_WE1                   <= E_WE1_NEW;               // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_WE2                   <= E_WE2_NEW;               // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_LS_SETCC              <= E_LS_SETCC_NEW;          // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_EX_SETCC              <= E_EX_SETCC_NEW;          // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_EX_INTCODE            <= E_EX_INTCODE_NEW;        // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_PRIVCODE              <= E_PRIVCODE_NEW;          // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_LS_LOG_AD             <= E_LS_LOG_AD_NEW;         // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_WAD1                  <= E_WAD1_NEW;              // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_WAD2                  <= E_WAD2_NEW;              // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_LS_OPS_IS_GR          <= E_LS_OPS_IS_GR_NEW;      // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_LS_RADS               <= E_LS_RADS_NEW;           // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_EX_RES                <= E_EX_RES_NEW;            // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_EX_CC                 <= E_EX_CC_NEW;             // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_TGT                   <= E_TGT_NEW;               // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_IS_SUPERSCALAR        <= E_IS_SUPERSCALAR_NEW;    // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_LATTER_IS_JB          <= E_LATTER_IS_JB_NEW;      // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_FIRST_IS_EX           <= E_FIRST_IS_EX_NEW;       // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    E_LS_OPCODE             <= E_LS_OPCODE_NEW;         // 110で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 110 (the hold branch becomes CE)
    B_V                     <= B_V_NEW;                 // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_JB_IS_BC              <= B_JB_IS_BC_NEW;          // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_JB_SUBJECT_TO_BC      <= B_JB_SUBJECT_TO_BC_NEW;  // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_JB_V                  <= B_JB_V_NEW;              // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_LS_SOLVING_BC         <= B_LS_SOLVING_BC_NEW;     // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_INTCODE               <= B_INTCODE_NEW;           // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_PRIVCODE              <= B_PRIVCODE_NEW;          // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_LS_LD_V               <= B_LS_LD_V_NEW;           // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_LS_ST_V               <= B_LS_ST_V_NEW;           // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_WE1                   <= B_WE1_NEW;               // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_WE2                   <= B_WE2_NEW;               // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_LS_SETCC              <= B_LS_SETCC_NEW;          // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_EX_SETCC              <= B_EX_SETCC_NEW;          // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_LS_LOG_AD             <= B_LS_LOG_AD_NEW;         // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_WAD1                  <= B_WAD1_NEW;              // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_WAD2                  <= B_WAD2_NEW;              // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_LS_OPS_IS_GR          <= B_LS_OPS_IS_GR_NEW;      // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_LS_RADS               <= B_LS_RADS_NEW;           // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_LS_OPCODE             <= B_LS_OPCODE_NEW;         // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_IS_SUPERSCALAR        <= B_IS_SUPERSCALAR_NEW;    // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_LATTER_IS_JB          <= B_LATTER_IS_JB_NEW;      // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_FIRST_IS_EX           <= B_FIRST_IS_EX_NEW;       // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_EX_RAD2               <= B_EX_RAD2_NEW;           // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_TGT                   <= B_TGT_NEW;               // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_EX_RES                <= B_EX_RES_NEW;            // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    B_EX_CC                 <= B_EX_CC_NEW;             // 130で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 130 (the hold branch becomes CE)
    A_LS_OPB_IS_GR          <= A_LS_OPB_IS_GR_NEW;      // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_EX_OP1_IS_GR          <= A_EX_OP1_IS_GR_NEW;      // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_EX_OP2_IS_GR          <= A_EX_OP2_IS_GR_NEW;      // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_LS_OPB_DT             <= A_LS_OPB_DT_NEW;         // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_EX_OP1_DT             <= A_EX_OP1_DT_NEW;         // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_EX_OP2_DT             <= A_EX_OP2_DT_NEW;         // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_LS_RADB               <= A_LS_RADB_NEW;           // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_EX_RAD1               <= A_EX_RAD1_NEW;           // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_EX_RAD2               <= A_EX_RAD2_NEW;           // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_DISP                  <= A_DISP_NEW;              // 140で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 140 (the hold branch becomes CE)
    A_V                     <= A_V_NEW;                 // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_JB_IS_BC              <= A_JB_IS_BC_NEW;          // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_JB_SUBJECT_TO_BC      <= A_JB_SUBJECT_TO_BC_NEW;  // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_JB_V                  <= A_JB_V_NEW;              // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_LS_SOLVING_BC         <= A_LS_SOLVING_BC_NEW;     // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_EX_SOLVING_BC         <= A_EX_SOLVING_BC_NEW;     // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_INTCODE               <= A_INTCODE_NEW;           // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_PRIVCODE              <= A_PRIVCODE_NEW;          // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_LS_LD_V               <= A_LS_LD_V_NEW;           // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_WE1                   <= A_WE1_NEW;               // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_LS_ST_V               <= A_LS_ST_V_NEW;           // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_LS_OPS_IS_GR          <= A_LS_OPS_IS_GR_NEW;      // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_LS_SETCC              <= A_LS_SETCC_NEW;          // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_EX_SETCC              <= A_EX_SETCC_NEW;          // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_WE2                   <= A_WE2_NEW;               // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_WAD1                  <= A_WAD1_NEW;              // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_LS_RADS               <= A_LS_RADS_NEW;           // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_WAD2                  <= A_WAD2_NEW;              // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_LS_OPCODE             <= A_LS_OPCODE_NEW;         // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_IS_SUPERSCALAR        <= A_IS_SUPERSCALAR_NEW;    // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_FIRST_IS_EX           <= A_FIRST_IS_EX_NEW;       // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_LATTER_IS_JB          <= A_LATTER_IS_JB_NEW;      // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_TGT                   <= A_TGT_NEW;               // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_EX_OPCODE             <= A_EX_OPCODE_NEW;         // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    A_SET_EAG_TO_TGT        <= A_SET_EAG_TO_TGT_NEW;    // 150で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 150 (the hold branch becomes CE)
    OP_WAIT_V               <= OP_WAIT_V_NEW;           // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    OP_WAIT_OPC             <= OP_WAIT_OPC_NEW;         // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    OP_WAIT_WE              <= OP_WAIT_WE_NEW;          // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    OP_WAIT_AD              <= OP_WAIT_AD_NEW;          // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    OP_WAIT_DT              <= OP_WAIT_DT_NEW;          // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    OP_WAIT_SUBJECT_TO_BC   <= OP_WAIT_SUBJECT_TO_BC_NEW; // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    OP_B_V                  <= OP_B_V_NEW;              // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    OP_B_OPC                <= OP_B_OPC_NEW;            // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    LBS_WE                  <= LBS_WE_NEW;              // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    LBS_AD                  <= LBS_AD_NEW;              // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    LBS_DT                  <= LBS_DT_NEW;              // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    OP_B_SUBJECT_TO_BC      <= OP_B_SUBJECT_TO_BC_NEW;  // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    OP_B_NEW                <= OP_B_NEW_NEW;            // 160で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 160 (the hold branch becomes CE)
    IB_V                    <= IB_V_NEW;                // 190で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 190 (the hold branch becomes CE)
    IB_AD                   <= IB_AD_NEW;               // 190で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 190 (the hold branch becomes CE)
    IB_ID                   <= IB_ID_NEW;               // 190で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 190 (the hold branch becomes CE)
    CUR_IWQ_ID              <= CUR_IWQ_ID_NEW;          // 190で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 190 (the hold branch becomes CE)
    NIP_B                   <= NIP_B_NEW;               // 190で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 190 (the hold branch becomes CE)
    NIP_A_REG               <= NIP_A_REG_NEW;           // 190で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 190 (the hold branch becomes CE)
    D_IF_AD_A               <= D_IF_AD_A_NEW;           // 190で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 190 (the hold branch becomes CE)
    D_IF_AD_B               <= D_IF_AD_B_NEW;           // 190で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 190 (the hold branch becomes CE)
    IWQ_A_0                 <= IWQ_A_0_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_A_1                 <= IWQ_A_1_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_A_2                 <= IWQ_A_2_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_A_3                 <= IWQ_A_3_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_A_V01               <= IWQ_A_V01_NEW;           // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_A_V23               <= IWQ_A_V23_NEW;           // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_B_0                 <= IWQ_B_0_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_B_1                 <= IWQ_B_1_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_B_2                 <= IWQ_B_2_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_B_3                 <= IWQ_B_3_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_B_V01               <= IWQ_B_V01_NEW;           // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_B_V23               <= IWQ_B_V23_NEW;           // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_A_4                 <= IWQ_A_4_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_A_5                 <= IWQ_A_5_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_B_4                 <= IWQ_B_4_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_B_5                 <= IWQ_B_5_NEW;             // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_A_V45               <= IWQ_A_V45_NEW;           // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    IWQ_B_V45               <= IWQ_B_V45_NEW;           // 200で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 200 (the hold branch becomes CE)
    G_BC_PENDING            <= G_BC_PENDING_NEW;        // 210で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 210 (the hold branch becomes CE)
    G_BC_JUST_SOLVED        <= G_BC_JUST_SOLVED_NEW;    // 210で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 210 (the hold branch becomes CE)
    G_BC_JUST_TAKEN         <= G_BC_JUST_TAKEN_NEW;     // 210で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 210 (the hold branch becomes CE)
    G_BC_TKN_PREDICTED      <= G_BC_TKN_PREDICTED_NEW;  // 210で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 210 (the hold branch becomes CE)
    G_BC_MASK               <= G_BC_MASK_NEW;           // 210で作ったD入力を取り込む (保持の分岐は合成でCEになる) / latch the D input made in 210 (the hold branch becomes CE)
  end                                                   // else の終わり / end of else
end                                                     // always の終わり / end of always

endmodule                                               // モジュールの終わり / end of module
