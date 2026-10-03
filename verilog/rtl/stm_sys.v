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
    .IB_AD            (ib_ad),
    .MEM_DT_IF_H      (mem_dt_if_h),
    .MEM_DT_IF_L      (mem_dt_if_l),
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
