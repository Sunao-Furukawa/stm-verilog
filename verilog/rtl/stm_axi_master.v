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
module stm_axi_master #(                                // AXI4マスタ: icacheのバースト読み出しとSユニットの1語アクセスを1つのAXIポートにまとめる / AXI4 master: merges icache bursts and single-word S-unit accesses onto one AXI port
  parameter ID_W      = 4,                              // AXIのIDの幅 / AXI ID width
  parameter IF_ID     = 0,          // 命令フェッチの ARID
                                    // ARID of instruction fetches
  parameter OP_ID     = 1,          // オペランドの ARID / AWID
                                    // ARID / AWID of operands
  parameter BYTE_SWAP = 0,                              // 1ならバイト順を入れ替える (バスがリトルエンディアンの語の場合) / 1 swaps byte order (for little-endian bus words)
  parameter        IO_EN   = 1,                         // I/O領域のアクセスをDevice属性にする / mark I/O-region accesses as Device
  parameter [31:0] IO_BASE = 32'hF000_0000,             // I/O領域の先頭 / I/O region base
  parameter [31:0] IO_MASK = 32'hF000_0000              // I/O領域の判定マスク / I/O region mask
) (                                                     // パラメータの終わり, ポートの始まり / end of parameters, start of ports
  input                 clk,                            // クロック (aclk) / clock (aclk)
  input                 rst,        // 同期リセット (1 でリセット)
                                    // synchronous reset (1 = reset)

  // ---- stm_icache 側: 命令フェッチのバースト読み出し
  //      (stm_icache side: burst reads for instruction fetch)
  input                 ifr_req,                        // icacheからのバースト読み出し要求 (レベル: 受け付けまで出し続ける) / burst read request from the icache (level, held until accepted)
  input      [31:0]     ifr_addr,                       // バーストの先頭番地 / burst start address
  input      [7:0]      ifr_len,    // ARLEN (ビート数 - 1)
                                    // ARLEN (number of beats - 1)
  input      [1:0]      ifr_burst,  // ARBURST
  output                ifr_ack,    // AR が受け付けられた
                                    // the AR was accepted
  output                ifr_valid,  // ビートが届いた
                                    // a beat arrived
  output     [31:0]     ifr_data,                       // 届いたビートのデータ (RDATAをlane()で並べ替え) / beat data (RDATA through lane())
  output                ifr_last,                       // バーストの最後のビート (RLAST) / last beat of the burst (RLAST)
  output                ifr_err,    // このビートはエラー応答
                                    // this beat is an error response

  // ---- stm_cntl 側: オペランド (S ユニット OP-B)
  //      (stm_cntl side: operands, OP-B of the S unit)
  input                 op_new,                         // OP-Bに新しい要求が入った (stm_cntlのOP_B_NEWのFF) / a new request entered OP-B (OP_B_NEW FF of stm_cntl)
  input                 op_busreq,                      // OP-Bの要求にバスが要る (stm_cntlの組合せ出力) / the OP-B request needs the bus (combinational from stm_cntl)
  input                 op_we,      // LBS_WE (1 なら ST2 = 書き込み)
                                    // LBS_WE (1 = ST2 = write)
  input      [31:0]     op_ad,      // LBS_AD
  input      [31:0]     op_wdt,     // LBS_DT
  output                op_rdy,     // -> RANDOM_FOR_OPCLH
  output reg [31:0]     op_dt,      // -> MEM_DT_OP
  output reg            op_err,     // -> MEM_OP_ERR (読み出しがエラー応答だった)
                                    // -> MEM_OP_ERR (the read got an error response)

  output reg            bus_error,                      // エラー応答を1度でも受けたら1のまま (FF) / sticky 1 once any error response arrives (FF)

  // ---- AXI4 マスタ: 書き込みアドレス
  //      (AXI4 master: write address)
  output     [ID_W-1:0] m_axi_awid,                     // 書き込みアドレスのID (常にOP_ID) / write address ID (always OP_ID)
  output     [31:0]     m_axi_awaddr,                   // 書き込み番地 (語境界) / write address (word aligned)
  output     [7:0]      m_axi_awlen,                    // バースト長-1 (常に0 = 1ビート) / burst length - 1 (always 0 = 1 beat)
  output     [2:0]      m_axi_awsize,                   // 1ビートのサイズ (常に4バイト) / bytes per beat (always 4)
  output     [1:0]      m_axi_awburst,                  // バーストの種類 (INCR) / burst type (INCR)
  output                m_axi_awlock,                   // 排他アクセス無し (0) / no exclusive access (0)
  output     [3:0]      m_axi_awcache,                  // メモリ属性 (I/OはDevice) / memory attributes (Device for I/O)
  output     [2:0]      m_axi_awprot,                   // 保護属性 (データ, 非特権扱い) / protection (data, unprivileged)
  output     [3:0]      m_axi_awqos,                    // QoS (0固定) / QoS (tied to 0)
  output                m_axi_awvalid,                  // 書き込みアドレス有効 (組合せ出力) / write address valid (combinational)
  input                 m_axi_awready,                  // スレーブがアドレスを受け付けた / slave accepts the address
  // ---- 書き込みデータ
  //      (write data)
  output     [31:0]     m_axi_wdata,                    // 書き込みデータ / write data
  output     [3:0]      m_axi_wstrb,                    // バイトストローブ (常に全バイト: CPUは語単位でしか書かない) / byte strobes (always all: the CPU writes whole words)
  output                m_axi_wlast,                    // 最後のビート (1ビートなので常に1) / last beat (always 1, single beat)
  output                m_axi_wvalid,                   // 書き込みデータ有効 / write data valid
  input                 m_axi_wready,                   // スレーブがデータを受け付けた / slave accepts the data
  // ---- 書き込み応答
  //      (write response)
  input      [ID_W-1:0] m_axi_bid,                      // 書き込み応答のID / write response ID
  input      [1:0]      m_axi_bresp,                    // 書き込み応答 (bit1=1ならSLVERR/DECERR) / write response (bit1=1: SLVERR/DECERR)
  input                 m_axi_bvalid,                   // 書き込み応答有効 / write response valid
  output                m_axi_bready,                   // 書き込み応答を受け取れる (常に1) / ready for write responses (always 1)
  // ---- 読み出しアドレス
  //      (read address)
  output     [ID_W-1:0] m_axi_arid,                     // 読み出しアドレスのID (IF_ID/OP_IDで区別) / read address ID (IF_ID or OP_ID)
  output     [31:0]     m_axi_araddr,                   // 読み出し番地 / read address
  output     [7:0]      m_axi_arlen,                    // バースト長-1 (OPは0, IFはicache次第) / burst length - 1 (0 for OP, from the icache for IF)
  output     [2:0]      m_axi_arsize,                   // 1ビート4バイト / 4 bytes per beat
  output     [1:0]      m_axi_arburst,                  // OPはINCR, IFはicacheの指定 (WRAPなど) / INCR for OP, the icache's choice (WRAP etc.) for IF
  output                m_axi_arlock,                   // 排他アクセス無し / no exclusive access
  output     [3:0]      m_axi_arcache,                  // メモリ属性 / memory attributes
  output     [2:0]      m_axi_arprot,                   // 保護属性 (IFは命令アクセス) / protection (instruction access for IF)
  output     [3:0]      m_axi_arqos,                    // QoS (0固定) / QoS (tied to 0)
  output                m_axi_arvalid,                  // 読み出しアドレス有効 (調停の結果) / read address valid (arbitration result)
  input                 m_axi_arready,                  // スレーブがアドレスを受け付けた / slave accepts the address
  // ---- 読み出しデータ
  //      (read data)
  input      [ID_W-1:0] m_axi_rid,                      // 読み出しデータのID (IF/OPの振り分けに使う) / read data ID (used to route to IF / OP)
  input      [31:0]     m_axi_rdata,                    // 読み出しデータ / read data
  input      [1:0]      m_axi_rresp,                    // 読み出し応答 (bit1=1ならエラー) / read response (bit1=1: error)
  input                 m_axi_rlast,                    // バーストの最後 / last beat
  input                 m_axi_rvalid,                   // 読み出しデータ有効 / read data valid
  output                m_axi_rready                    // 読み出しデータを受け取れる (常に1) / ready for read data (always 1)
);                                                      // ポート宣言の終わり / end of ports
  function [31:0] lane;             // CPU の語 <-> バスの語
                                    // CPU word <-> bus word
    input [31:0] d;                                     // 関数の入力 (32bitの語) / function input (a 32-bit word)
    lane = BYTE_SWAP ? {d[7:0], d[15:8], d[23:16], d[31:24]} : d; // バイトの並べ替え: 定数で選ぶので配線の付け替えだけ (LUT 0個) / byte reorder: selected by a constant, so only rewiring (no LUT)
  endfunction                                           // 関数の終わり / end of function

  localparam [ID_W-1:0] IFID = IF_ID;                   // 命令フェッチのID (定数) / ID of instruction fetches (constant)
  localparam [ID_W-1:0] OPID = OP_ID;                   // オペランドのID (定数) / ID of operands (constant)

  // 状態: IDLE = 何もしていない, ADDR = アドレス (と書きデータ) を出している,
  //       RESP = 読み出しデータ / 書き込み応答を待っている
  // States: IDLE = doing nothing, ADDR = driving the address (and write data),
  //         RESP = waiting for the read data / write response
  localparam [1:0] S_IDLE = 2'd0, S_ADDR = 2'd1, S_RESP = 2'd2; // 状態の符号: 2bitの状態FF (if_st, op_st) の値 / state codes: values of the 2-bit state FFs (if_st, op_st)

  // R / B はいつでも受け取れる (各 ID の未完了は高々 1 つなので溢れない)
  // R / B can be accepted at any time (at most 1 outstanding per ID, so they never overflow)
  assign m_axi_rready = 1'b1;                           // 常に受け取れる: VCCに接続 / always ready: tied to VCC
  assign m_axi_bready = 1'b1;                           // 常に受け取れる: VCCに接続 / always ready: tied to VCC

  wire r_hs  = m_axi_rvalid;                  // RREADY=1 なので VALID だけで成立
                                              // RREADY=1, so VALID alone completes the handshake
  wire r_if  = r_hs & (m_axi_rid == IFID);              // 命令フェッチ宛てのRビート: IDの比較 (ID_W bit一致) / R beat for the fetch: ID compare (ID_W-bit match)
  wire r_op  = r_hs & (m_axi_rid == OPID);              // オペランド宛てのRビート / R beat for the operand
  wire b_op  = m_axi_bvalid & (m_axi_bid == OPID);      // オペランドの書き込み応答 / write response for the operand

  // =================================================================
  //  命令フェッチ (IF): stm_icache の要求をそのまま AR に出し, ビートを返す
  //  Instruction fetch (IF): put the request of stm_icache on AR as it is, and return the beats
  // =================================================================
  reg  [1:0]  if_st;                                    // IF側の状態FF (IDLE/ADDR/RESP) / IF-side state FFs (IDLE / ADDR / RESP)
  reg  [31:0] if_ad_q;      // 出しているアドレス
                            // the address being driven
  reg  [7:0]  if_len_q;                                 // 受け付け待ちのARLEN (保持用FF) / ARLEN held while waiting for acceptance (FFs)
  reg  [1:0]  if_burst_q;                               // 受け付け待ちのARBURST / ARBURST held while waiting

  wire        if_launch = (if_st == S_IDLE) & ifr_req;  // IDLEで要求が来た: このサイクルからARを出す (1サイクル早く出すため組合せで直結) / request in IDLE: drive AR from this cycle (combinational so it goes out a cycle early)
  wire        if_arv    = if_launch | (if_st == S_ADDR); // IF側のARVALIDの候補 (調停前) / IF candidate ARVALID (before arbitration)
  wire [31:0] if_araddr = (if_st == S_ADDR) ? if_ad_q    : ifr_addr; // 出す番地: 初回は入力をそのまま, 待ちの間はFF (32bit 2:1 MUX) / address: input on the first cycle, the FF while waiting (32-bit 2:1 mux)
  wire [7:0]  if_arlen  = (if_st == S_ADDR) ? if_len_q   : ifr_len; // 出すARLEN (同じ形のMUX) / ARLEN to drive (same mux)
  wire [1:0]  if_arbst  = (if_st == S_ADDR) ? if_burst_q : ifr_burst; // 出すARBURST / ARBURST to drive

  assign ifr_valid = r_if & (if_st == S_RESP);          // icacheへのビート到着: IDがIFでRESP中 (AND) / beat to the icache: ID is IF and in RESP (AND)
  assign ifr_data  = lane(m_axi_rdata);                 // RDATAをlane()で並べ替えて渡す (配線) / RDATA reordered by lane() (wires)
  assign ifr_last  = m_axi_rlast;                       // RLASTをそのまま / RLAST as is
  assign ifr_err   = m_axi_rresp[1];                    // RRESP[1]=エラー応答 (SLVERR/DECERR) / RRESP[1] = error (SLVERR / DECERR)

  // =================================================================
  //  オペランド (OP)
  //  Operands (OP)
  // =================================================================
  reg  [1:0]  op_st;                                    // OP側の状態FF / OP-side state FFs
  reg         op_wr_q;      // 出しているのは書き込み
                            // what is being driven is a write
  reg  [31:0] op_ad_q;                                  // 出している番地 (FF32本) / address being driven (32 FFs)
  reg  [31:0] op_wdt_q;                                 // 出している書き込みデータ (FF32本) / write data being driven (32 FFs)
  reg         op_aw_ok;     // AW は受け付けられた
                            // the AW has been accepted
  reg         op_w_ok;      // W は受け付けられた
                            // the W has been accepted
  reg         op_done;                                  // この要求の結果を持っている (FF) / the result of this request is held (FF)
  reg         op_stale;                                 // 出している途中で要求が変わった: 応答は捨てる (FF) / request changed while on the bus: drop the response (FF)

  // 【解説】OP の要求をバスに出し始める条件: 何も出しておらず (S_IDLE), バスが要り,
  //         今の要求の結果をまだ持っていない (op_done=0) か新しい要求が来た (op_new)。
  //         op_done は「この要求は済んだ」の FF で、同じ要求を 2 度出さないためのもの。
  // [Note] Condition to start putting an OP request on the bus: nothing is out (S_IDLE), the bus is needed,
  //        and the result of the current request is not held yet (op_done=0) or a new request came (op_new).
  //        op_done is an FF meaning "this request is done", so the same request is not issued twice.
  wire        op_launch = (op_st == S_IDLE) & op_busreq & (!op_done | op_new); // OPをバスに出し始める: IDLEでバスが要り, 結果がまだ無いか新しい要求 / start an OP access: IDLE, bus needed, no result yet or a new request
  wire        op_wr     = (op_st == S_IDLE) ? op_we : op_wr_q; // 書き込みか: IDLEでは入力, それ以外はFF / write?: input in IDLE, else the FF
  wire [31:0] op_addr   = (op_st == S_IDLE) ? {op_ad[31:2], 2'b00} : op_ad_q; // 出す番地 (下位2bitは0に): 32bit 2:1 MUX / address to drive (low 2 bits 0): 32-bit 2:1 mux
  wire [31:0] op_data   = (op_st == S_IDLE) ? op_wdt : op_wdt_q; // 出す書き込みデータ: 32bit 2:1 MUX / write data to drive: 32-bit 2:1 mux
  wire        op_in_addr = op_launch | (op_st == S_ADDR); // アドレス段階にいる (このサイクルに出し始めた分も含む) / in the address phase (including starting this cycle)
  // op_aw_ok / op_w_ok は S_ADDR の間だけ意味を持つ (前の書き込みの値が残っている)
  // op_aw_ok / op_w_ok only mean something during S_ADDR (values of the previous write remain)
  wire        aw_ok     = (op_st == S_ADDR) & op_aw_ok; // AWはもう受け付けられた / AW already accepted
  wire        w_ok      = (op_st == S_ADDR) & op_w_ok;  // Wはもう受け付けられた / W already accepted
  wire        op_arv    = op_in_addr & !op_wr;          // OPの読み出しのARVALID候補 / OP read ARVALID candidate
  wire        op_awv    = op_in_addr &  op_wr & !aw_ok; // AWVALID: 書き込みでAWがまだ / AWVALID: a write whose AW is not yet accepted
  wire        op_wv     = op_in_addr &  op_wr & !w_ok;  // WVALID: 書き込みでWがまだ (AWとWは独立に受け付けられる) / WVALID: a write whose W is not yet accepted (AW and W are accepted independently)

  // 【解説】op_rdy (→ stm_cntl の RANDOM_FOR_OPCLH): 結果が揃っていて, かつ同じサイクルに
  //         新しい要求が入っていない。op_new のサイクルは古い要求の結果なので返さない。
  // [Note] op_rdy (-> RANDOM_FOR_OPCLH of stm_cntl): the result is ready, and no new request entered
  //        in the same cycle. In an op_new cycle the result belongs to the old request, so it is not returned.
  assign op_rdy = op_done & !op_new;                    // stm_cntlへの完了 (RANDOM_FOR_OPCLH): 結果ありで新要求の最初のサイクルでない / completion to stm_cntl (RANDOM_FOR_OPCLH): result held and not the first cycle of a new request
  wire   op_io  = IO_EN && ((op_addr & IO_MASK) == IO_BASE); // 出す番地がI/O領域: 定数マスクの比較 (既定は上位4bitのAND) / the address is in I/O space: constant-mask compare (top-4-bit AND by default)

  // =================================================================
  //  AR チャネルの調停 (OP 優先)。ARVALID を出したまま受け付けられなかったら、
  //  次のサイクルも同じ相手のまま (ar_lock)。
  //  Arbitration of the AR channel (OP first). If ARVALID was raised and not accepted,
  //  the same owner is kept in the next cycle (ar_lock).
  // =================================================================
  reg  ar_lock;                                         // ARVALIDを出したのに受け付けられなかった: 次も同じ相手 (AXIの規則: VALIDを下げない) / ARVALID raised but not accepted: keep the owner (AXI rule: VALID must stay)
  reg  ar_own_op;                                       // 前のサイクルのARの持ち主がOPか / was OP the AR owner last cycle
  wire gnt_op = ar_lock ?  ar_own_op : op_arv;          // ARの使用許可 (OP): ロック中は前の持ち主, そうでなければOP優先 / AR grant (OP): previous owner while locked, else OP first
  wire gnt_if = ar_lock ? !ar_own_op : !op_arv & if_arv; // ARの使用許可 (IF): OPが要らないときだけ / AR grant (IF): only when OP does not need it

  assign m_axi_arvalid = gnt_op | gnt_if;               // ARVALID = どちらかに許可 (OR) / ARVALID = either granted (OR)
  assign m_axi_arid    = gnt_op ? OPID    : IFID;       // ID: 許可された側 (定数の2:1 MUX) / ID of the granted side (2:1 mux of constants)
  assign m_axi_araddr  = gnt_op ? op_addr : if_araddr;  // 番地: 許可された側 (32bit 2:1 MUX) / address of the granted side (32-bit 2:1 mux)
  assign m_axi_arlen   = gnt_op ? 8'd0    : if_arlen;   // 長さ: OPは1ビート, IFはicacheの指定 / length: 1 beat for OP, the icache's for IF
  assign m_axi_arsize  = 3'b010;                      // 4 バイト/ビート
                                                      // 4 bytes per beat
  assign m_axi_arburst = gnt_op ? 2'b01   : if_arbst; // OP は INCR
                                                      // OP uses INCR
  assign m_axi_arlock  = 1'b0;                          // 排他アクセス無し: GND / no exclusive access: GND
  // Normal, non-cacheable, bufferable / I/O 領域は Device, non-bufferable
  // (the I/O region is Device, non-bufferable)
  assign m_axi_arcache = (gnt_op && op_io) ? 4'b0000 : 4'b0011; // OPのI/OアクセスだけDevice(0000), 他はNormal non-cacheable bufferable (0011) / Device (0000) for OP I/O only, else Normal non-cacheable bufferable (0011)
  assign m_axi_arprot  = gnt_op ? 3'b000 : 3'b100;    // [2]=1: 命令アクセス
                                                      // [2]=1: instruction access
  assign m_axi_arqos   = 4'd0;                          // QoS: GND / QoS: GND

  wire if_ar_acc = gnt_if & m_axi_arready;              // IFのARが受け付けられた (ハンドシェイク成立) / IF AR accepted (handshake)
  wire op_ar_acc = gnt_op & m_axi_arready;              // OPのARが受け付けられた / OP AR accepted
  assign ifr_ack = if_ar_acc;                           // icacheへ「ARが受け付けられた」 / tell the icache "AR accepted"

  // ---- AW / W (OP の書き込みだけ)
  //      (AW / W: only for OP writes)
  assign m_axi_awvalid = op_awv;                        // AWVALID = op_awv / AWVALID = op_awv
  assign m_axi_awid    = OPID;                          // 書き込みは常にOPのID (定数) / writes always use the OP ID (constant)
  assign m_axi_awaddr  = op_addr;                       // 書き込み番地 = op_addr / write address = op_addr
  assign m_axi_awlen   = 8'd0;                          // 1ビート (GND) / 1 beat (GND)
  assign m_axi_awsize  = 3'b010;                        // 4バイト/ビート (定数) / 4 bytes per beat (constant)
  assign m_axi_awburst = 2'b01;                         // INCR (定数) / INCR (constant)
  assign m_axi_awlock  = 1'b0;                          // 排他無し (GND) / not exclusive (GND)
  assign m_axi_awcache = op_io ? 4'b0000 : 4'b0011;     // I/OならDevice, 他はNormal / Device for I/O, else Normal
  assign m_axi_awprot  = 3'b000;                        // データ・非特権・セキュア (GND) / data, unprivileged, secure (GND)
  assign m_axi_awqos   = 4'd0;                          // QoS (GND) / QoS (GND)

  assign m_axi_wvalid  = op_wv;                         // WVALID = op_wv / WVALID = op_wv
  assign m_axi_wdata   = lane(op_data);                 // 書き込みデータ (lane()で並べ替え) / write data (reordered by lane())
  assign m_axi_wstrb   = 4'hf;                          // 全バイト書き込み (VCC x4) / write all bytes (4 x VCC)
  assign m_axi_wlast   = 1'b1;                          // 1ビートなので常に最後 (VCC) / single beat, always last (VCC)

  wire aw_acc  = op_awv & m_axi_awready;                // このサイクルにAWが受け付けられた / AW accepted this cycle
  wire w_acc   = op_wv  & m_axi_wready;                 // このサイクルにWが受け付けられた / W accepted this cycle
  // 書き込みのアドレスとデータが両方受け付けられた (このサイクルの分も含む)
  // both the address and the data of the write have been accepted (including this cycle)
  wire wr_sent = (aw_ok | aw_acc) & (w_ok | w_acc);     // 書き込みのAWとWが両方済んだ → RESPへ / both AW and W of the write are done -> to RESP

  // =================================================================
  //  状態の更新
  //  State update
  // =================================================================
  always @(posedge clk) begin                           // 状態FFの更新 (同期リセット) / state FF update (synchronous reset)
    if (rst) begin                                      // リセット: 全FFを初期値に / reset: every FF to its initial value
      if_st      <= S_IDLE;                             // IFはIDLEへ / IF to IDLE
      if_ad_q    <= 32'd0;                              // 0クリア / clear
      if_len_q   <= 8'd0;                               // 0クリア / clear
      if_burst_q <= 2'b01;                              // INCRで初期化 / init to INCR
      op_st     <= S_IDLE;                              // OPはIDLEへ / OP to IDLE
      op_wr_q   <= 1'b0;                                // 0クリア / clear
      op_ad_q   <= 32'd0;                               // 0クリア / clear
      op_wdt_q  <= 32'd0;                               // 0クリア / clear
      op_aw_ok  <= 1'b0;                                // 0クリア / clear
      op_w_ok   <= 1'b0;                                // 0クリア / clear
      op_done   <= 1'b0;                                // 結果無し / no result
      op_stale  <= 1'b0;                                // 捨てる応答無し / nothing to drop
      op_dt     <= 32'd0;                               // 読み出しデータ0 / read data 0
      op_err    <= 1'b0;                                // エラー無し / no error
      ar_lock   <= 1'b0;                                // ロック無し / not locked
      ar_own_op <= 1'b0;                                // 持ち主無し / no owner
      bus_error <= 1'b0;                                // エラー表示を消す / clear the error flag
    end else begin                                      // 通常動作 / normal operation
      ar_lock   <= m_axi_arvalid & !m_axi_arready;      // ARを出して待たされた → 次のサイクルも同じ相手を保つ / AR raised and stalled -> keep the same owner next cycle
      ar_own_op <= gnt_op;                              // 今の持ち主を覚える / remember the current owner

      // ---------------- IF ----------------
      case (if_st)                                      // IF側の状態遷移 (2bitの状態FF + 次状態のLUT) / IF state transitions (2-bit state FFs + next-state LUTs)
        S_IDLE:                                         // 待機中 / idle
          if (if_launch) begin                          // 要求が来た / a request came
            if_ad_q    <= ifr_addr;                     // 番地を保持 (待たされた時に出し続けるため) / hold the address (to keep driving it if stalled)
            if_len_q   <= ifr_len;                      // 長さを保持 / hold the length
            if_burst_q <= ifr_burst;                    // バーストの種類を保持 / hold the burst type
            if_st      <= if_ar_acc ? S_RESP : S_ADDR;  // すぐ受け付けられたらRESP, そうでなければADDRで待つ / RESP if accepted at once, else wait in ADDR
          end                                           // if の終わり / end of if
        S_ADDR:                                         // ARの受け付け待ち / waiting for AR acceptance
          if (if_ar_acc) if_st <= S_RESP;               // 受け付けられたらデータ待ちへ / to data wait once accepted
        default: // S_RESP
          if (r_if && m_axi_rlast) if_st <= S_IDLE;     // (S_RESP) 最後のビートが来たらIDLEへ / (S_RESP) back to IDLE at the last beat
      endcase                                           // IF側の終わり / end of IF side

      // ---------------- OP ----------------
      // 【解説】新しい要求が来たら前の結果は無効。バスに出している途中なら、
      //         その応答は受け取ってから捨てる (op_stale)。
      // [Note] When a new request comes, the previous result is invalid. If it is still on the bus,
      //        its response is received and then dropped (op_stale).
      if (op_new) op_done <= 1'b0;                      // 新しい要求: 前の結果は無効 / new request: the old result is invalid
      if (op_new && op_st != S_IDLE) op_stale <= 1'b1;  // 出している途中なら, その応答は捨てる印を付ける / if still on the bus, mark its response to be dropped

      case (op_st)                                      // OP側の状態遷移 / OP state transitions
        S_IDLE:                                         // 待機中 / idle
          if (op_launch) begin                          // 要求をバスに出し始めた / started a bus access
            op_wr_q  <= op_we;                          // 書き込みかを保持 / hold write?
            op_ad_q  <= op_addr;                        // 番地を保持 (CE付きFF32本) / hold the address (32 FFs with CE)
            op_wdt_q <= op_wdt;                         // 書き込みデータを保持 / hold the write data
            op_stale <= 1'b0;                           // この要求の応答は有効 / this request's response is valid
            op_aw_ok <= aw_acc;                         // このサイクルにAWが受け付けられたか / was AW accepted this cycle
            op_w_ok  <= w_acc;                          // このサイクルにWが受け付けられたか / was W accepted this cycle
            op_st    <= (op_we ? wr_sent : op_ar_acc) ? S_RESP : S_ADDR; // 全部受け付けられたらRESP, そうでなければADDR / RESP if everything accepted, else ADDR
          end                                           // if の終わり / end of if
        S_ADDR:                                         // 受け付け待ち / waiting for acceptance
          if (op_wr_q) begin                            // 書き込み: AWとWを別々に待つ / write: wait for AW and W separately
            if (aw_acc) op_aw_ok <= 1'b1;               // AWが済んだ / AW done
            if (w_acc)  op_w_ok  <= 1'b1;               // Wが済んだ / W done
            if (wr_sent) op_st <= S_RESP;               // 両方済んだらB応答待ちへ / both done -> wait for B
          end else if (op_ar_acc)                       // 読み出し: ARが受け付けられたら ... / read: when AR is accepted ...
            op_st <= S_RESP;                            // ...R待ちへ / ... wait for R
        default: // S_RESP
          if (op_wr_q ? b_op : (r_op & m_axi_rlast)) begin // (S_RESP) 書き込みはB, 読み出しはRの最後のビートで完了 / (S_RESP) done on B for writes, on the last R beat for reads
            if (!op_wr_q) begin                         // 読み出しなら / for a read
              op_dt  <= lane(m_axi_rdata);              // データを保持 → stm_cntlのMEM_DT_OP (FF32本) / keep the data -> MEM_DT_OP of stm_cntl (32 FFs)
              op_err <= m_axi_rresp[1];                 // エラー応答か → MEM_OP_ERR / error response? -> MEM_OP_ERR
            end else                                    // 書き込みなら / for a write
              op_err <= 1'b0;                           // 書き込みのエラーは例外にしない (bus_errorだけ) / write errors raise no exception (bus_error only)
            op_st <= S_IDLE;                            // 待機へ戻る / back to idle
            if (!op_stale && !op_new) op_done <= 1'b1;  // 捨てる応答でなければ「結果あり」 → op_rdy / unless dropped, "result held" -> op_rdy
          end                                           // if の終わり / end of if
      endcase                                           // OP側の終わり / end of OP side

      // ---------------- エラー応答 ----------------
      //               (error responses)
      if ((r_hs && m_axi_rresp[1]) || (m_axi_bvalid && m_axi_bresp[1])) // どれかのRまたはBがエラー応答なら ... / any R or B error response ...
        bus_error <= 1'b1;                              // ...bus_errorを1に (リセットまで保持) → LED等へ / ... sets bus_error (until reset) -> LED etc.
    end                                                 // else の終わり / end of else
  end                                                   // always の終わり / end of always
endmodule                                               // モジュールの終わり / end of module
