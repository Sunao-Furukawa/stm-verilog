// =====================================================================
//  tb_stm_axi.v  -  stm_axi_top (AXI4 マスタ版) のテストベンチ
//    tb_stm.v と同じ手順で動かす。メモリは AXI4 スレーブモデル
//    (axi4_mem_slave) で、CPU とは AXI4 だけでつながる。
//      * メモリを初期化して PC=開始番地から実行
//      * 各サイクル, Mem[PC>>2] の上位 4bit が 0xD (診断命令 DD/DF...) なら終了
//      * bup0/bup1 のテストは SUCCESS (0x3F0) で終われば OK, DEAD (0x3D0) は NG
//      * スレーブが AXI の規則違反を見つけていたら AXIERR
//
//  plusargs:
//    +HEX=<file>      $readmemh 形式のメモリイメージ (tools/mem2hex.py で作る)
//    +PC=<hex>        開始番地
//    +CYCLES=<dec>    最大サイクル数
//    +RANDOM          スレーブのウェイト・応答順を乱数で変える
//    +SEED=<dec>      乱数の種
//    +TRACE           毎サイクル PC 等を表示
//    +VCD             tb_stm_axi.vcd に波形を書く
//
//  パラメータ BYTE_SWAP (iverilog -P tb_stm_axi.BYTE_SWAP=1) で
//  stm_axi_master のバイトレーンの並びを切り替えられる。1 のときは
//  メモリイメージを語ごとにバイト反転してスレーブに入れる。
// =====================================================================
module tb_stm_axi;
  parameter BYTE_SWAP = 0;
  localparam ID_W = 4;

  reg         clk = 1'b0;
  reg         aresetn = 1'b0;
  reg  [31:0] reset_pc;
  reg         rnd = 1'b0;
  wire [31:0] pc;
  wire        bus_error;

  reg  [8*1024-1:0] hexfile;     // +HEX= のファイル名 (最大 1024 文字)
  integer       cycles, maxcyc, seed, k;
  reg           trace;
  reg  [31:0]   insn, w;

  wire [ID_W-1:0] awid, bid, arid, rid;
  wire [31:0]     awaddr, wdata, araddr, rdata;
  wire [7:0]      awlen, arlen;
  wire [2:0]      awsize, arsize, awprot, arprot;
  wire [1:0]      awburst, arburst, bresp, rresp;
  wire [3:0]      awcache, arcache, awqos, arqos, wstrb;
  wire            awlock, arlock;
  wire            awvalid, awready, wlast, wvalid, wready, bvalid, bready;
  wire            arvalid, arready, rlast, rvalid, rready;

  stm_axi_top #(.ID_W(ID_W), .BYTE_SWAP(BYTE_SWAP)) u_dut (
    .aclk(clk), .aresetn(aresetn), .RESET_PC(reset_pc), .PC(pc),
    .bus_error(bus_error),
    .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
    .m_axi_awsize(awsize), .m_axi_awburst(awburst), .m_axi_awlock(awlock),
    .m_axi_awcache(awcache), .m_axi_awprot(awprot), .m_axi_awqos(awqos),
    .m_axi_awvalid(awvalid), .m_axi_awready(awready),
    .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
    .m_axi_wvalid(wvalid), .m_axi_wready(wready),
    .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid),
    .m_axi_bready(bready),
    .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
    .m_axi_arsize(arsize), .m_axi_arburst(arburst), .m_axi_arlock(arlock),
    .m_axi_arcache(arcache), .m_axi_arprot(arprot), .m_axi_arqos(arqos),
    .m_axi_arvalid(arvalid), .m_axi_arready(arready),
    .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp),
    .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
  );

  axi4_mem_slave #(.AW(10), .ID_W(ID_W)) u_mem (
    .aclk(clk), .aresetn(aresetn), .rnd(rnd),
    .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
    .s_axi_awsize(awsize), .s_axi_awburst(awburst),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast),
    .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen),
    .s_axi_arsize(arsize), .s_axi_arburst(arburst),
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
    .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready)
  );

  always #5 clk = ~clk;

  function [31:0] bswap;
    input [31:0] d;
    bswap = {d[7:0], d[15:8], d[23:16], d[31:24]};
  endfunction

  task finish_with;
    input [8*8-1:0] verdict;
    begin
      if (u_mem.errors != 0) verdict = "AXIERR";
      $display("RESULT: stop at PC=%h after %0d cycles -> %0s", pc, cycles, verdict);
      $display("AXI: reads=%0d writes=%0d protocol_errors=%0d bus_error=%b",
               u_mem.n_rd, u_mem.n_wr, u_mem.errors, bus_error);
      $finish;
    end
  endtask

  initial begin
    if (!$value$plusargs("HEX=%s", hexfile)) begin
      $display("usage: vvp sim +HEX=mem.hex +PC=300 +CYCLES=2500 [+RANDOM] [+SEED=n]");
      $finish;
    end
    if (!$value$plusargs("PC=%h", reset_pc))   reset_pc = 32'h300;
    if (!$value$plusargs("CYCLES=%d", maxcyc)) maxcyc   = 2500;
    if (!$value$plusargs("SEED=%d", seed))     seed     = 1;
    rnd   = $test$plusargs("RANDOM");
    trace = $test$plusargs("TRACE");
    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_stm_axi.vcd");
      $dumpvars(0, tb_stm_axi);
    end

    #1;   // スレーブの initial (メモリのクリア) の後で読み込む
    u_mem.seed = seed;
    $readmemh(hexfile, u_mem.mem);
    if (BYTE_SWAP)
      for (k = 0; k < 1024; k = k + 1) u_mem.mem[k] = bswap(u_mem.mem[k]);

    repeat (2) @(posedge clk);
    @(negedge clk) aresetn = 1'b1;

    for (cycles = 1; cycles <= maxcyc; cycles = cycles + 1) begin
      #1;
      w    = u_mem.mem[pc[11:2]];
      insn = BYTE_SWAP ? bswap(w) : w;
      if (trace)
        $display("%4d PC=%h D_FWD=%b A_FWD=%b B_FWD=%b E_FWD=%b W_COMPLETE=%b I0=%h I1=%h AR=%b%b AW=%b W=%b R=%b B=%b",
                 cycles, pc, u_dut.u_cntl.D_FWD, u_dut.u_cntl.A_FWD,
                 u_dut.u_cntl.B_FWD, u_dut.u_cntl.E_FWD,
                 u_dut.u_cntl.W_COMPLETE, u_dut.u_cntl.I0, u_dut.u_cntl.I1,
                 arvalid, arready, awvalid, wvalid, rvalid, bvalid);
      if (insn[31:28] == 4'hD) begin
        if (pc == 32'h3f0)      finish_with("OK");
        else if (pc == 32'h3d0) finish_with("DEAD");
        else                    finish_with("STOP");
      end
      @(negedge clk);
    end
    $display("RESULT: timeout PC=%h after %0d cycles -> TIMEOUT", pc, maxcyc);
    $finish;
  end
endmodule
