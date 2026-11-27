// =====================================================================
//  tb_noio.v  -  tb_stm_axi.v の実験用コピー: stm_axi_top を IO_EN=0 で作る
//    (モジュール名は tb_stm_axi のままなので, tb_stm_axi を階層名で見るモニタも
//     そのまま使え, tb/tb_stm_axi.v とは同時にコンパイルできない)
//    使い方 (tb/tb_stm_axi.v の代わりに指定する):
//      iverilog -g2001 -I rtl -o noio.vvp tb/tb_noio.v tb/axi4_mem_slave.v \n//               rtl/stm_axi_top.v rtl/stm_icache.v rtl/stm_axi_master.v \n//               rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v
//
//  tb_noio.v  -  experimental copy of tb_stm_axi.v: builds stm_axi_top with IO_EN=0
//    (The module name stays tb_stm_axi, so monitors that look at tb_stm_axi by hierarchical
//     name work with it unchanged, and it cannot be compiled together with tb/tb_stm_axi.v)
//    Usage (give it instead of tb/tb_stm_axi.v):
//      iverilog -g2001 -I rtl -o noio.vvp tb/tb_noio.v tb/axi4_mem_slave.v \n//               rtl/stm_axi_top.v rtl/stm_icache.v rtl/stm_axi_master.v \n//               rtl/stm_cntl.v rtl/stm_exu.v rtl/stm_regfile.v
//
// 【ネットリスト解説】IO_EN=0 にすると何が変わるか
//   ・IO_EN は stm_cntl / stm_icache / stm_axi_master に渡るパラメータ (定数)。
//     is_io() = EXT_BUS && IO_EN && ((番地 & IO_MASK) == IO_BASE) が定数 0 になり,
//     番地の上位 4bit の比較器とそれにつながる論理 (I/O ロードを確定まで待たせる
//     AA_IO_LD_HOLD, ストアの B サイクル読み出しを省く OP_B_IO_ST, I/O からの
//     フェッチを不正命令にする io_hit, AxCACHE=Device の選択) は合成で消える。
//   ・CPU から見ると 0xF000_0000〜 も普通のメモリになり, ロードは投機的に出て,
//     ストアの前には B サイクルの読み出しが出る。一方スレーブ (axi4_mem_slave) の
//     I/O デバイス (DEV_A / DEV_B / CONSOLE) はそのまま。
//   ・そのため I/O を使うテストでは DEV_A の読み出し回数や DEV_B の値が合わなくなる
//     (かもしれない)。IO_EN=1 の I/O 領域の扱いが要ることを, 比べて確かめるための版。
//   ・ネット (AXI4 の 5 チャネルの wire) は tb_stm_axi.v と同じ。
//
// [Netlist notes] What changes with IO_EN=0
//   - IO_EN is a parameter (constant) passed to stm_cntl / stm_icache / stm_axi_master.
//     is_io() = EXT_BUS && IO_EN && ((address & IO_MASK) == IO_BASE) becomes the constant 0,
//     and synthesis removes the comparator on the top 4 address bits and the logic hanging off
//     it (AA_IO_LD_HOLD that holds I/O loads until they are certain, OP_B_IO_ST that skips the
//     B-cycle read of stores, io_hit that turns fetches from I/O into illegal instructions, the
//     AxCACHE=Device selection).
//   - Seen from the CPU, 0xF000_0000- becomes ordinary memory: loads go out speculatively and
//     a store is preceded by a B-cycle read. The slave's (axi4_mem_slave) I/O devices
//     (DEV_A / DEV_B / CONSOLE) stay as they are.
//   - So in tests that use I/O, the DEV_A read count or the DEV_B value can go wrong.
//     This version is for checking, by comparison, that the IO_EN=1 handling of the I/O region
//     is needed.
//   - The nets (wires of the 5 AXI4 channels) are the same as in tb_stm_axi.v.
//
//  以下は tb_stm_axi.v の説明 / below is the description of tb_stm_axi.v:
//
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
module tb_stm_axi;                                      // I/O領域を無効 (IO_EN=0) にした実験用テストベンチ (tb_stm_axi.vと同名なので片方だけコンパイル, 合成されない) / experimental testbench with the I/O region disabled (IO_EN=0); same name as tb_stm_axi.v, so compile only one; never synthesized
  parameter BYTE_SWAP = 0;                              // バス上のバイト順 (-Pで上書き可) / byte order on the bus (overridable with -P)
  parameter ICACHE    = 1;                              // 命令キャッシュの有無 / instruction cache on/off
  parameter IC_LINE_W = 5;                              // キャッシュのライン長 (2^5=32バイト) / cache line length (2^5 = 32 bytes)
  parameter IC_SET_W  = 7;                              // キャッシュのライン数 (2^7=128) / number of cache lines (2^7 = 128)
  localparam ID_W = 4;                                  // AXIのIDの幅 / AXI ID width

  reg         clk = 1'b0;                               // クロック / clock
  reg         aresetn = 1'b0;                           // 負論理リセット: 0で始める / active-low reset: starts at 0
  reg  [31:0] reset_pc;                                 // 開始番地 / start address
  reg         rnd = 1'b0;                               // スレーブの応答を乱数で遅らせるか (+RANDOM) / delay slave responses randomly? (+RANDOM)
  wire [31:0] pc;                                       // DUTのPC / the DUT's PC
  wire        bus_error;                                // DUTのエラー表示 / the DUT's error flag

  reg  [8*1024-1:0] hexfile;     // +HEX= のファイル名 (最大 1024 文字)
                                 // file name from +HEX= (up to 1024 characters)
  integer       cycles, maxcyc, seed, k;                // サイクル数, 上限, 種, ループ変数 / cycle count, limit, seed, loop variable
  reg           trace;                                  // +TRACEの有無 / +TRACE given?
  reg  [31:0]   insn, w;                                // PCの命令語 (wはバス上の語, insnはCPUから見た語) / insn at PC (w = bus word, insn = CPU view)

  wire [ID_W-1:0] awid, bid, arid, rid;                 // AXIのIDのネット (DUT⇔スレーブ) / AXI ID nets (DUT <-> slave)
  wire [31:0]     awaddr, wdata, araddr, rdata;         // 番地とデータのネット / address and data nets
  wire [7:0]      awlen, arlen;                         // バースト長のネット / burst length nets
  wire [2:0]      awsize, arsize, awprot, arprot;       // サイズと保護属性のネット / size and protection nets
  wire [1:0]      awburst, arburst, bresp, rresp;       // バーストの種類と応答のネット / burst type and response nets
  wire [3:0]      awcache, arcache, awqos, arqos, wstrb; // キャッシュ属性, QoS, ストローブのネット / cache attribute, QoS, strobe nets
  wire            awlock, arlock;                       // 排他アクセスのネット / exclusive-access nets
  wire            awvalid, awready, wlast, wvalid, wready, bvalid, bready; // 書き込み側のハンドシェイクのネット / write-side handshake nets
  wire            arvalid, arready, rlast, rvalid, rready; // 読み出し側のハンドシェイクのネット / read-side handshake nets

  // 【解説】tb_stm_axi.v との違いはここだけ: IO_EN(0) で CPU 側の I/O 領域を無くす。
  // [Note] The only difference from tb_stm_axi.v: IO_EN(0) removes the I/O region on the CPU side.
  stm_axi_top #(.IO_EN(0), .ID_W(ID_W), .BYTE_SWAP(BYTE_SWAP), .ICACHE(ICACHE), // DUT: IO_EN=0なのでis_io()は定数0, I/O用の回路 (投機ロード抑止など) が丸ごと消える / DUT: IO_EN=0 makes is_io() constant 0, so all I/O logic (e.g. holding speculative loads) disappears
                .IC_LINE_W(IC_LINE_W), .IC_SET_W(IC_SET_W)) u_dut ( // キャッシュの大きさを渡す / pass the cache size
    .aclk(clk), .aresetn(aresetn), .RESET_PC(reset_pc), .PC(pc), // クロック, リセット, 開始番地, PC / clock, reset, start address, PC
    .bus_error(bus_error),                              // エラー表示 / error flag
    .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), // AWチャネル (ID, 番地, 長さ) / AW channel (ID, address, length)
    .m_axi_awsize(awsize), .m_axi_awburst(awburst), .m_axi_awlock(awlock), // AWチャネル (サイズ, バースト, ロック) / AW channel (size, burst, lock)
    .m_axi_awcache(awcache), .m_axi_awprot(awprot), .m_axi_awqos(awqos), // AWチャネル (属性) / AW channel (attributes)
    .m_axi_awvalid(awvalid), .m_axi_awready(awready),   // AWのハンドシェイク / AW handshake
    .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), // Wチャネル (データ, ストローブ, LAST) / W channel (data, strobes, last)
    .m_axi_wvalid(wvalid), .m_axi_wready(wready),       // Wのハンドシェイク / W handshake
    .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), // Bチャネル (ID, 応答, VALID) / B channel (ID, response, valid)
    .m_axi_bready(bready),                              // BのREADY / B ready
    .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), // ARチャネル (ID, 番地, 長さ) / AR channel (ID, address, length)
    .m_axi_arsize(arsize), .m_axi_arburst(arburst), .m_axi_arlock(arlock), // ARチャネル (サイズ, バースト, ロック) / AR channel (size, burst, lock)
    .m_axi_arcache(arcache), .m_axi_arprot(arprot), .m_axi_arqos(arqos), // ARチャネル (属性) / AR channel (attributes)
    .m_axi_arvalid(arvalid), .m_axi_arready(arready),   // ARのハンドシェイク / AR handshake
    .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp), // Rチャネル (ID, データ, 応答) / R channel (ID, data, response)
    .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready) // Rチャネル (LAST, ハンドシェイク) / R channel (last, handshake)
  );                                                    // u_dutの終わり / end of u_dut

  axi4_mem_slave #(.AW(10), .ID_W(ID_W), .SWAP(BYTE_SWAP)) u_mem ( // AXI4スレーブのメモリモデル (1024語, 乱数で遅延) / AXI4 slave memory model (1024 words, random delays)
    .aclk(clk), .aresetn(aresetn), .rnd(rnd),           // クロック, リセット, 乱数モード / clock, reset, random mode
    .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen), // AWチャネル / AW channel
    .s_axi_awsize(awsize), .s_axi_awburst(awburst),     // AWチャネル (サイズ, バースト) / AW channel (size, burst)
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),   // AWのハンドシェイク / AW handshake
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast), // Wチャネル / W channel
    .s_axi_wvalid(wvalid), .s_axi_wready(wready),       // Wのハンドシェイク / W handshake
    .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), // Bチャネル / B channel
    .s_axi_bready(bready),                              // BのREADY / B ready
    .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen), // ARチャネル / AR channel
    .s_axi_arsize(arsize), .s_axi_arburst(arburst),     // ARチャネル (サイズ, バースト) / AR channel (size, burst)
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),   // ARのハンドシェイク / AR handshake
    .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp), // Rチャネル / R channel
    .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready) // Rチャネル (LAST, ハンドシェイク) / R channel (last, handshake)
  );                                                    // u_memの終わり / end of u_mem

  always #5 clk = ~clk;                                 // 周期10のクロック / clock with period 10

  // 命令フェッチの AR を数える (キャッシュのミス回数)
  // count the ARs of instruction fetches (the number of cache misses)
  integer n_if = 0;                                     // 命令フェッチのAR回数 / number of fetch ARs
  always @(posedge clk) if (arvalid && arready && arid == 0) n_if = n_if + 1; // ID=0 (IF) のARが受け付けられたら数える (キャッシュミス数) / count accepted ARs with ID 0 (IF) = cache misses

  function [31:0] bswap;                                // 語のバイト順を反転する関数 / reverse the bytes of a word
    input [31:0] d;                                     // 入力の語 / input word
    bswap = {d[7:0], d[15:8], d[23:16], d[31:24]};      // バイトの並べ替え / reorder the bytes
  endfunction                                           // 関数の終わり / end of function

  task finish_with;                                     // 結果と統計を表示して終わるタスク / task: print the verdict and statistics, then finish
    input [8*8-1:0] verdict;                            // 判定の文字列 (最大8文字) / verdict string (up to 8 chars)
    begin                                               // タスク本体 / task body
      if (u_mem.errors != 0) verdict = "AXIERR";        // スレーブがプロトコル違反を見つけていたらAXIERRにする / AXIERR if the slave found protocol violations
      $display("RESULT: stop at PC=%h after %0d cycles -> %0s", pc, cycles, verdict); // run_bup_axi.shが見る結果行 / the result line run_bup_axi.sh greps
      $display("AXI: reads=%0d (fetch %0d) writes=%0d protocol_errors=%0d bus_error=%b", // バスの統計: 読み出し数, フェッチ数, 書き込み数, 違反数 / bus statistics: reads, fetches, writes, violations
               u_mem.n_rd, n_if, u_mem.n_wr, u_mem.errors, bus_error); // 表示する値 (スレーブの内部カウンタを階層参照) / values (hierarchical refs to the slave's counters)
      $display("DEV: reads=%0d dev_a=%0d dev_b=%h read_errors=%0d write_errors=%0d", // I/Oデバイスの統計 / I/O device statistics
               u_mem.dev_rd, u_mem.dev_a, u_mem.dev_b, u_mem.n_rd_err, u_mem.n_wr_err); // 表示する値 / values
      $finish;                                          // 終了 / finish
    end                                                 // タスク本体の終わり / end of task body
  endtask                                               // タスクの終わり / end of task

  initial begin                                         // テストの手順 / the test sequence
    if (!$value$plusargs("HEX=%s", hexfile)) begin      // +HEX=が無ければ使い方 / usage when +HEX= is missing
      $display("usage: vvp sim +HEX=mem.hex +PC=300 +CYCLES=2500 [+RANDOM] [+SEED=n]"); // 使い方の表示 / print usage
      $finish;                                          // 終了 / finish
    end                                                 // if の終わり / end of if
    if (!$value$plusargs("PC=%h", reset_pc))   reset_pc = 32'h300; // 開始番地 (既定0x300) / start address (default 0x300)
    if (!$value$plusargs("CYCLES=%d", maxcyc)) maxcyc   = 2500; // サイクル上限 (既定2500: バスが遅いので多め) / cycle limit (default 2500: the bus is slower)
    if (!$value$plusargs("SEED=%d", seed))     seed     = 1; // 乱数の種 / random seed
    rnd   = $test$plusargs("RANDOM");                   // スレーブの乱数遅延を使うか / use the slave's random delays?
    trace = $test$plusargs("TRACE");                    // 毎サイクルの表示 / per-cycle trace
    if ($test$plusargs("VCD")) begin                    // +VCDなら波形を記録 / with +VCD, record waveforms
      $dumpfile("tb_stm_axi.vcd");                      // 波形ファイル名 / waveform file name
      $dumpvars(0, tb_stm_axi);                         // 全階層の全信号を記録 / dump every signal of every level
    end                                                 // if の終わり / end of if

    #1;   // スレーブの initial (メモリのクリア) の後で読み込む
          // load after the slave's initial block (memory clear)
    // 【解説】BYTE_SWAP=1 のときはバスの語のバイト順が逆になるので、スレーブの
    //         メモリにも反転した語を入れておく (CPU から見える内容は同じになる)。
    // [Note] With BYTE_SWAP=1 the byte order of the words on the bus is reversed, so reversed words
    //        are put into the slave's memory too (the contents seen by the CPU stay the same).
    u_mem.seed = seed;                                  // スレーブの乱数の種を設定 / set the slave's seed
    $readmemh(hexfile, u_mem.mem);                      // プログラムをスレーブのメモリへ / load the program into the slave memory
    if (BYTE_SWAP)                                      // バイト順を入れ替える設定なら / when byte swapping
      for (k = 0; k < 1024; k = k + 1) u_mem.mem[k] = bswap(u_mem.mem[k]); // 全語を反転して入れ直す / reverse every word

    repeat (2) @(posedge clk);                          // リセットを2クロック / hold reset 2 clocks
    @(negedge clk) aresetn = 1'b1;                      // 立ち下がりでリセット解除 / release reset on the falling edge

    for (cycles = 1; cycles <= maxcyc; cycles = cycles + 1) begin // 1サイクルずつ / one cycle at a time
      #1;                                               // 信号が落ち着くのを待つ / let signals settle
      w    = u_mem.mem[pc[11:2]];                       // PCの語をスレーブのメモリから直接読む / read the word at PC straight from the slave memory
      insn = BYTE_SWAP ? bswap(w) : w;                  // CPUから見た命令語に直す / convert to the CPU's view
      if (trace)                                        // +TRACEなら / with +TRACE
        $display("%4d PC=%h D_FWD=%b A_FWD=%b B_FWD=%b E_FWD=%b W_COMPLETE=%b I0=%h I1=%h AR=%b%b AW=%b W=%b R=%b B=%b", // パイプラインとAXIのハンドシェイクを表示 / show the pipeline and AXI handshakes
                 cycles, pc, u_dut.u_cntl.D_FWD, u_dut.u_cntl.A_FWD, // サイクル, PC, D/A段 (DUT内部を階層参照) / cycle, PC, D/A (hierarchical refs into the DUT)
                 u_dut.u_cntl.B_FWD, u_dut.u_cntl.E_FWD, // B/E段 / B/E stages
                 u_dut.u_cntl.W_COMPLETE, u_dut.u_cntl.I0, u_dut.u_cntl.I1, // 完了と発行候補 / completion and issue candidates
                 arvalid, arready, awvalid, wvalid, rvalid, bvalid); // AXIの各チャネルのVALID/READY / VALID / READY of the AXI channels
      if (insn[31:28] == 4'hD) begin                    // 診断命令に着いたら止める / stop at a diagnostic insn
        if (pc == 32'h3f0)      finish_with("OK");      // 0x3f0 = 成功 / 0x3f0 = pass
        else if (pc == 32'h3d0) finish_with("DEAD");    // 0x3d0 = 失敗 / 0x3d0 = fail
        else                    finish_with("STOP");    // その他 = 停止 / otherwise = stop
      end                                               // if の終わり / end of if
      @(negedge clk);                                   // 次のサイクルへ / next cycle
    end                                                 // for の終わり / end of for
    $display("RESULT: timeout PC=%h after %0d cycles -> TIMEOUT", pc, maxcyc); // 上限まで止まらなかった / did not stop within the limit
    $finish;                                            // 終了 / finish
  end                                                   // initial の終わり / end of initial
endmodule                                               // モジュールの終わり / end of module
