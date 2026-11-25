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
//  パラメータ (iverilog -P tb_stm_axi.<名前>=<値>):
//    BYTE_SWAP  stm_axi_master のバイトレーンの並び。1 のときは
//               メモリイメージを語ごとにバイト反転してスレーブに入れる
//    ICACHE, IC_LINE_W, IC_SET_W   命令キャッシュの有無と大きさ (stm_icache.v)
//
//  コンソール: 番地 F000_0008 (I/O 領域) に語をストアすると, その下位 8bit を
//  1 文字として表示する (axi4_mem_slave の CONSOLE)。
//
//  tb_stm_axi.v  -  testbench for stm_axi_top (the AXI4 master version)
//    Runs the same way as tb_stm.v. The memory is an AXI4 slave model
//    (axi4_mem_slave), connected to the CPU only through AXI4.
//      * initialise the memory and run from PC = start address
//      * stop when the top 4 bits of Mem[PC>>2] are 0xD (diagnostic instructions DD/DF...) in a cycle
//      * the bup0/bup1 tests pass if they end at SUCCESS (0x3F0); DEAD (0x3D0) is a failure
//      * AXIERR if the slave found AXI rule violations
//
//  plusargs:
//    +HEX=<file>      memory image in $readmemh format (made by tools/mem2hex.py)
//    +PC=<hex>        start address
//    +CYCLES=<dec>    maximum number of cycles
//    +RANDOM          randomise the slave's waits and response order
//    +SEED=<dec>      random seed
//    +TRACE           print PC etc. every cycle
//    +VCD             write waveforms to tb_stm_axi.vcd
//
//  Parameters (iverilog -P tb_stm_axi.<name>=<value>):
//    BYTE_SWAP  byte-lane order of stm_axi_master. When 1,
//               the memory image is byte-reversed word by word before it is put in the slave
//    ICACHE, IC_LINE_W, IC_SET_W   presence and size of the instruction cache (stm_icache.v)
//
//  Console: storing a word to address F000_0008 (I/O region) prints its low 8 bits
//  as a character (CONSOLE of axi4_mem_slave).
//
// 【解説】テストベンチの構成とネット
//
//     +-------------+   aw*/w*  (マスタ → スレーブ)    +----------------+
//     |             | --------------------------------> |                |
//     | stm_axi_top |   b*      (スレーブ → マスタ)    | axi4_mem_slave |
//     |   (u_dut)   | <-------------------------------- |    (u_mem)     |
//     |             |   ar*     (マスタ → スレーブ)    |                |
//     |             | --------------------------------> |                |
//     |             |   r*      (スレーブ → マスタ)    |                |
//     +-------------+ <-------------------------------- +----------------+
//
//   ・下の wire は AXI4 の 5 チャネルそのもの。名前は m_axi_ / s_axi_ を取ったもの
//     (awaddr = AW チャネルの番地, rdata = R チャネルのデータ, ...)。
//     各チャネルは VALID (送り手) と READY (受け手) の 2 本で 1 回の受け渡しが決まる。
//   ・awlock / arlock / awcache / arcache / awprot / arprot / awqos / arqos は
//     u_dut から出ているがスレーブにはつないでいない (モデルが見ないため)。
//   ・n_if は arid == 0 (stm_axi_top の IF_ID) の AR を数える。命令キャッシュが
//     有効なら、これがキャッシュミス (ライン埋め) の回数になる。
//
// [Note] Structure of the testbench and its nets
//
//     +-------------+   aw*/w*  (master -> slave)       +----------------+
//     |             | --------------------------------> |                |
//     | stm_axi_top |   b*      (slave -> master)       | axi4_mem_slave |
//     |   (u_dut)   | <-------------------------------- |    (u_mem)     |
//     |             |   ar*     (master -> slave)       |                |
//     |             | --------------------------------> |                |
//     |             |   r*      (slave -> master)       |                |
//     +-------------+ <-------------------------------- +----------------+
//
//   - The wires below are the 5 AXI4 channels themselves, named without m_axi_ / s_axi_
//     (awaddr = address of the AW channel, rdata = data of the R channel, ...).
//     On each channel, VALID (sender) and READY (receiver) together decide one transfer.
//   - awlock / arlock / awcache / arcache / awprot / arprot / awqos / arqos come out of
//     u_dut but are not connected to the slave (the model does not look at them).
//   - n_if counts ARs with arid == 0 (IF_ID of stm_axi_top). With the instruction cache
//     enabled, this is the number of cache misses (line fills).
// =====================================================================
module tb_stm_axi;
  parameter BYTE_SWAP = 0;
  parameter ICACHE    = 1;
  parameter IC_LINE_W = 5;
  parameter IC_SET_W  = 7;
  localparam ID_W = 4;

  reg         clk = 1'b0;
  reg         aresetn = 1'b0;
  reg  [31:0] reset_pc;
  reg         rnd = 1'b0;
  wire [31:0] pc;
  wire        bus_error;

  reg  [8*1024-1:0] hexfile;     // +HEX= のファイル名 (最大 1024 文字)
                                 // file name from +HEX= (up to 1024 characters)
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

  stm_axi_top #(.ID_W(ID_W), .BYTE_SWAP(BYTE_SWAP), .ICACHE(ICACHE),
                .IC_LINE_W(IC_LINE_W), .IC_SET_W(IC_SET_W)) u_dut (
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

  axi4_mem_slave #(.AW(10), .ID_W(ID_W), .SWAP(BYTE_SWAP)) u_mem (
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

  // 命令フェッチの AR を数える (キャッシュのミス回数)
  // count the ARs of instruction fetches (the number of cache misses)
  integer n_if = 0;
  always @(posedge clk) if (arvalid && arready && arid == 0) n_if = n_if + 1;

  function [31:0] bswap;
    input [31:0] d;
    bswap = {d[7:0], d[15:8], d[23:16], d[31:24]};
  endfunction

  task finish_with;
    input [8*8-1:0] verdict;
    begin
      if (u_mem.errors != 0) verdict = "AXIERR";
      $display("RESULT: stop at PC=%h after %0d cycles -> %0s", pc, cycles, verdict);
      $display("AXI: reads=%0d (fetch %0d) writes=%0d protocol_errors=%0d bus_error=%b",
               u_mem.n_rd, n_if, u_mem.n_wr, u_mem.errors, bus_error);
      $display("DEV: reads=%0d dev_a=%0d dev_b=%h read_errors=%0d write_errors=%0d",
               u_mem.dev_rd, u_mem.dev_a, u_mem.dev_b, u_mem.n_rd_err, u_mem.n_wr_err);
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
          // load after the slave's initial block (memory clear)
    // 【解説】BYTE_SWAP=1 のときはバスの語のバイト順が逆になるので、スレーブの
    //         メモリにも反転した語を入れておく (CPU から見える内容は同じになる)。
    // [Note] With BYTE_SWAP=1 the byte order of the words on the bus is reversed, so reversed words
    //        are put into the slave's memory too (the contents seen by the CPU stay the same).
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
