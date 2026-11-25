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
module stm_sys #(
  parameter MEM_AW   = 10,
  parameter INIT_HEX = ""
) (
  input         clk,
  input         rst,
  input  [31:0] RESET_PC,
  input         RANDOM_FOR_OPCLH,
  input         RANDOM_FOR_IFRDY,
  input         RANDOM_FOR_IFCLH,
  output [31:0] PC
);
  wire [3:0]  dd_rad1, dd_rad2, dd_radb, b_ls_rads;
  wire [31:0] gr_dt_1, gr_dt_2, gr_dt_b, gr_dt_s;
  wire        w_we1, w_we2;
  wire [3:0]  w_wad1, w_wad2;
  wire [31:0] w_wdt1, w_wdt2;
  wire        lbs_we;
  wire [31:0] lbs_ad, lbs_dt, ib_ad;
  wire [31:0] mem_dt_op, mem_dt_if_h, mem_dt_if_l;

  stm_cntl u_cntl (
    .clk              (clk),
    .rst              (rst),
    .RESET_PC         (RESET_PC),
    .RANDOM_FOR_OPCLH (RANDOM_FOR_OPCLH),
    .RANDOM_FOR_IFRDY (RANDOM_FOR_IFRDY),
    .RANDOM_FOR_IFCLH (RANDOM_FOR_IFCLH),
    .DD_RAD1          (dd_rad1),
    .DD_RAD2          (dd_rad2),
    .DD_RADB          (dd_radb),
    .B_LS_RADS        (b_ls_rads),
    .GR_DT_1          (gr_dt_1),
    .GR_DT_2          (gr_dt_2),
    .GR_DT_B          (gr_dt_b),
    .GR_DT_S          (gr_dt_s),
    .W_WE1            (w_we1),
    .W_WE2            (w_we2),
    .W_WAD1           (w_wad1),
    .W_WAD2           (w_wad2),
    .W_WDT1           (w_wdt1),
    .W_WDT2           (w_wdt2),
    .LBS_WE           (lbs_we),
    .LBS_AD           (lbs_ad),
    .LBS_DT           (lbs_dt),
    .MEM_DT_OP        (mem_dt_op),
    .MEM_OP_ERR       (1'b0),         // 外部バス (EXT_BUS=1) 用。ここでは未使用
    .IB_AD            (ib_ad),
    .MEM_DT_IF_H      (mem_dt_if_h),
    .MEM_DT_IF_L      (mem_dt_if_l),
    .IB_VALID         (),             // 外部バス (EXT_BUS=1) 用。ここでは未使用
    .IB_AD_NXT        (),
    .OP_B_NEW         (),
    .OP_B_BUSREQ      (),
    .PC               (PC)
  );

  stm_regfile u_reg (
    .clk  (clk),
    .we1  (w_we1),   .we2  (w_we2),
    .wad1 (w_wad1),  .wad2 (w_wad2),
    .wdt1 (w_wdt1),  .wdt2 (w_wdt2),
    .rad1 (dd_rad1), .rad2 (dd_rad2), .radb (dd_radb), .rads (b_ls_rads),
    .rdt1 (gr_dt_1), .rdt2 (gr_dt_2), .rdtb (gr_dt_b), .rdts (gr_dt_s)
  );

  stm_memory #(.AW(MEM_AW), .INIT_HEX(INIT_HEX)) u_mem (
    .clk   (clk),
    .we    (lbs_we),
    .opad  (lbs_ad),
    .stdt  (lbs_dt),
    .ifad  (ib_ad),
    .opdt  (mem_dt_op),
    .ifdth (mem_dt_if_h),
    .ifdtl (mem_dt_if_l)
  );
endmodule
