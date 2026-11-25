// =====================================================================
//  stm_axi_master.v  -  stm_cntl (EXT_BUS=1) のメモリ要求を AXI4 マスタに変換する
//
//  メモリ側には 2 つの要求元がある:
//    IF : 命令フェッチ。stm_icache (命令キャッシュ) からのバースト読み出し
//         (ライン埋め, またはキャッシュ無しのときは 8 バイト)。
//         アドレス・長さ・バースト種別は stm_icache が決める
//    OP : S ユニットの OP-B。LD/ST は LBS_AD の 1 語を読み, ST2 は 1 語を書く
//         -> AXI4 読み出し / 書き込み 1 ビート (LEN=0, WSTRB=4'hf)
//  サブワードのストアは CPU 内部で語に組み立ててから ST2 で書くので、
//  バスに出るのは常に 32bit の語アクセスだけ。
//
//  ・読み出しアドレスチャネル (AR) は IF と OP で共用する。OP を優先し、
//    ARVALID を出して受け付けられるまでは相手を変えない (AXI の規則)。
//    ARID は IF=IF_ID, OP=OP_ID とし、R チャネルは RID で振り分ける
//    (ID の違う応答が順不同・インタリーブで返ってきてもよい)。
//  ・IF と OP はそれぞれ同時に 1 トランザクションまで。OP は 1 要求ずつ
//    完了 (読み出しデータ / 書き込み応答 B) を待つので、OP の読み書きの順序は
//    プログラム順のまま保たれる。
//  ・CPU 側が OP の要求を取り消しても、出してしまった AXI トランザクションは
//    最後まで受け取ってから捨てる (stale)。
//  ・OP の応答はいったんレジスタに受けてから CPU に返す。IF のビートは
//    stm_icache がレジスタ (キャッシュの RAM) に受ける。AXI の入力から CPU への
//    組合せ回路は無い。
//
//  stm_icache との約束 (IF):
//    ifr_req             : 読み出し要求 (ifr_addr / ifr_len / ifr_burst)。
//                          ifr_ack (AR が受け付けられた) まで出し続けること。
//                          一度出した要求は取り下げられない。
//    ifr_valid / ifr_last : ビートが届いた / 最後のビート (ifr_data にデータ)
//  CPU (stm_cntl) との約束 (OP):
//    OP_B_NEW            : 新しい要求が入った最初のサイクルに 1。
//                          要求の切れ目はこれで知る (前の要求の結果は捨てる)。
//    OP_B_BUSREQ         : OP-B の要求にバスアクセスが要る (組合せ)
//    op_rdy              : 今の要求の結果が揃った。次の要求 (OP_B_NEW) が来るまで保持
//
//  BYTE_SWAP: STM はビッグエンディアン (番地 4n のバイトが語の最上位)。
//    0 : 語をそのままバスに載せる (RDATA[31:24] = 番地 4n のバイト)。
//        メモリを語単位でしか使わないなら、これが一番簡単
//        ($readmemh の語イメージがそのまま使える)。
//    1 : バイトを入れ替える (RDATA[7:0] = 番地 4n のバイト)。AXI の
//        バイトレーンの約束 (番地 4n+k のバイトは [8k+7:8k]) に合わせるので、
//        リトルエンディアンの周辺装置や他のマスタとバイト単位で共有できる。
//
//  エラー応答 (SLVERR / DECERR):
//    ・OP の読み出し: op_err を op_rdy と一緒に返す。CPU はデータアクセス例外にする
//    ・IF の読み出し: ifr_err をビートと一緒に返す (stm_icache が不正命令に置き換える)
//    ・書き込み (B): CPU は命令を完了済みなので知らせる方法が無い。bus_error だけ
//    どの場合も bus_error を 1 にする (sticky, リセットで 0)。
//
//  I/O 領域 ((番地 & IO_MASK) == IO_BASE, IO_EN=1 のとき) へのアクセスは
//  AxCACHE=4'b0000 (Device, non-bufferable) で出す。それ以外は 4'b0011。
//
//  stm_axi_master.v  -  turns the memory requests of stm_cntl (EXT_BUS=1) into an AXI4 master
//
//  There are two requesters on the memory side:
//    IF : instruction fetch. Burst reads from stm_icache (the instruction cache)
//         (a line fill, or 8 bytes without the cache).
//         stm_icache decides the address, length and burst type
//    OP : OP-B of the S unit. LD/ST read the 1 word at LBS_AD, ST2 writes 1 word
//         -> one AXI4 read / write beat (LEN=0, WSTRB=4'hf)
//  Sub-word stores are assembled into a word inside the CPU and written by ST2, so
//  only 32-bit word accesses ever appear on the bus.
//
//  - The read address channel (AR) is shared by IF and OP. OP has priority, and once
//    ARVALID is raised the owner is not changed until it is accepted (an AXI rule).
//    ARID is IF_ID for IF and OP_ID for OP, and the R channel is split by RID
//    (responses with different IDs may come back out of order or interleaved).
//  - IF and OP each have at most 1 transaction at a time. OP waits for each request to
//    complete (read data / write response B), so OP reads and writes stay in program order.
//  - If the CPU cancels an OP request, an AXI transaction already issued is still received
//    to the end and then dropped (stale).
//  - OP responses are first latched in registers and then returned to the CPU. IF beats are
//    latched by stm_icache in registers (the cache RAMs). There is no combinational path
//    from the AXI inputs to the CPU.
//
//  Contract with stm_icache (IF):
//    ifr_req             : read request (ifr_addr / ifr_len / ifr_burst).
//                          Keep it up until ifr_ack (the AR was accepted).
//                          A request once raised cannot be withdrawn.
//    ifr_valid / ifr_last : a beat arrived / the last beat (data in ifr_data)
//  Contract with the CPU (stm_cntl) (OP):
//    OP_B_NEW            : 1 in the first cycle a new request is in.
//                          This tells where requests start (the previous result is dropped).
//    OP_B_BUSREQ         : the OP-B request needs a bus access (combinational)
//    op_rdy              : the result of the current request is ready. Held until the next request (OP_B_NEW)
//
//  BYTE_SWAP: STM is big-endian (the byte at address 4n is the top of the word).
//    0 : put the word on the bus as it is (RDATA[31:24] = the byte at 4n).
//        If memory is only used in words this is the simplest
//        (the word image of $readmemh can be used as it is).
//    1 : swap the bytes (RDATA[7:0] = the byte at 4n). This follows the AXI byte-lane
//        rule (the byte at 4n+k is [8k+7:8k]), so bytes can be shared with little-endian
//        peripherals and other masters.
//
//  Error responses (SLVERR / DECERR):
//    - OP read: op_err is returned with op_rdy. The CPU makes it a data access exception
//    - IF read: ifr_err is returned with the beat (stm_icache replaces it with an illegal instruction)
//    - write (B): the CPU has already completed the instruction, so there is no way to tell it; only bus_error
//    In every case bus_error becomes 1 (sticky, 0 on reset).
//
//  Accesses to the I/O region ((address & IO_MASK) == IO_BASE, when IO_EN=1) go out
//  with AxCACHE=4'b0000 (Device, non-bufferable); everything else with 4'b0011.
//
// 【ネットリスト解説】
//   ・状態を持つのは IF 側と OP 側の 2 つの小さな状態機械 (if_st, op_st 各 2bit) と、
//     要求の保持用レジスタ (if_ad_q, op_ad_q, op_wdt_q など) だけ。
//     Vivado の結果では FDRE 136 個 + FDSE 3 個, LUT 約 130 個の小さな回路
//     (FDSE はリセット値 1 の FF)。Vivado は if_st / op_st を 2bit の符号のままにせず
//     ワンホット (状態ごとに FF 1 本, FSM_onehot_if_st_reg[0..2]) に置き換えている。
//     リセットで S_IDLE の FF だけ 1 になるので、それと if_burst_q[0] (リセット値 1)
//     が FDSE になる。
//   ・AXI の出力はほとんどが組合せ出力。例えば
//       m_axi_araddr = gnt_op ? op_addr : if_araddr
//       op_addr      = (op_st == S_IDLE) ? {op_ad[31:2], 2'b00} : op_ad_q
//     なので、要求を受けた最初のサイクル (S_IDLE) は stm_cntl の LBS_AD の FF が
//     そのまま ARADDR に出る (1 サイクル早く出せる)。受け付けられなかったら
//     op_ad_q の FF に保持した値を出し続ける (AXI の「VALID 中は内容を変えない」)。
//   ・AR の調停 (gnt_op / gnt_if) は ar_lock / ar_own_op の 2 つの FF と
//     op_arv / if_arv の組合せ。m_axi_arready は ar_lock の FF の D 入力、
//     if_st / op_st の次状態、ifr_ack (→ stm_icache の状態機械) にしか入らない
//     (AXI 入力 → FF の短い経路で、stm_cntl までは届かない)。
//   ・R チャネルは m_axi_rid の比較 (r_if / r_op) で IF 側と OP 側に振り分ける。
//     IF 側は組合せのまま stm_icache へ (ifr_valid / ifr_data), OP 側は op_dt /
//     op_err の FF に受けてから stm_cntl へ返す。
//   ・BYTE_SWAP はパラメータなので lane() はバイトの並べ替え (配線) か素通し。
//
// [Netlist notes]
//   - The only state is two small state machines for the IF side and the OP side
//     (if_st, op_st, 2 bits each) and registers that hold the requests (if_ad_q, op_ad_q,
//     op_wdt_q etc.). In the Vivado result it is a small circuit of 136 FDRE + 3 FDSE and about
//     130 LUTs (an FDSE is an FF with reset value 1). Vivado does not keep if_st / op_st as
//     2-bit codes; it re-encodes them as one-hot (one FF per state, FSM_onehot_if_st_reg[0..2]).
//     On reset only the S_IDLE FF becomes 1, so it and if_burst_q[0] (reset value 1) are FDSEs.
//   - Most AXI outputs are combinational outputs. For example
//       m_axi_araddr = gnt_op ? op_addr : if_araddr
//       op_addr      = (op_st == S_IDLE) ? {op_ad[31:2], 2'b00} : op_ad_q
//     so in the first cycle of a request (S_IDLE) the LBS_AD FFs of stm_cntl appear directly
//     on ARADDR (it goes out one cycle earlier). If it is not accepted, the value held in the
//     op_ad_q FFs keeps being driven (AXI's "do not change the contents while VALID").
//   - AR arbitration (gnt_op / gnt_if) is the two FFs ar_lock / ar_own_op plus the logic of
//     op_arv / if_arv. m_axi_arready only goes into the D input of the ar_lock FF, the next
//     state of if_st / op_st and ifr_ack (-> the state machine of stm_icache)
//     (short AXI input -> FF paths; it never reaches stm_cntl).
//   - The R channel is split between the IF side and the OP side by comparing m_axi_rid
//     (r_if / r_op). The IF side goes combinationally to stm_icache (ifr_valid / ifr_data);
//     the OP side is first latched in the op_dt / op_err FFs and then returned to stm_cntl.
//   - BYTE_SWAP is a parameter, so lane() is either a byte reordering (wires) or a pass-through.
// =====================================================================
module stm_axi_master #(
  parameter ID_W      = 4,
  parameter IF_ID     = 0,          // 命令フェッチの ARID
                                    // ARID of instruction fetches
  parameter OP_ID     = 1,          // オペランドの ARID / AWID
                                    // ARID / AWID of operands
  parameter BYTE_SWAP = 0,
  parameter        IO_EN   = 1,
  parameter [31:0] IO_BASE = 32'hF000_0000,
  parameter [31:0] IO_MASK = 32'hF000_0000
) (
  input                 clk,
  input                 rst,        // 同期リセット (1 でリセット)
                                    // synchronous reset (1 = reset)

  // ---- stm_icache 側: 命令フェッチのバースト読み出し
  //      (stm_icache side: burst reads for instruction fetch)
  input                 ifr_req,
  input      [31:0]     ifr_addr,
  input      [7:0]      ifr_len,    // ARLEN (ビート数 - 1)
                                    // ARLEN (number of beats - 1)
  input      [1:0]      ifr_burst,  // ARBURST
  output                ifr_ack,    // AR が受け付けられた
                                    // the AR was accepted
  output                ifr_valid,  // ビートが届いた
                                    // a beat arrived
  output     [31:0]     ifr_data,
  output                ifr_last,
  output                ifr_err,    // このビートはエラー応答
                                    // this beat is an error response

  // ---- stm_cntl 側: オペランド (S ユニット OP-B)
  //      (stm_cntl side: operands, OP-B of the S unit)
  input                 op_new,
  input                 op_busreq,
  input                 op_we,      // LBS_WE (1 なら ST2 = 書き込み)
                                    // LBS_WE (1 = ST2 = write)
  input      [31:0]     op_ad,      // LBS_AD
  input      [31:0]     op_wdt,     // LBS_DT
  output                op_rdy,     // -> RANDOM_FOR_OPCLH
  output reg [31:0]     op_dt,      // -> MEM_DT_OP
  output reg            op_err,     // -> MEM_OP_ERR (読み出しがエラー応答だった)
                                    // -> MEM_OP_ERR (the read got an error response)

  output reg            bus_error,

  // ---- AXI4 マスタ: 書き込みアドレス
  //      (AXI4 master: write address)
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
  // ---- 書き込みデータ
  //      (write data)
  output     [31:0]     m_axi_wdata,
  output     [3:0]      m_axi_wstrb,
  output                m_axi_wlast,
  output                m_axi_wvalid,
  input                 m_axi_wready,
  // ---- 書き込み応答
  //      (write response)
  input      [ID_W-1:0] m_axi_bid,
  input      [1:0]      m_axi_bresp,
  input                 m_axi_bvalid,
  output                m_axi_bready,
  // ---- 読み出しアドレス
  //      (read address)
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
  // ---- 読み出しデータ
  //      (read data)
  input      [ID_W-1:0] m_axi_rid,
  input      [31:0]     m_axi_rdata,
  input      [1:0]      m_axi_rresp,
  input                 m_axi_rlast,
  input                 m_axi_rvalid,
  output                m_axi_rready
);
  function [31:0] lane;             // CPU の語 <-> バスの語
                                    // CPU word <-> bus word
    input [31:0] d;
    lane = BYTE_SWAP ? {d[7:0], d[15:8], d[23:16], d[31:24]} : d;
  endfunction

  localparam [ID_W-1:0] IFID = IF_ID;
  localparam [ID_W-1:0] OPID = OP_ID;

  // 状態: IDLE = 何もしていない, ADDR = アドレス (と書きデータ) を出している,
  //       RESP = 読み出しデータ / 書き込み応答を待っている
  // States: IDLE = doing nothing, ADDR = driving the address (and write data),
  //         RESP = waiting for the read data / write response
  localparam [1:0] S_IDLE = 2'd0, S_ADDR = 2'd1, S_RESP = 2'd2;

  // R / B はいつでも受け取れる (各 ID の未完了は高々 1 つなので溢れない)
  // R / B can be accepted at any time (at most 1 outstanding per ID, so they never overflow)
  assign m_axi_rready = 1'b1;
  assign m_axi_bready = 1'b1;

  wire r_hs  = m_axi_rvalid;                  // RREADY=1 なので VALID だけで成立
                                              // RREADY=1, so VALID alone completes the handshake
  wire r_if  = r_hs & (m_axi_rid == IFID);
  wire r_op  = r_hs & (m_axi_rid == OPID);
  wire b_op  = m_axi_bvalid & (m_axi_bid == OPID);

  // =================================================================
  //  命令フェッチ (IF): stm_icache の要求をそのまま AR に出し, ビートを返す
  //  Instruction fetch (IF): put the request of stm_icache on AR as it is, and return the beats
  // =================================================================
  reg  [1:0]  if_st;
  reg  [31:0] if_ad_q;      // 出しているアドレス
                            // the address being driven
  reg  [7:0]  if_len_q;
  reg  [1:0]  if_burst_q;

  wire        if_launch = (if_st == S_IDLE) & ifr_req;
  wire        if_arv    = if_launch | (if_st == S_ADDR);
  wire [31:0] if_araddr = (if_st == S_ADDR) ? if_ad_q    : ifr_addr;
  wire [7:0]  if_arlen  = (if_st == S_ADDR) ? if_len_q   : ifr_len;
  wire [1:0]  if_arbst  = (if_st == S_ADDR) ? if_burst_q : ifr_burst;

  assign ifr_valid = r_if & (if_st == S_RESP);
  assign ifr_data  = lane(m_axi_rdata);
  assign ifr_last  = m_axi_rlast;
  assign ifr_err   = m_axi_rresp[1];

  // =================================================================
  //  オペランド (OP)
  //  Operands (OP)
  // =================================================================
  reg  [1:0]  op_st;
  reg         op_wr_q;      // 出しているのは書き込み
                            // what is being driven is a write
  reg  [31:0] op_ad_q;
  reg  [31:0] op_wdt_q;
  reg         op_aw_ok;     // AW は受け付けられた
                            // the AW has been accepted
  reg         op_w_ok;      // W は受け付けられた
                            // the W has been accepted
  reg         op_done;
  reg         op_stale;

  // 【解説】OP の要求をバスに出し始める条件: 何も出しておらず (S_IDLE), バスが要り,
  //         今の要求の結果をまだ持っていない (op_done=0) か新しい要求が来た (op_new)。
  //         op_done は「この要求は済んだ」の FF で、同じ要求を 2 度出さないためのもの。
  // [Note] Condition to start putting an OP request on the bus: nothing is out (S_IDLE), the bus is needed,
  //        and the result of the current request is not held yet (op_done=0) or a new request came (op_new).
  //        op_done is an FF meaning "this request is done", so the same request is not issued twice.
  wire        op_launch = (op_st == S_IDLE) & op_busreq & (!op_done | op_new);
  wire        op_wr     = (op_st == S_IDLE) ? op_we : op_wr_q;
  wire [31:0] op_addr   = (op_st == S_IDLE) ? {op_ad[31:2], 2'b00} : op_ad_q;
  wire [31:0] op_data   = (op_st == S_IDLE) ? op_wdt : op_wdt_q;
  wire        op_in_addr = op_launch | (op_st == S_ADDR);
  // op_aw_ok / op_w_ok は S_ADDR の間だけ意味を持つ (前の書き込みの値が残っている)
  // op_aw_ok / op_w_ok only mean something during S_ADDR (values of the previous write remain)
  wire        aw_ok     = (op_st == S_ADDR) & op_aw_ok;
  wire        w_ok      = (op_st == S_ADDR) & op_w_ok;
  wire        op_arv    = op_in_addr & !op_wr;
  wire        op_awv    = op_in_addr &  op_wr & !aw_ok;
  wire        op_wv     = op_in_addr &  op_wr & !w_ok;

  // 【解説】op_rdy (→ stm_cntl の RANDOM_FOR_OPCLH): 結果が揃っていて, かつ同じサイクルに
  //         新しい要求が入っていない。op_new のサイクルは古い要求の結果なので返さない。
  // [Note] op_rdy (-> RANDOM_FOR_OPCLH of stm_cntl): the result is ready, and no new request entered
  //        in the same cycle. In an op_new cycle the result belongs to the old request, so it is not returned.
  assign op_rdy = op_done & !op_new;
  wire   op_io  = IO_EN && ((op_addr & IO_MASK) == IO_BASE);

  // =================================================================
  //  AR チャネルの調停 (OP 優先)。ARVALID を出したまま受け付けられなかったら、
  //  次のサイクルも同じ相手のまま (ar_lock)。
  //  Arbitration of the AR channel (OP first). If ARVALID was raised and not accepted,
  //  the same owner is kept in the next cycle (ar_lock).
  // =================================================================
  reg  ar_lock;
  reg  ar_own_op;
  wire gnt_op = ar_lock ?  ar_own_op : op_arv;
  wire gnt_if = ar_lock ? !ar_own_op : !op_arv & if_arv;

  assign m_axi_arvalid = gnt_op | gnt_if;
  assign m_axi_arid    = gnt_op ? OPID    : IFID;
  assign m_axi_araddr  = gnt_op ? op_addr : if_araddr;
  assign m_axi_arlen   = gnt_op ? 8'd0    : if_arlen;
  assign m_axi_arsize  = 3'b010;                      // 4 バイト/ビート
                                                      // 4 bytes per beat
  assign m_axi_arburst = gnt_op ? 2'b01   : if_arbst; // OP は INCR
                                                      // OP uses INCR
  assign m_axi_arlock  = 1'b0;
  // Normal, non-cacheable, bufferable / I/O 領域は Device, non-bufferable
  // (the I/O region is Device, non-bufferable)
  assign m_axi_arcache = (gnt_op && op_io) ? 4'b0000 : 4'b0011;
  assign m_axi_arprot  = gnt_op ? 3'b000 : 3'b100;    // [2]=1: 命令アクセス
                                                      // [2]=1: instruction access
  assign m_axi_arqos   = 4'd0;

  wire if_ar_acc = gnt_if & m_axi_arready;
  wire op_ar_acc = gnt_op & m_axi_arready;
  assign ifr_ack = if_ar_acc;

  // ---- AW / W (OP の書き込みだけ)
  //      (AW / W: only for OP writes)
  assign m_axi_awvalid = op_awv;
  assign m_axi_awid    = OPID;
  assign m_axi_awaddr  = op_addr;
  assign m_axi_awlen   = 8'd0;
  assign m_axi_awsize  = 3'b010;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awlock  = 1'b0;
  assign m_axi_awcache = op_io ? 4'b0000 : 4'b0011;
  assign m_axi_awprot  = 3'b000;
  assign m_axi_awqos   = 4'd0;

  assign m_axi_wvalid  = op_wv;
  assign m_axi_wdata   = lane(op_data);
  assign m_axi_wstrb   = 4'hf;
  assign m_axi_wlast   = 1'b1;

  wire aw_acc  = op_awv & m_axi_awready;
  wire w_acc   = op_wv  & m_axi_wready;
  // 書き込みのアドレスとデータが両方受け付けられた (このサイクルの分も含む)
  // both the address and the data of the write have been accepted (including this cycle)
  wire wr_sent = (aw_ok | aw_acc) & (w_ok | w_acc);

  // =================================================================
  //  状態の更新
  //  State update
  // =================================================================
  always @(posedge clk) begin
    if (rst) begin
      if_st      <= S_IDLE;
      if_ad_q    <= 32'd0;
      if_len_q   <= 8'd0;
      if_burst_q <= 2'b01;
      op_st     <= S_IDLE;
      op_wr_q   <= 1'b0;
      op_ad_q   <= 32'd0;
      op_wdt_q  <= 32'd0;
      op_aw_ok  <= 1'b0;
      op_w_ok   <= 1'b0;
      op_done   <= 1'b0;
      op_stale  <= 1'b0;
      op_dt     <= 32'd0;
      op_err    <= 1'b0;
      ar_lock   <= 1'b0;
      ar_own_op <= 1'b0;
      bus_error <= 1'b0;
    end else begin
      ar_lock   <= m_axi_arvalid & !m_axi_arready;
      ar_own_op <= gnt_op;

      // ---------------- IF ----------------
      case (if_st)
        S_IDLE:
          if (if_launch) begin
            if_ad_q    <= ifr_addr;
            if_len_q   <= ifr_len;
            if_burst_q <= ifr_burst;
            if_st      <= if_ar_acc ? S_RESP : S_ADDR;
          end
        S_ADDR:
          if (if_ar_acc) if_st <= S_RESP;
        default: // S_RESP
          if (r_if && m_axi_rlast) if_st <= S_IDLE;
      endcase

      // ---------------- OP ----------------
      // 【解説】新しい要求が来たら前の結果は無効。バスに出している途中なら、
      //         その応答は受け取ってから捨てる (op_stale)。
      // [Note] When a new request comes, the previous result is invalid. If it is still on the bus,
      //        its response is received and then dropped (op_stale).
      if (op_new) op_done <= 1'b0;
      if (op_new && op_st != S_IDLE) op_stale <= 1'b1;

      case (op_st)
        S_IDLE:
          if (op_launch) begin
            op_wr_q  <= op_we;
            op_ad_q  <= op_addr;
            op_wdt_q <= op_wdt;
            op_stale <= 1'b0;
            op_aw_ok <= aw_acc;
            op_w_ok  <= w_acc;
            op_st    <= (op_we ? wr_sent : op_ar_acc) ? S_RESP : S_ADDR;
          end
        S_ADDR:
          if (op_wr_q) begin
            if (aw_acc) op_aw_ok <= 1'b1;
            if (w_acc)  op_w_ok  <= 1'b1;
            if (wr_sent) op_st <= S_RESP;
          end else if (op_ar_acc)
            op_st <= S_RESP;
        default: // S_RESP
          if (op_wr_q ? b_op : (r_op & m_axi_rlast)) begin
            if (!op_wr_q) begin
              op_dt  <= lane(m_axi_rdata);
              op_err <= m_axi_rresp[1];
            end else
              op_err <= 1'b0;
            op_st <= S_IDLE;
            if (!op_stale && !op_new) op_done <= 1'b1;
          end
      endcase

      // ---------------- エラー応答 ----------------
      //               (error responses)
      if ((r_hs && m_axi_rresp[1]) || (m_axi_bvalid && m_axi_bresp[1]))
        bus_error <= 1'b1;
    end
  end
endmodule
