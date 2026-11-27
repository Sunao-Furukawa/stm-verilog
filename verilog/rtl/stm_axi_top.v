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
//
//  stm_axi_top.v  -  the STM CPU with an AXI4 master interface
//  (in the figure: 命令 = instructions, オペランド = operands, 32bit データ = 32-bit data)
//
//  stm_sys.v with stm_memory removed and an instruction cache and an AXI4 master added
//  in its place. There is no cache on the data side.
//  Instructions and data are both accessed through the same AXI4 port (instruction fetches have ARPROT[2]=1).
//  One clock, aclk; the reset is aresetn as usual for AXI (0 = reset,
//  handled synchronously to aclk). After reset is released, execution starts at RESET_PC.
//
// 【ネットリスト解説】このモジュールも配線だけ (rst = !aresetn の NOT 1 個を除く)。
//   stm_sys.v との違いは、メモリの代わりに 2 つのモジュールが入り、
//   stm_cntl の「乱数入力」が本物のハンドシェイクになること:
//
//     ネット          作り手                        使い手              意味
//     ib_valid        u_cntl (IB_V の FF)           u_icache            命令フェッチ要求が出ている
//     ib_ad           u_cntl (IB_AD の FF)          u_icache            その番地 (8 バイト単位)
//     ib_ad_nxt       u_cntl (IB_AD の D 入力)      u_icache            次のサイクルの ib_ad (RAM の先読み)
//     if_rdy          u_icache (組合せ)             u_cntl RANDOM_FOR_IFCLH  2 命令が揃った
//     mem_dt_if_h/l   u_icache (組合せ)             u_cntl (180)        その 2 命令
//     fr_req/addr/len/burst
//                     u_icache                      u_axi (ifr_*)       ライン埋めのバースト読み出し要求
//     fr_ack          u_axi (組合せ)                u_icache            AR が受け付けられた
//     fr_valid/data/last/err
//                     u_axi (R チャネルの振り分け)  u_icache            届いたビート
//     op_b_new        u_cntl (OP_B_NEW の FF)       u_axi op_new        OP-B に新しい要求が入った
//     op_b_busreq     u_cntl (050, 組合せ)          u_axi op_busreq     その要求にバスアクセスが要る
//     lbs_we/ad/dt    u_cntl (160 の FF)            u_axi op_we/ad/wdt  読むか書くか, 番地, 書くデータ
//     op_rdy          u_axi (FF から 1 段)          u_cntl RANDOM_FOR_OPCLH  要求が完了した
//     mem_dt_op       u_axi (op_dt の FF)           u_cntl (050)        読んだデータ
//     op_err          u_axi (op_err の FF)          u_cntl MEM_OP_ERR   読み出しがエラー応答だった
//     (GR 関係のネットは stm_sys.v と同じ)
//
//   AXI の入力 (m_axi_*ready, m_axi_r*, m_axi_b*) から stm_cntl の FF までの間には
//   必ず u_axi か u_icache の FF が入る (u_axi の op_dt / op_err, u_icache の RAM と
//   byp_*)。そのため AXI 側の配線遅延が CPU 内部の長い経路とつながらない。
//   if_rdy / op_rdy も u_icache / u_axi の FF (と RAM の出力レジスタ) から数段の
//   論理で作られ、AXI の入力を直接は通らない。
//
//   Vivado の合成結果 (syn/vivado のブロックデザイン) では、このモジュールの
//   中に stm_cntl / stm_regfile / stm_icache / stm_axi_master の 4 つのモジュールが
//   残り (stm_exu は stm_cntl に展開される)、命令キャッシュのデータ RAM が
//   RAMB36E1 1 個, タグ RAM が RAMB18E1 1 個になる。
//
// [Netlist notes] This module is also wiring only (except for one NOT, rst = !aresetn).
//   The difference from stm_sys.v is that two modules take the place of the memory, and the
//   "random inputs" of stm_cntl become real handshakes:
//
//     net             driver                        loads               meaning
//     ib_valid        u_cntl (IB_V FF)              u_icache            a fetch request is out
//     ib_ad           u_cntl (IB_AD FFs)            u_icache            its address (8-byte unit)
//     ib_ad_nxt       u_cntl (D input of IB_AD)     u_icache            ib_ad of the next cycle (RAM read-ahead)
//     if_rdy          u_icache (combinational)      u_cntl RANDOM_FOR_IFCLH  two instructions are ready
//     mem_dt_if_h/l   u_icache (combinational)      u_cntl (180)        those two instructions
//     fr_req/addr/len/burst
//                     u_icache                      u_axi (ifr_*)       burst read request for a line fill
//     fr_ack          u_axi (combinational)         u_icache            AR was accepted
//     fr_valid/data/last/err
//                     u_axi (R channel split)       u_icache            a beat arrived
//     op_b_new        u_cntl (OP_B_NEW FF)          u_axi op_new        a new request entered OP-B
//     op_b_busreq     u_cntl (050, combinational)   u_axi op_busreq     that request needs the bus
//     lbs_we/ad/dt    u_cntl (FFs in 160)           u_axi op_we/ad/wdt  read or write, address, write data
//     op_rdy          u_axi (1 level after FFs)     u_cntl RANDOM_FOR_OPCLH  the request completed
//     mem_dt_op       u_axi (op_dt FFs)             u_cntl (050)        the data read
//     op_err          u_axi (op_err FF)             u_cntl MEM_OP_ERR   the read got an error response
//     (the GR nets are the same as in stm_sys.v)
//
//   Between the AXI inputs (m_axi_*ready, m_axi_r*, m_axi_b*) and the FFs of stm_cntl there is
//   always an FF of u_axi or u_icache (op_dt / op_err in u_axi, the RAMs and byp_* in u_icache).
//   So the wiring delays on the AXI side never join the long paths inside the CPU.
//   if_rdy / op_rdy are also made by a few levels of logic from the FFs (and RAM output
//   registers) of u_icache / u_axi and do not pass directly through any AXI input.
//
//   In the Vivado synthesis result (the block design in syn/vivado), four modules remain inside
//   this module: stm_cntl / stm_regfile / stm_icache / stm_axi_master (stm_exu is flattened
//   into stm_cntl). The data RAM of the instruction cache becomes 1 RAMB36E1 and the tag RAM
//   1 RAMB18E1.
// =====================================================================
module stm_axi_top #(                                   // 合成用の最上位: CPU+レジスタファイル+命令キャッシュ+AXI4マスタ (ブロックデザインのIP) / top for synthesis: CPU + register file + icache + AXI4 master (the block-design IP)
  parameter ID_W      = 4,                              // AXIのIDの幅 / AXI ID width
  parameter IF_ID     = 0,                              // 命令フェッチのARID / ARID of instruction fetches
  parameter OP_ID     = 1,                              // オペランドのARID/AWID / ARID / AWID of operands
  parameter BYTE_SWAP = 0,          // stm_axi_master.v を参照
                                    // see stm_axi_master.v
  parameter ICACHE    = 1,          // 0 にすると命令キャッシュ無し (stm_icache.v を参照)
                                    // 0 = no instruction cache (see stm_icache.v)
  parameter IC_LINE_W = 5,          // 命令キャッシュのライン = 2^IC_LINE_W バイト
                                    // instruction cache line = 2^IC_LINE_W bytes
  parameter IC_SET_W  = 7,          // 命令キャッシュのライン数 = 2^IC_SET_W (既定 4KB)
                                    // number of instruction cache lines = 2^IC_SET_W (4 KB by default)
  // I/O 領域: (番地 & IO_MASK) == IO_BASE。既定は上位 256MB (0xF000_0000〜)。
  //   ・ロードは確定してから (投機的にではなく), 先行するストアが終わってから出す
  //   ・ストアの B サイクルの読み出しはしない (ワード単位でストアすること)
  //   ・命令はフェッチしない (不正命令として扱う)
  //   ・AxCACHE=4'b0000 (Device)
  // IO_EN=0 で I/O 領域を無くす。
  // I/O region: (address & IO_MASK) == IO_BASE. The default is the top 256 MB (0xF000_0000-).
  //   - loads go out only once certain (not speculatively), after earlier stores finish
  //   - stores do not do the B-cycle read (store whole words)
  //   - instructions are not fetched from it (treated as illegal instructions)
  //   - AxCACHE=4'b0000 (Device)
  // IO_EN=0 removes the I/O region.
  parameter        IO_EN   = 1,                         // I/O領域を使う / use the I/O region
  parameter [31:0] IO_BASE = 32'hF000_0000,             // I/O領域の先頭 / I/O region base
  parameter [31:0] IO_MASK = 32'hF000_0000              // I/O領域の判定マスク (上位4bit) / I/O region mask (top 4 bits)
) (                                                     // パラメータの終わり, ポートの始まり / end of parameters, start of ports
  input                 aclk,                           // AXIのクロック = CPUのクロック (ブロックデザインではClocking Wizardの出力) / AXI clock = CPU clock (Clocking Wizard output in the block design)
  input                 aresetn,                        // AXIのリセット (0でリセット, aclkに同期して解除) / AXI reset (active low, released synchronously to aclk)
  input      [31:0]     RESET_PC,                       // リセット後の開始番地 (ブロックデザインではConstant IP 0x300) / start address after reset (Constant IP 0x300 in the block design)
  output     [31:0]     PC,         // 観測用
                                    // for observation
  output                bus_error,  // SLVERR/DECERR 応答があった (sticky)。
                                    // ロードのエラーは CPU の例外にもなる
                                    // a SLVERR/DECERR response was seen (sticky).
                                    // An error on a load also becomes a CPU exception

  output     [ID_W-1:0] m_axi_awid,                     // AXI4 書き込みアドレスのID (出力) / AXI4 write address ID (output)
  output     [31:0]     m_axi_awaddr,                   // AXI4 書き込み番地 (出力) / AXI4 write address (output)
  output     [7:0]      m_axi_awlen,                    // AXI4 書き込みバースト長-1 (出力) / AXI4 write burst length - 1 (output)
  output     [2:0]      m_axi_awsize,                   // AXI4 書き込みの1ビートのサイズ (出力) / AXI4 write beat size (output)
  output     [1:0]      m_axi_awburst,                  // AXI4 書き込みバーストの種類 (出力) / AXI4 write burst type (output)
  output                m_axi_awlock,                   // AXI4 排他アクセス (出力) / AXI4 exclusive access (output)
  output     [3:0]      m_axi_awcache,                  // AXI4 書き込みのメモリ属性 (出力) / AXI4 write memory attributes (output)
  output     [2:0]      m_axi_awprot,                   // AXI4 書き込みの保護属性 (出力) / AXI4 write protection (output)
  output     [3:0]      m_axi_awqos,                    // AXI4 書き込みのQoS (出力) / AXI4 write QoS (output)
  output                m_axi_awvalid,                  // AXI4 書き込みアドレス有効 (出力) / AXI4 write address valid (output)
  input                 m_axi_awready,                  // AXI4 スレーブが書き込みアドレスを受け付けた (入力) / AXI4 slave accepts the write address (input)
  output     [31:0]     m_axi_wdata,                    // AXI4 書き込みデータ (出力) / AXI4 write data (output)
  output     [3:0]      m_axi_wstrb,                    // AXI4 バイトストローブ (出力) / AXI4 byte strobes (output)
  output                m_axi_wlast,                    // AXI4 最後の書き込みビート (出力) / AXI4 last write beat (output)
  output                m_axi_wvalid,                   // AXI4 書き込みデータ有効 (出力) / AXI4 write data valid (output)
  input                 m_axi_wready,                   // AXI4 スレーブが書き込みデータを受け付けた (入力) / AXI4 slave accepts the write data (input)
  input      [ID_W-1:0] m_axi_bid,                      // AXI4 書き込み応答のID (入力) / AXI4 write response ID (input)
  input      [1:0]      m_axi_bresp,                    // AXI4 書き込み応答 (bit1=1でエラー) (入力) / AXI4 write response (bit1=1 error) (input)
  input                 m_axi_bvalid,                   // AXI4 書き込み応答有効 (入力) / AXI4 write response valid (input)
  output                m_axi_bready,                   // AXI4 書き込み応答を受け取れる (出力) / AXI4 ready for the write response (output)
  output     [ID_W-1:0] m_axi_arid,                     // AXI4 読み出しアドレスのID (IF/OP) (出力) / AXI4 read address ID (IF/OP) (output)
  output     [31:0]     m_axi_araddr,                   // AXI4 読み出し番地 (出力) / AXI4 read address (output)
  output     [7:0]      m_axi_arlen,                    // AXI4 読み出しバースト長-1 (出力) / AXI4 read burst length - 1 (output)
  output     [2:0]      m_axi_arsize,                   // AXI4 読み出しの1ビートのサイズ (出力) / AXI4 read beat size (output)
  output     [1:0]      m_axi_arburst,                  // AXI4 読み出しバーストの種類 (出力) / AXI4 read burst type (output)
  output                m_axi_arlock,                   // AXI4 排他アクセス (出力) / AXI4 exclusive access (output)
  output     [3:0]      m_axi_arcache,                  // AXI4 読み出しのメモリ属性 (出力) / AXI4 read memory attributes (output)
  output     [2:0]      m_axi_arprot,                   // AXI4 読み出しの保護属性 (出力) / AXI4 read protection (output)
  output     [3:0]      m_axi_arqos,                    // AXI4 読み出しのQoS (出力) / AXI4 read QoS (output)
  output                m_axi_arvalid,                  // AXI4 読み出しアドレス有効 (出力) / AXI4 read address valid (output)
  input                 m_axi_arready,                  // AXI4 スレーブが読み出しアドレスを受け付けた (入力) / AXI4 slave accepts the read address (input)
  input      [ID_W-1:0] m_axi_rid,                      // AXI4 読み出しデータのID (入力) / AXI4 read data ID (input)
  input      [31:0]     m_axi_rdata,                    // AXI4 読み出しデータ (入力) / AXI4 read data (input)
  input      [1:0]      m_axi_rresp,                    // AXI4 読み出し応答 (bit1=1でエラー) (入力) / AXI4 read response (bit1=1 error) (input)
  input                 m_axi_rlast,                    // AXI4 最後の読み出しビート (入力) / AXI4 last read beat (input)
  input                 m_axi_rvalid,                   // AXI4 読み出しデータ有効 (入力) / AXI4 read data valid (input)
  output                m_axi_rready                    // AXI4 読み出しデータを受け取れる (出力) / AXI4 ready for read data (output)
);                                                      // ポート宣言の終わり / end of ports
  // stm_cntl / stm_axi_master とも同期リセット。aresetn は aclk に同期して
  // 解除されるもの (AXI の約束) とし、ここでは同期化しない。
  // stm_cntl and stm_axi_master both use synchronous reset. aresetn is assumed to be released
  // synchronously to aclk (an AXI rule), so it is not synchronised here.
  wire rst = !aresetn;                                  // 正論理のリセット: NOT 1個 (FDREのR端子群へ高ファンアウト) / active-high reset: one NOT (high fan-out to the FDRE R pins)

  wire [3:0]  dd_rad1, dd_rad2, dd_radb, b_ls_rads;     // レジスタ読み出し番号のネット (u_cntl→u_reg) / register read-number nets (u_cntl -> u_reg)
  wire [31:0] gr_dt_1, gr_dt_2, gr_dt_b, gr_dt_s;       // レジスタ読み出しデータのネット (u_reg→u_cntl) / register read-data nets (u_reg -> u_cntl)
  wire        w_we1, w_we2;                             // 書き込み許可のネット / write-enable nets
  wire [3:0]  w_wad1, w_wad2;                           // 書き込み番号のネット / write-number nets
  wire [31:0] w_wdt1, w_wdt2;                           // 書き込みデータのネット / write-data nets
  wire        lbs_we;                                   // オペランドの書き込み (ST2) か (u_cntl→u_axi) / operand write (ST2)? (u_cntl -> u_axi)
  wire [31:0] lbs_ad, lbs_dt, ib_ad;                    // オペランドの番地/データ, フェッチ番地のネット / operand address / data and fetch-address nets
  wire [31:0] mem_dt_op, mem_dt_if_h, mem_dt_if_l;      // オペランドの読み出しデータ (u_axi→u_cntl), 命令 (u_icache→u_cntl) / operand read data (u_axi -> u_cntl), insns (u_icache -> u_cntl)
  wire        ib_valid, op_b_new, op_b_busreq;          // フェッチ要求有効, OP-Bの新要求, バスが要る (u_cntl→外) / fetch valid, new OP-B request, bus needed (u_cntl -> out)
  wire [31:0] ib_ad_nxt;                                // 次のサイクルのIB_AD (u_cntl→u_icacheのRAM番地) / next-cycle IB_AD (u_cntl -> u_icache RAM address)
  wire        if_rdy, op_rdy, op_err;                   // 命令到着, OP完了, OPエラー (→u_cntlのRANDOM_*/MEM_OP_ERR) / insns arrived, OP done, OP error (-> RANDOM_* / MEM_OP_ERR of u_cntl)
  wire        fr_req, fr_ack, fr_valid, fr_last, fr_err; // icache⇔AXIマスタのバースト読み出しの制御線 / burst-read control nets icache <-> AXI master
  wire [31:0] fr_addr, fr_data;                         // バーストの番地とデータ / burst address and data
  wire [7:0]  fr_len;                                   // バースト長-1 / burst length - 1
  wire [1:0]  fr_burst;                                 // バーストの種類 / burst type

  stm_cntl #(.EXT_BUS(1), .IO_EN(IO_EN), .IO_BASE(IO_BASE), .IO_MASK(IO_MASK)) u_cntl ( // CPU本体: EXT_BUS=1で遅いメモリに対応 (フォワード/I/O回路が増える) / CPU core: EXT_BUS=1 for a slow memory (adds forwarding / I/O logic)
    .clk              (aclk),                           // クロック / clock
    .rst              (rst),                            // 同期リセット / synchronous reset
    .RESET_PC         (RESET_PC),                       // 開始番地 / start address
    .RANDOM_FOR_OPCLH (op_rdy),       // OP-B の要求が完了  -- ← u_axiのop_rdy (EXT_BUS=1では「データが揃った」の意味) / <- op_rdy of u_axi ("data ready" with EXT_BUS=1)
                                      // the OP-B request completed
    .RANDOM_FOR_IFRDY (1'b1),                           // フェッチ要求はいつでも受け付け (VCC) / fetch requests always accepted (VCC)
    .RANDOM_FOR_IFCLH (if_rdy),       // 命令フェッチのデータが届いた  -- ← u_icacheのif_rdy / <- if_rdy of u_icache
                                      // the instruction fetch data arrived
    .DD_RAD1          (dd_rad1),                        // R1の読み出し番号 → u_reg / R1 read number -> u_reg
    .DD_RAD2          (dd_rad2),                        // R2の読み出し番号 → u_reg / R2 read number -> u_reg
    .DD_RADB          (dd_radb),                        // RBの読み出し番号 → u_reg / RB read number -> u_reg
    .B_LS_RADS        (b_ls_rads),                      // RSの読み出し番号 → u_reg / RS read number -> u_reg
    .GR_DT_1          (gr_dt_1),                        // R1のデータ ← u_reg / R1 data <- u_reg
    .GR_DT_2          (gr_dt_2),                        // R2のデータ ← u_reg / R2 data <- u_reg
    .GR_DT_B          (gr_dt_b),                        // RBのデータ ← u_reg / RB data <- u_reg
    .GR_DT_S          (gr_dt_s),                        // RSのデータ ← u_reg / RS data <- u_reg
    .W_WE1            (w_we1),                          // LS側の書き込み許可 → u_reg / LS write enable -> u_reg
    .W_WE2            (w_we2),                          // EX側の書き込み許可 → u_reg / EX write enable -> u_reg
    .W_WAD1           (w_wad1),                         // LS側の書き込み番号 / LS write number
    .W_WAD2           (w_wad2),                         // EX側の書き込み番号 / EX write number
    .W_WDT1           (w_wdt1),                         // LS側の書き込みデータ / LS write data
    .W_WDT2           (w_wdt2),                         // EX側の書き込みデータ / EX write data
    .LBS_WE           (lbs_we),                         // OP-Bが書き込みか → u_axi / OP-B is a write -> u_axi
    .LBS_AD           (lbs_ad),                         // OP-Bの番地 → u_axi / OP-B address -> u_axi
    .LBS_DT           (lbs_dt),                         // OP-Bの書き込みデータ → u_axi / OP-B write data -> u_axi
    .MEM_DT_OP        (mem_dt_op),                      // 読み出しデータ ← u_axiのop_dt (FF) / read data <- op_dt of u_axi (FF)
    .MEM_OP_ERR       (op_err),                         // 読み出しエラー ← u_axi → データアクセス例外 / read error <- u_axi -> data access exception
    .IB_AD            (ib_ad),                          // フェッチ番地 → u_icache / fetch address -> u_icache
    .MEM_DT_IF_H      (mem_dt_if_h),                    // 1語目 ← u_icache / first word <- u_icache
    .MEM_DT_IF_L      (mem_dt_if_l),                    // 2語目 ← u_icache / second word <- u_icache
    .IB_VALID         (ib_valid),                       // フェッチ要求有効 → u_icache / fetch valid -> u_icache
    .IB_AD_NXT        (ib_ad_nxt),                      // 次のIB_AD → u_icacheのRAMの読み出し番地 / next IB_AD -> u_icache RAM read address
    .OP_B_NEW         (op_b_new),                       // OP-Bの新要求 → u_axi / new OP-B request -> u_axi
    .OP_B_BUSREQ      (op_b_busreq),                    // バスが要る → u_axi / bus needed -> u_axi
    .PC               (PC)                              // PCを外へ (観測用) / PC out (for observation)
  );                                                    // u_cntlの終わり / end of u_cntl

  stm_regfile u_reg (                                   // レジスタファイル (FF 512本) / register file (512 FFs)
    .clk  (aclk),                                       // クロック / clock
    .we1  (w_we1),   .we2  (w_we2),                     // 書き込み許可2本 / two write enables
    .wad1 (w_wad1),  .wad2 (w_wad2),                    // 書き込み番号2本 / two write numbers
    .wdt1 (w_wdt1),  .wdt2 (w_wdt2),                    // 書き込みデータ2本 / two write data
    .rad1 (dd_rad1), .rad2 (dd_rad2), .radb (dd_radb), .rads (b_ls_rads), // 読み出し番号4本 / four read numbers
    .rdt1 (gr_dt_1), .rdt2 (gr_dt_2), .rdtb (gr_dt_b), .rdts (gr_dt_s) // 読み出しデータ4本 / four read data
  );                                                    // u_regの終わり / end of u_reg

  stm_icache #(.ENABLE(ICACHE), .LINE_W(IC_LINE_W), .SET_W(IC_SET_W), // 命令キャッシュ (パラメータでキャッシュの有無と大きさ) / instruction cache (parameters: on/off and size)
               .IO_EN(IO_EN), .IO_BASE(IO_BASE), .IO_MASK(IO_MASK)) u_icache ( // I/O領域の設定も渡す / also pass the I/O settings
    .clk       (aclk),                                  // クロック / clock
    .rst       (rst),                                   // リセット / reset
    .ib_valid  (ib_valid),                              // フェッチ要求有効 ← u_cntl / fetch valid <- u_cntl
    .ib_ad     (ib_ad),                                 // フェッチ番地 ← u_cntl / fetch address <- u_cntl
    .ib_ad_nxt (ib_ad_nxt),                             // 次のフェッチ番地 ← u_cntl / next fetch address <- u_cntl
    .if_rdy    (if_rdy),                                // 命令が届いた → u_cntlのRANDOM_FOR_IFCLH / insns arrived -> RANDOM_FOR_IFCLH of u_cntl
    .if_dt_h   (mem_dt_if_h),                           // 1語目 → u_cntl / first word -> u_cntl
    .if_dt_l   (mem_dt_if_l),                           // 2語目 → u_cntl / second word -> u_cntl
    .fr_req    (fr_req),                                // バースト要求 → u_axi / burst request -> u_axi
    .fr_addr   (fr_addr),                               // バースト番地 → u_axi / burst address -> u_axi
    .fr_len    (fr_len),                                // バースト長 → u_axi / burst length -> u_axi
    .fr_burst  (fr_burst),                              // バーストの種類 → u_axi / burst type -> u_axi
    .fr_ack    (fr_ack),                                // AR受け付け ← u_axi / AR accepted <- u_axi
    .fr_valid  (fr_valid),                              // ビート到着 ← u_axi / beat arrived <- u_axi
    .fr_data   (fr_data),                               // ビートのデータ ← u_axi / beat data <- u_axi
    .fr_last   (fr_last),                               // 最後のビート ← u_axi / last beat <- u_axi
    .fr_err    (fr_err)                                 // エラー応答 ← u_axi / error response <- u_axi
  );                                                    // u_icacheの終わり / end of u_icache

  stm_axi_master #(                                     // AXI4マスタ (IFとOPを1つのポートへ) / AXI4 master (IF and OP onto one port)
    .ID_W(ID_W), .IF_ID(IF_ID), .OP_ID(OP_ID), .BYTE_SWAP(BYTE_SWAP), // IDとバイト順の設定 / ID and byte-order settings
    .IO_EN(IO_EN), .IO_BASE(IO_BASE), .IO_MASK(IO_MASK) // I/O領域の設定 / I/O settings
  ) u_axi (                                             // インスタンス名 / instance name
    .clk           (aclk),                              // クロック / clock
    .rst           (rst),                               // リセット / reset
    .ifr_req       (fr_req),                            // icacheのバースト要求 / icache burst request
    .ifr_addr      (fr_addr),                           // その番地 / its address
    .ifr_len       (fr_len),                            // その長さ / its length
    .ifr_burst     (fr_burst),                          // その種類 / its type
    .ifr_ack       (fr_ack),                            // AR受け付け → icache / AR accepted -> icache
    .ifr_valid     (fr_valid),                          // ビート到着 → icache / beat arrived -> icache
    .ifr_data      (fr_data),                           // ビートのデータ → icache / beat data -> icache
    .ifr_last      (fr_last),                           // 最後のビート → icache / last beat -> icache
    .ifr_err       (fr_err),                            // エラー応答 → icache / error response -> icache
    .op_new        (op_b_new),                          // OP-Bの新要求 ← u_cntl / new OP-B request <- u_cntl
    .op_busreq     (op_b_busreq),                       // バスが要る ← u_cntl / bus needed <- u_cntl
    .op_we         (lbs_we),                            // 書き込みか ← u_cntl / write? <- u_cntl
    .op_ad         (lbs_ad),                            // 番地 ← u_cntl / address <- u_cntl
    .op_wdt        (lbs_dt),                            // 書き込みデータ ← u_cntl / write data <- u_cntl
    .op_rdy        (op_rdy),                            // 完了 → u_cntl / done -> u_cntl
    .op_dt         (mem_dt_op),                         // 読み出しデータ → u_cntl / read data -> u_cntl
    .op_err        (op_err),                            // エラー → u_cntl / error -> u_cntl
    .bus_error     (bus_error),                         // sticky のエラー表示 → トップのポート / sticky error flag -> top port
    .m_axi_awid    (m_axi_awid),                        // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awaddr  (m_axi_awaddr),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awlen   (m_axi_awlen),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awsize  (m_axi_awsize),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awburst (m_axi_awburst),                     // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awlock  (m_axi_awlock),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awcache (m_axi_awcache),                     // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awprot  (m_axi_awprot),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awqos   (m_axi_awqos),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awvalid (m_axi_awvalid),                     // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_awready (m_axi_awready),                     // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_wdata   (m_axi_wdata),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_wstrb   (m_axi_wstrb),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_wlast   (m_axi_wlast),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_wvalid  (m_axi_wvalid),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_wready  (m_axi_wready),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_bid     (m_axi_bid),                         // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_bresp   (m_axi_bresp),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_bvalid  (m_axi_bvalid),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_bready  (m_axi_bready),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arid    (m_axi_arid),                        // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_araddr  (m_axi_araddr),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arlen   (m_axi_arlen),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arsize  (m_axi_arsize),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arburst (m_axi_arburst),                     // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arlock  (m_axi_arlock),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arcache (m_axi_arcache),                     // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arprot  (m_axi_arprot),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arqos   (m_axi_arqos),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arvalid (m_axi_arvalid),                     // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_arready (m_axi_arready),                     // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_rid     (m_axi_rid),                         // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_rdata   (m_axi_rdata),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_rresp   (m_axi_rresp),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_rlast   (m_axi_rlast),                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_rvalid  (m_axi_rvalid),                      // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
    .m_axi_rready  (m_axi_rready)                       // トップのポートへ直結 (配線のみ) / wired straight to the top-level port
  );                                                    // u_axiの終わり / end of u_axi
endmodule                                               // モジュールの終わり / end of module
