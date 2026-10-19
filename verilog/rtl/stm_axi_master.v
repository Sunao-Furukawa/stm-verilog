// =====================================================================
//  stm_axi_master.v  -  stm_cntl (EXT_BUS=1) のメモリ要求を AXI4 マスタに変換する
//
//  stm_cntl のメモリ側には 2 つの要求元がある:
//    IF : 命令フェッチ。IB_AD の 8 バイト (2 命令) を読む
//         -> AXI4 読み出し 2 ビートのバースト (ARLEN=1, INCR, 4 バイト/ビート)
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
//  ・CPU 側が要求を取り消しても、出してしまった AXI トランザクションは
//    最後まで受け取ってから捨てる (stale)。
//  ・応答はいったんレジスタに受けてから CPU に返す。AXI の入力から CPU への
//    組合せ回路は無い。
//
//  CPU (stm_cntl) との約束:
//    IB_NEW / OP_B_NEW  : 新しい要求が入った最初のサイクルに 1。
//                         要求の切れ目はこれで知る (前の要求の結果は捨てる)。
//    IB_VALID           : フェッチ要求が有効 (取り消されると 0)
//    OP_B_BUSREQ        : OP-B の要求にバスアクセスが要る (組合せ)
//    if_rdy / op_rdy    : 今の要求の結果が揃った。次の要求 (*_NEW) が来るまで保持
//
//  BYTE_SWAP: STM はビッグエンディアン (番地 4n のバイトが語の最上位)。
//    0 : 語をそのままバスに載せる (RDATA[31:24] = 番地 4n のバイト)。
//        メモリを語単位でしか使わないなら、これが一番簡単
//        ($readmemh の語イメージがそのまま使える)。
//    1 : バイトを入れ替える (RDATA[7:0] = 番地 4n のバイト)。AXI の
//        バイトレーンの約束 (番地 4n+k のバイトは [8k+7:8k]) に合わせるので、
//        リトルエンディアンの周辺装置や他のマスタとバイト単位で共有できる。
//
//  RRESP / BRESP がエラー (SLVERR / DECERR) でも CPU には普通に返し、
//  bus_error を 1 にする (sticky, リセットで 0)。CPU にバスエラー例外は無い。
// =====================================================================
module stm_axi_master #(
  parameter ID_W      = 4,
  parameter IF_ID     = 0,          // 命令フェッチの ARID
  parameter OP_ID     = 1,          // オペランドの ARID / AWID
  parameter BYTE_SWAP = 0
) (
  input                 clk,
  input                 rst,        // 同期リセット (1 でリセット)

  // ---- stm_cntl 側: 命令フェッチ
  input                 ib_valid,
  input                 ib_new,
  input      [31:0]     ib_ad,
  output                if_rdy,     // -> RANDOM_FOR_IFCLH
  output reg [31:0]     if_dt_h,    // -> MEM_DT_IF_H (先の命令, 番地 8n)
  output reg [31:0]     if_dt_l,    // -> MEM_DT_IF_L (後の命令, 番地 8n+4)

  // ---- stm_cntl 側: オペランド (S ユニット OP-B)
  input                 op_new,
  input                 op_busreq,
  input                 op_we,      // LBS_WE (1 なら ST2 = 書き込み)
  input      [31:0]     op_ad,      // LBS_AD
  input      [31:0]     op_wdt,     // LBS_DT
  output                op_rdy,     // -> RANDOM_FOR_OPCLH
  output reg [31:0]     op_dt,      // -> MEM_DT_OP

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
  //  命令フェッチ (IF)
  // =================================================================
  reg  [1:0]  if_st;
  reg  [31:0] if_ad_q;      // 出しているアドレス (8 バイト境界)
  reg         if_done;      // 今の要求のデータが if_dt_h/l に揃っている
  reg         if_stale;     // 出しているトランザクションは取り消された要求のもの
  reg         if_beat;      // 0 = 1 ビート目 (H) を待っている, 1 = 2 ビート目 (L)

  // 要求があってまだ結果を持っていなければ出す。IB_NEW のサイクルは
  // 前の要求の if_done が残っているので無視する。
  wire        if_launch = (if_st == S_IDLE) & ib_valid & (!if_done | ib_new);
  wire        if_arv    = if_launch | (if_st == S_ADDR);
  wire [31:0] if_araddr = (if_st == S_ADDR) ? if_ad_q : {ib_ad[31:3], 3'b000};

  assign if_rdy = if_done & !ib_new;

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
  assign m_axi_arlen   = gnt_op ? 8'd0    : 8'd1;     // IF は 2 ビート
  assign m_axi_arsize  = 3'b010;                      // 4 バイト/ビート
  assign m_axi_arburst = 2'b01;                       // INCR
  assign m_axi_arlock  = 1'b0;
  assign m_axi_arcache = 4'b0011;                     // Normal, non-cacheable, bufferable
  assign m_axi_arprot  = gnt_op ? 3'b000 : 3'b100;    // [2]=1: 命令アクセス
  assign m_axi_arqos   = 4'd0;

  wire if_ar_acc = gnt_if & m_axi_arready;
  wire op_ar_acc = gnt_op & m_axi_arready;

  // ---- AW / W (OP の書き込みだけ)
  assign m_axi_awvalid = op_awv;
  assign m_axi_awid    = OPID;
  assign m_axi_awaddr  = op_addr;
  assign m_axi_awlen   = 8'd0;
  assign m_axi_awsize  = 3'b010;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awlock  = 1'b0;
  assign m_axi_awcache = 4'b0011;
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
      if_st     <= S_IDLE;
      if_ad_q   <= 32'd0;
      if_done   <= 1'b0;
      if_stale  <= 1'b0;
      if_beat   <= 1'b0;
      if_dt_h   <= 32'd0;
      if_dt_l   <= 32'd0;
      op_st     <= S_IDLE;
      op_wr_q   <= 1'b0;
      op_ad_q   <= 32'd0;
      op_wdt_q  <= 32'd0;
      op_aw_ok  <= 1'b0;
      op_w_ok   <= 1'b0;
      op_done   <= 1'b0;
      op_stale  <= 1'b0;
      op_dt     <= 32'd0;
      ar_lock   <= 1'b0;
      ar_own_op <= 1'b0;
      bus_error <= 1'b0;
    end else begin
      ar_lock   <= m_axi_arvalid & !m_axi_arready;
      ar_own_op <= gnt_op;

      // ---------------- IF ----------------
      if (ib_new) if_done <= 1'b0;
      if (ib_new && if_st != S_IDLE) if_stale <= 1'b1;

      case (if_st)
        S_IDLE:
          if (if_launch) begin
            if_ad_q  <= if_araddr;
            if_stale <= 1'b0;
            if_beat  <= 1'b0;
            if_st    <= if_ar_acc ? S_RESP : S_ADDR;
          end
        S_ADDR:
          if (if_ar_acc) if_st <= S_RESP;
        default: // S_RESP
          if (r_if) begin
            if (!if_beat) if_dt_h <= lane(m_axi_rdata);
            else          if_dt_l <= lane(m_axi_rdata);
            if_beat <= 1'b1;
            if (m_axi_rlast) begin
              if_st <= S_IDLE;
              // 取り消された要求のデータは捨てる。このサイクルに次の要求が
              // 来た (ib_new) ときも、届いたのは前の要求のデータ。
              if (!if_stale && !ib_new) if_done <= 1'b1;
            end
          end
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
            if (!op_wr_q) op_dt <= lane(m_axi_rdata);
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
