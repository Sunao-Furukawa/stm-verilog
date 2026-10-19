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
// =====================================================================
module stm_axi_master #(
  parameter ID_W      = 4,
  parameter IF_ID     = 0,          // 命令フェッチの ARID
  parameter OP_ID     = 1,          // オペランドの ARID / AWID
  parameter BYTE_SWAP = 0,
  parameter        IO_EN   = 1,
  parameter [31:0] IO_BASE = 32'hF000_0000,
  parameter [31:0] IO_MASK = 32'hF000_0000
) (
  input                 clk,
  input                 rst,        // 同期リセット (1 でリセット)

  // ---- stm_icache 側: 命令フェッチのバースト読み出し
  input                 ifr_req,
  input      [31:0]     ifr_addr,
  input      [7:0]      ifr_len,    // ARLEN (ビート数 - 1)
  input      [1:0]      ifr_burst,  // ARBURST
  output                ifr_ack,    // AR が受け付けられた
  output                ifr_valid,  // ビートが届いた
  output     [31:0]     ifr_data,
  output                ifr_last,
  output                ifr_err,    // このビートはエラー応答

  // ---- stm_cntl 側: オペランド (S ユニット OP-B)
  input                 op_new,
  input                 op_busreq,
  input                 op_we,      // LBS_WE (1 なら ST2 = 書き込み)
  input      [31:0]     op_ad,      // LBS_AD
  input      [31:0]     op_wdt,     // LBS_DT
  output                op_rdy,     // -> RANDOM_FOR_OPCLH
  output reg [31:0]     op_dt,      // -> MEM_DT_OP
  output reg            op_err,     // -> MEM_OP_ERR (読み出しがエラー応答だった)

  output reg            bus_error,

  // ---- AXI4 マスタ: 書き込みアドレス
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
  output     [31:0]     m_axi_wdata,
  output     [3:0]      m_axi_wstrb,
  output                m_axi_wlast,
  output                m_axi_wvalid,
  input                 m_axi_wready,
  // ---- 書き込み応答
  input      [ID_W-1:0] m_axi_bid,
  input      [1:0]      m_axi_bresp,
  input                 m_axi_bvalid,
  output                m_axi_bready,
  // ---- 読み出しアドレス
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
  input      [ID_W-1:0] m_axi_rid,
  input      [31:0]     m_axi_rdata,
  input      [1:0]      m_axi_rresp,
  input                 m_axi_rlast,
  input                 m_axi_rvalid,
  output                m_axi_rready
);
  function [31:0] lane;             // CPU の語 <-> バスの語
    input [31:0] d;
    lane = BYTE_SWAP ? {d[7:0], d[15:8], d[23:16], d[31:24]} : d;
  endfunction

  localparam [ID_W-1:0] IFID = IF_ID;
  localparam [ID_W-1:0] OPID = OP_ID;

  // 状態: IDLE = 何もしていない, ADDR = アドレス (と書きデータ) を出している,
  //       RESP = 読み出しデータ / 書き込み応答を待っている
  localparam [1:0] S_IDLE = 2'd0, S_ADDR = 2'd1, S_RESP = 2'd2;

  // R / B はいつでも受け取れる (各 ID の未完了は高々 1 つなので溢れない)
  assign m_axi_rready = 1'b1;
  assign m_axi_bready = 1'b1;

  wire r_hs  = m_axi_rvalid;                  // RREADY=1 なので VALID だけで成立
  wire r_if  = r_hs & (m_axi_rid == IFID);
  wire r_op  = r_hs & (m_axi_rid == OPID);
  wire b_op  = m_axi_bvalid & (m_axi_bid == OPID);

  // =================================================================
  //  命令フェッチ (IF): stm_icache の要求をそのまま AR に出し, ビートを返す
  // =================================================================
  reg  [1:0]  if_st;
  reg  [31:0] if_ad_q;      // 出しているアドレス
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
  // =================================================================
  reg  [1:0]  op_st;
  reg         op_wr_q;      // 出しているのは書き込み
  reg  [31:0] op_ad_q;
  reg  [31:0] op_wdt_q;
  reg         op_aw_ok;     // AW は受け付けられた
  reg         op_w_ok;      // W は受け付けられた
  reg         op_done;
  reg         op_stale;

  wire        op_launch = (op_st == S_IDLE) & op_busreq & (!op_done | op_new);
  wire        op_wr     = (op_st == S_IDLE) ? op_we : op_wr_q;
  wire [31:0] op_addr   = (op_st == S_IDLE) ? {op_ad[31:2], 2'b00} : op_ad_q;
  wire [31:0] op_data   = (op_st == S_IDLE) ? op_wdt : op_wdt_q;
  wire        op_in_addr = op_launch | (op_st == S_ADDR);
  // op_aw_ok / op_w_ok は S_ADDR の間だけ意味を持つ (前の書き込みの値が残っている)
  wire        aw_ok     = (op_st == S_ADDR) & op_aw_ok;
  wire        w_ok      = (op_st == S_ADDR) & op_w_ok;
  wire        op_arv    = op_in_addr & !op_wr;
  wire        op_awv    = op_in_addr &  op_wr & !aw_ok;
  wire        op_wv     = op_in_addr &  op_wr & !w_ok;

  assign op_rdy = op_done & !op_new;
  wire   op_io  = IO_EN && ((op_addr & IO_MASK) == IO_BASE);

  // =================================================================
  //  AR チャネルの調停 (OP 優先)。ARVALID を出したまま受け付けられなかったら、
  //  次のサイクルも同じ相手のまま (ar_lock)。
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
  assign m_axi_arburst = gnt_op ? 2'b01   : if_arbst; // OP は INCR
  assign m_axi_arlock  = 1'b0;
  // Normal, non-cacheable, bufferable / I/O 領域は Device, non-bufferable
  assign m_axi_arcache = (gnt_op && op_io) ? 4'b0000 : 4'b0011;
  assign m_axi_arprot  = gnt_op ? 3'b000 : 3'b100;    // [2]=1: 命令アクセス
  assign m_axi_arqos   = 4'd0;

  wire if_ar_acc = gnt_if & m_axi_arready;
  wire op_ar_acc = gnt_op & m_axi_arready;
  assign ifr_ack = if_ar_acc;

  // ---- AW / W (OP の書き込みだけ)
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
  wire wr_sent = (aw_ok | aw_acc) & (w_ok | w_acc);

  // =================================================================
  //  状態の更新
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
      if ((r_hs && m_axi_rresp[1]) || (m_axi_bvalid && m_axi_bresp[1]))
        bus_error <= 1'b1;
    end
  end
endmodule
