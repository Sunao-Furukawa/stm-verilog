// =====================================================================
//  stm_sys.v  -  システム全体 (VHDL 版 vh/behave/sys.vst に相当)
//
//     +-----------+   DD_RAD*,B_LS_RADS,W_*   +-------------+
//     |           | ------------------------> |             |
//     | stm_cntl  | <------------------------ | stm_regfile |
//     |  (CPU)    |        GR_DT_*            +-------------+
//     |           |   LBS_*, IB_AD            +-------------+
//     |           | ------------------------> |             |
//     |           | <------------------------ | stm_memory  |
//     +-----------+   MEM_DT_*                +-------------+
//
//  VHDL 版で外に出していた加算器や EXU は stm_cntl の中に入れてある。
//
//  The whole system (equivalent of vh/behave/sys.vst of the VHDL version).
//  The adders and EXU that the VHDL version had outside are inside stm_cntl.
//
// 【ネットリスト解説】このモジュールは配線だけ (ゲートも FF も無い)。
//   各 wire は 1 本のネットで、作り手 (ドライバ) は 1 つ、使い手は 1 つ以上:
//
//     ネット          作り手                        使い手            意味
//     dd_rad1/2/b     u_cntl (030, 組合せ)          u_reg rad1/2/b    D サイクルで読むレジスタ番号
//     b_ls_rads       u_cntl (130 の FF)            u_reg rads        B サイクルで読むレジスタ番号
//     gr_dt_1/2/b     u_reg (組合せ)                u_cntl (140)      D サイクルの読み出しデータ
//     gr_dt_s         u_reg (組合せ)                u_cntl (100)      ストアデータ / EX-RM のオペランド
//     w_we1/2, w_wad1/2, w_wdt1/2
//                     u_cntl (090 の FF)            u_reg             W サイクルの書き込み (1=LS, 2=EX)
//     lbs_we/ad/dt    u_cntl (160 の FF)            u_mem             オペランドの読み書き
//     mem_dt_op       u_mem (組合せ)                u_cntl (050)      オペランドの読み出しデータ
//     ib_ad           u_cntl (190 の FF)            u_mem             命令フェッチの番地 (8 バイト単位)
//     mem_dt_if_h/l   u_mem (組合せ)                u_cntl (180)      フェッチした 2 命令
//
//   u_cntl → u_reg → u_cntl, u_cntl → u_mem → u_cntl と、モジュールをまたいで
//   組合せの経路が往復するが、出発点は必ず u_cntl の FF なのでループにはならない。
//   (dd_rad* だけは u_cntl の中の組合せ回路から出ているので、IWQ の FF から
//    レジスタファイルを通って A_*_DT の FF まで 1 サイクルの長い経路になる)
//   RANDOM_FOR_* は tb_stm.v から直接入り、キャッシュのミスを模擬する。
//   常に 1 なら「メモリは同じサイクルに応答する」理想的なメモリになる。
//
// [Netlist notes] This module is wiring only (no gates, no FFs).
//   Each wire is one net with exactly one driver and one or more loads:
//
//     net             driver                        load              meaning
//     dd_rad1/2/b     u_cntl (030, combinational)   u_reg rad1/2/b    register numbers read in the D cycle
//     b_ls_rads       u_cntl (FF in 130)            u_reg rads        register number read in the B cycle
//     gr_dt_1/2/b     u_reg (combinational)         u_cntl (140)      read data for the D cycle
//     gr_dt_s         u_reg (combinational)         u_cntl (100)      store data / operand of EX-RM
//     w_we1/2, w_wad1/2, w_wdt1/2
//                     u_cntl (FFs in 090)           u_reg             W-cycle writes (1=LS, 2=EX)
//     lbs_we/ad/dt    u_cntl (FFs in 160)           u_mem             operand read / write
//     mem_dt_op       u_mem (combinational)         u_cntl (050)      operand read data
//     ib_ad           u_cntl (FFs in 190)           u_mem             fetch address (8-byte unit)
//     mem_dt_if_h/l   u_mem (combinational)         u_cntl (180)      the 2 fetched instructions
//
//   Combinational paths go back and forth across modules, u_cntl -> u_reg -> u_cntl and
//   u_cntl -> u_mem -> u_cntl, but they always start at FFs of u_cntl, so there is no loop.
//   (Only dd_rad* come from combinational logic inside u_cntl, which makes a long one-cycle
//    path from the IWQ FFs through the register file to the A_*_DT FFs.)
//   RANDOM_FOR_* come straight from tb_stm.v and simulate cache misses.
//   If they are always 1, the memory is an ideal one that "answers in the same cycle".
// =====================================================================
module stm_sys #(                                       // シミュレーション用のシステム: CPU+レジスタファイル+メモリ (配線だけ) / simulation system: CPU + register file + memory (wiring only)
  parameter MEM_AW   = 10,                              // メモリの語番地幅 (10 = 1024語 = 4KB) / memory word-address width (10 = 1024 words = 4 KB)
  parameter INIT_HEX = ""                               // メモリの初期化ファイル (tbから+HEXで渡す) / memory init file (passed from the tb as +HEX)
) (                                                     // パラメータの終わり, ポートの始まり / end of parameters, start of ports
  input         clk,                                    // クロック: 全FFへ / clock: to every FF
  input         rst,                                    // 同期リセット (stm_cntlだけが使う) / synchronous reset (used only by stm_cntl)
  input  [31:0] RESET_PC,                               // リセット後の開始番地 / start address after reset
  input         RANDOM_FOR_OPCLH,                       // オペランドキャッシュのヒット (tbの乱数でミスを模擬) / operand-cache hit (tb random = miss simulation)
  input         RANDOM_FOR_IFRDY,                       // フェッチ要求の受け付け可 (乱数) / fetch request accepted (random)
  input         RANDOM_FOR_IFCLH,                       // 命令データが届いた (乱数) / fetch data arrived (random)
  output [31:0] PC                                      // 完了した命令のPC (080のFF) → tbが停止判定に使う / PC of completed insns (FF in 080) -> tb uses it to detect the stop
);                                                      // ポート宣言の終わり / end of ports
  wire [3:0]  dd_rad1, dd_rad2, dd_radb, b_ls_rads;     // レジスタ読み出し番号のネット (u_cntl→u_reg) / register read-number nets (u_cntl -> u_reg)
  wire [31:0] gr_dt_1, gr_dt_2, gr_dt_b, gr_dt_s;       // レジスタ読み出しデータのネット (u_reg→u_cntl) / register read-data nets (u_reg -> u_cntl)
  wire        w_we1, w_we2;                             // 書き込み許可のネット (090のFF→u_reg) / write-enable nets (FFs in 090 -> u_reg)
  wire [3:0]  w_wad1, w_wad2;                           // 書き込み番号のネット / write-number nets
  wire [31:0] w_wdt1, w_wdt2;                           // 書き込みデータのネット / write-data nets
  wire        lbs_we;                                   // メモリ書き込み許可のネット (160のFF→u_mem) / memory write-enable net (FF in 160 -> u_mem)
  wire [31:0] lbs_ad, lbs_dt, ib_ad;                    // メモリ番地/データとフェッチ番地のネット / memory address / data and fetch-address nets
  wire [31:0] mem_dt_op, mem_dt_if_h, mem_dt_if_l;      // メモリ読み出しデータのネット (u_mem→u_cntl) / memory read-data nets (u_mem -> u_cntl)

  stm_cntl u_cntl (                                     // CPU本体のインスタンス (EXT_BUSは既定の0: 理想メモリ用) / CPU core instance (EXT_BUS default 0: for the ideal memory)
    .clk              (clk),                            // クロック / clock
    .rst              (rst),                            // リセット / reset
    .RESET_PC         (RESET_PC),                       // 開始番地 → PCのFFのリセット値 / start address -> reset value of the PC FFs
    .RANDOM_FOR_OPCLH (RANDOM_FOR_OPCLH),               // キャッシュヒット信号を直結 / cache-hit signal wired through
    .RANDOM_FOR_IFRDY (RANDOM_FOR_IFRDY),               // フェッチ受け付け信号を直結 / fetch-ready signal wired through
    .RANDOM_FOR_IFCLH (RANDOM_FOR_IFCLH),               // フェッチ到着信号を直結 / fetch-arrival signal wired through
    .DD_RAD1          (dd_rad1),                        // D: R1の番号 (組合せ出力) / D: R1 number (combinational output)
    .DD_RAD2          (dd_rad2),                        // D: R2の番号 / D: R2 number
    .DD_RADB          (dd_radb),                        // D: RBの番号 / D: RB number
    .B_LS_RADS        (b_ls_rads),                      // B: RSの番号 (FF出力) / B: RS number (FF output)
    .GR_DT_1          (gr_dt_1),                        // R1のデータ ← u_reg / R1 data <- u_reg
    .GR_DT_2          (gr_dt_2),                        // R2のデータ / R2 data
    .GR_DT_B          (gr_dt_b),                        // RBのデータ / RB data
    .GR_DT_S          (gr_dt_s),                        // RSのデータ / RS data
    .W_WE1            (w_we1),                          // W: LS側書き込み許可 / W: LS write enable
    .W_WE2            (w_we2),                          // W: EX側書き込み許可 / W: EX write enable
    .W_WAD1           (w_wad1),                         // W: LS側書き込み番号 / W: LS write number
    .W_WAD2           (w_wad2),                         // W: EX側書き込み番号 / W: EX write number
    .W_WDT1           (w_wdt1),                         // W: LS側書き込みデータ / W: LS write data
    .W_WDT2           (w_wdt2),                         // W: EX側書き込みデータ / W: EX write data
    .LBS_WE           (lbs_we),                         // メモリ書き込み許可 / memory write enable
    .LBS_AD           (lbs_ad),                         // オペランドの番地 / operand address
    .LBS_DT           (lbs_dt),                         // 書き込みデータ / write data
    .MEM_DT_OP        (mem_dt_op),                      // オペランドの読み出しデータ ← u_mem / operand read data <- u_mem
    .MEM_OP_ERR       (1'b0),         // 外部バス (EXT_BUS=1) 用。ここでは未使用
                                      // for the external bus (EXT_BUS=1); unused here
    .IB_AD            (ib_ad),                          // 命令フェッチの番地 / fetch address
    .MEM_DT_IF_H      (mem_dt_if_h),                    // フェッチした1語目 / first fetched word
    .MEM_DT_IF_L      (mem_dt_if_l),                    // フェッチした2語目 / second fetched word
    .IB_VALID         (),             // 外部バス (EXT_BUS=1) 用。ここでは未使用
                                      // for the external bus (EXT_BUS=1); unused here
    .IB_AD_NXT        (),                               // 未接続: icache用の出力 (未使用ネットは合成で消える) / unconnected: icache output (unused, removed)
    .OP_B_NEW         (),                               // 未接続: AXIマスタ用 / unconnected: for the AXI master
    .OP_B_BUSREQ      (),                               // 未接続: AXIマスタ用 / unconnected: for the AXI master
    .PC               (PC)                              // PCを外へ / PC out
  );                                                    // u_cntlの終わり / end of u_cntl

  stm_regfile u_reg (                                   // レジスタファイルのインスタンス / register file instance
    .clk  (clk),                                        // クロック / clock
    .we1  (w_we1),   .we2  (w_we2),                     // 書き込み許可2本 / two write enables
    .wad1 (w_wad1),  .wad2 (w_wad2),                    // 書き込み番号2本 / two write numbers
    .wdt1 (w_wdt1),  .wdt2 (w_wdt2),                    // 書き込みデータ2本 / two write data
    .rad1 (dd_rad1), .rad2 (dd_rad2), .radb (dd_radb), .rads (b_ls_rads), // 読み出し番号4本 / four read numbers
    .rdt1 (gr_dt_1), .rdt2 (gr_dt_2), .rdtb (gr_dt_b), .rdts (gr_dt_s) // 読み出しデータ4本 / four read data
  );                                                    // u_regの終わり / end of u_reg

  stm_memory #(.AW(MEM_AW), .INIT_HEX(INIT_HEX)) u_mem ( // メモリのインスタンス (パラメータを渡す) / memory instance (parameters passed down)
    .clk   (clk),                                       // クロック / clock
    .we    (lbs_we),                                    // 書き込み許可 / write enable
    .opad  (lbs_ad),                                    // オペランドの番地 / operand address
    .stdt  (lbs_dt),                                    // 書き込みデータ / write data
    .ifad  (ib_ad),                                     // フェッチ番地 / fetch address
    .opdt  (mem_dt_op),                                 // オペランドの読み出しデータ / operand read data
    .ifdth (mem_dt_if_h),                               // フェッチの1語目 / first fetch word
    .ifdtl (mem_dt_if_l)                                // フェッチの2語目 / second fetch word
  );                                                    // u_memの終わり / end of u_mem
endmodule                                               // モジュールの終わり / end of module
