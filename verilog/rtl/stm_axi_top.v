// =====================================================================
//  stm_axi_top.v  -  AXI4 マスタ・インタフェースを持つ STM CPU
//
//     +--------------------+  IB_AD     +------------+
//     | stm_cntl           | ---------> | stm_icache | --+
//     |  (EXT_BUS=1)       | <--------- | (命令)     |   |  +----------------+
//     |                    |            +------------+   +->|                |  AXI4
//     |                    |  LBS_* (オペランド)            | stm_axi_master | <=====> m_axi_*
//     |                    | ------------------------------>|                |  (32bit データ)
//     |                    | <------------------------------|                |
//     +--------------------+                                +----------------+
//          |      ^
//          v      |  GR
//     +--------------------+
//     | stm_regfile        |
//     +--------------------+
//
//  stm_sys.v から stm_memory を外し、代わりに命令キャッシュと AXI4 マスタを
//  付けたもの。データ側にキャッシュは無い。
//  命令もデータも同じ AXI4 ポートからアクセスする (命令フェッチは ARPROT[2]=1)。
//  クロックは aclk 1 本, リセットは AXI の慣習どおり aresetn (0 でリセット,
//  aclk に同期して扱う)。リセット解除後, RESET_PC から実行を始める。
// =====================================================================
module stm_axi_top #(
  parameter ID_W      = 4,
  parameter IF_ID     = 0,
  parameter OP_ID     = 1,
  parameter BYTE_SWAP = 0,          // stm_axi_master.v を参照
  parameter ICACHE    = 1,          // 0 にすると命令キャッシュ無し (stm_icache.v を参照)
  parameter IC_LINE_W = 5,          // 命令キャッシュのライン = 2^IC_LINE_W バイト
  parameter IC_SET_W  = 7           // 命令キャッシュのライン数 = 2^IC_SET_W (既定 4KB)
) (
  input                 aclk,
  input                 aresetn,
  input      [31:0]     RESET_PC,
  output     [31:0]     PC,         // 観測用
  output                bus_error,  // SLVERR/DECERR 応答があった (sticky)

  output     [ID_W-1:0] m_axi_awid,
  output     [31:0]     m_axi_awaddr,
  output     [7:0]      m_axi_awlen,
  output     [2:0]      m_axi_awsize,
  output     [1:0]      m_axi_awburst,
  output                m_axi_awlock,
  output     [3:0]      m_axi_awcache,
  output     [2:0]      m_axi_awprot,
  output     [3:0]      m_axi_awqos,
  output                m_axi_awvalid,
  input                 m_axi_awready,
  output     [31:0]     m_axi_wdata,
  output     [3:0]      m_axi_wstrb,
  output                m_axi_wlast,
  output                m_axi_wvalid,
  input                 m_axi_wready,
  input      [ID_W-1:0] m_axi_bid,
  input      [1:0]      m_axi_bresp,
  input                 m_axi_bvalid,
  output                m_axi_bready,
  output     [ID_W-1:0] m_axi_arid,
  output     [31:0]     m_axi_araddr,
  output     [7:0]      m_axi_arlen,
  output     [2:0]      m_axi_arsize,
  output     [1:0]      m_axi_arburst,
  output                m_axi_arlock,
  output     [3:0]      m_axi_arcache,
  output     [2:0]      m_axi_arprot,
  output     [3:0]      m_axi_arqos,
  output                m_axi_arvalid,
  input                 m_axi_arready,
  input      [ID_W-1:0] m_axi_rid,
  input      [31:0]     m_axi_rdata,
  input      [1:0]      m_axi_rresp,
  input                 m_axi_rlast,
  input                 m_axi_rvalid,
  output                m_axi_rready
);
  // stm_cntl / stm_axi_master とも同期リセット。aresetn は aclk に同期して
  // 解除されるもの (AXI の約束) とし、ここでは同期化しない。
  wire rst = !aresetn;

  wire [3:0]  dd_rad1, dd_rad2, dd_radb, b_ls_rads;
  wire [31:0] gr_dt_1, gr_dt_2, gr_dt_b, gr_dt_s;
  wire        w_we1, w_we2;
  wire [3:0]  w_wad1, w_wad2;
  wire [31:0] w_wdt1, w_wdt2;
  wire        lbs_we;
  wire [31:0] lbs_ad, lbs_dt, ib_ad;
  wire [31:0] mem_dt_op, mem_dt_if_h, mem_dt_if_l;
  wire        ib_valid, op_b_new, op_b_busreq;
  wire [31:0] ib_ad_nxt;
  wire        if_rdy, op_rdy;
  wire        fr_req, fr_ack, fr_valid, fr_last;
  wire [31:0] fr_addr, fr_data;
  wire [7:0]  fr_len;
  wire [1:0]  fr_burst;

  stm_cntl #(.EXT_BUS(1)) u_cntl (
    .clk              (aclk),
    .rst              (rst),
    .RESET_PC         (RESET_PC),
    .RANDOM_FOR_OPCLH (op_rdy),       // OP-B の要求が完了
    .RANDOM_FOR_IFRDY (1'b1),
    .RANDOM_FOR_IFCLH (if_rdy),       // 命令フェッチのデータが届いた
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
    .IB_VALID         (ib_valid),
    .IB_AD_NXT        (ib_ad_nxt),
    .OP_B_NEW         (op_b_new),
    .OP_B_BUSREQ      (op_b_busreq),
    .PC               (PC)
  );

  stm_regfile u_reg (
    .clk  (aclk),
    .we1  (w_we1),   .we2  (w_we2),
    .wad1 (w_wad1),  .wad2 (w_wad2),
    .wdt1 (w_wdt1),  .wdt2 (w_wdt2),
    .rad1 (dd_rad1), .rad2 (dd_rad2), .radb (dd_radb), .rads (b_ls_rads),
    .rdt1 (gr_dt_1), .rdt2 (gr_dt_2), .rdtb (gr_dt_b), .rdts (gr_dt_s)
  );

  stm_icache #(.ENABLE(ICACHE), .LINE_W(IC_LINE_W), .SET_W(IC_SET_W)) u_icache (
    .clk       (aclk),
    .rst       (rst),
    .ib_valid  (ib_valid),
    .ib_ad     (ib_ad),
    .ib_ad_nxt (ib_ad_nxt),
    .if_rdy    (if_rdy),
    .if_dt_h   (mem_dt_if_h),
    .if_dt_l   (mem_dt_if_l),
    .fr_req    (fr_req),
    .fr_addr   (fr_addr),
    .fr_len    (fr_len),
    .fr_burst  (fr_burst),
    .fr_ack    (fr_ack),
    .fr_valid  (fr_valid),
    .fr_data   (fr_data),
    .fr_last   (fr_last)
  );

  stm_axi_master #(
    .ID_W(ID_W), .IF_ID(IF_ID), .OP_ID(OP_ID), .BYTE_SWAP(BYTE_SWAP)
  ) u_axi (
    .clk           (aclk),
    .rst           (rst),
    .ifr_req       (fr_req),
    .ifr_addr      (fr_addr),
    .ifr_len       (fr_len),
    .ifr_burst     (fr_burst),
    .ifr_ack       (fr_ack),
    .ifr_valid     (fr_valid),
    .ifr_data      (fr_data),
    .ifr_last      (fr_last),
    .op_new        (op_b_new),
    .op_busreq     (op_b_busreq),
    .op_we         (lbs_we),
    .op_ad         (lbs_ad),
    .op_wdt        (lbs_dt),
    .op_rdy        (op_rdy),
    .op_dt         (mem_dt_op),
    .bus_error     (bus_error),
    .m_axi_awid    (m_axi_awid),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),
    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awlock  (m_axi_awlock),
    .m_axi_awcache (m_axi_awcache),
    .m_axi_awprot  (m_axi_awprot),
    .m_axi_awqos   (m_axi_awqos),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wlast   (m_axi_wlast),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    .m_axi_bid     (m_axi_bid),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready),
    .m_axi_arid    (m_axi_arid),
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arlock  (m_axi_arlock),
    .m_axi_arcache (m_axi_arcache),
    .m_axi_arprot  (m_axi_arprot),
    .m_axi_arqos   (m_axi_arqos),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rid     (m_axi_rid),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rresp   (m_axi_rresp),
    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready)
  );
endmodule
