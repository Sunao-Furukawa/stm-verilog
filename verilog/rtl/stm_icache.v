// =====================================================================
//  stm_icache.v  -  命令キャッシュ (stm_cntl の命令フェッチ <-> stm_axi_master)
//
//  ダイレクトマップ, ライン 2^LINE_W バイト, 2^SET_W ライン
//  (既定 32 バイト x 128 = 4KB)。読み出し専用で、ストアとの一貫性は取らない
//  (自己書き換えコードは非対応)。
//
//  ・CPU は 8 バイト (2 命令) 単位でフェッチする (IB_AD, IB_V)。
//    データ RAM は 64bit 幅で 1 エントリ = 8 バイト。
//  ・ヒット: RAM は CPU の「次のサイクルの IB_AD」(IB_AD_NXT) で 1 サイクル先に
//    引いておくので、要求の次のサイクルに if_rdy を返せる。これは元の
//    stm_memory (同じサイクルに応答) と同じタイミングで、ヒットする限り
//    CPU は元の設計と同じサイクル数で動く。
//  ・ミス: そのラインを AXI4 の WRAP バーストで埋める。要求した 8 バイトから
//    読み始め、その 2 ビートが届いた時点で CPU に返す (early restart)。
//    続く 8 バイトも届いた順に CPU へ流す (順に実行していくコードなら、
//    ラインを埋め終わるのを待たずに次の命令が届く)。それ以外のヒットは
//    ラインを埋め終わってから返す。
//  ・CPU が要求を取り消しても、始めたライン埋めは最後まで行う (無駄にならない)。
//    要求はアドレスで照合するので、CPU 側から要求の切れ目を教わる必要は無い。
//
//  ENABLE=0 にするとキャッシュを持たず、毎回 8 バイト (2 ビートの INCR) を
//  読む (キャッシュ追加前と同じ動作)。
//
//  RAM はどちらも「書き 1 ポート + 読み 1 ポート, 読み出しはクロック同期」の
//  形で書いてあるので、FPGA のブロック RAM になる。有効ビットだけは FF。
//
//  フェッチできない番地の扱い: 次の場合は命令の代わりに不正命令 ILL_INSN
//  (0xE0000000。先頭 4bit が 14 の命令は無い) を CPU に返す。
//    ・I/O 領域 ((番地 & IO_MASK) == IO_BASE, IO_EN=1): バスには出さない
//      (命令の先読みで I/O を読まないため)
//    ・バスがエラー応答を返した 8 バイト: そのラインはキャッシュに残さない
//  その命令を実際に実行すると不正命令例外 (INTCODE_OP) になり、XPC にその番地が
//  残る。予測ミス側の先読みなら取り消されるだけで何も起きない。
// =====================================================================
module stm_icache #(
  parameter ENABLE = 1,
  parameter LINE_W = 5,             // ライン長 = 2^LINE_W バイト (4〜6: 16〜64 バイト)
  parameter SET_W  = 7,             // ライン数 = 2^SET_W (1 以上)
  parameter        IO_EN   = 1,
  parameter [31:0] IO_BASE = 32'hF000_0000,
  parameter [31:0] IO_MASK = 32'hF000_0000
) (
  input             clk,
  input             rst,

  // ---- stm_cntl 側
  input             ib_valid,       // IB_VALID
  input      [31:0] ib_ad,          // IB_AD
  input      [31:0] ib_ad_nxt,      // IB_AD_NXT (次のサイクルの IB_AD)
  output            if_rdy,         // -> RANDOM_FOR_IFCLH
  output     [31:0] if_dt_h,        // -> MEM_DT_IF_H (先の命令, 番地 8n)
  output     [31:0] if_dt_l,        // -> MEM_DT_IF_L (後の命令, 番地 8n+4)

  // ---- stm_axi_master 側 (バースト読み出し)
  output            fr_req,
  output     [31:0] fr_addr,
  output     [7:0]  fr_len,
  output     [1:0]  fr_burst,
  input             fr_ack,
  input             fr_valid,
  input      [31:0] fr_data,
  input             fr_last,
  input             fr_err          // このビートはエラー応答
);
  localparam [31:0] ILL_INSN = 32'hE000_0000;

  // I/O 領域からはフェッチしない (すぐに不正命令を返す)
  wire       io_hit  = ib_valid & IO_EN & ((ib_ad & IO_MASK) == IO_BASE);

  // 直前に届いた 8 バイト (early restart / キャッシュ無しのときのデータ)
  reg        byp_v;
  reg [28:0] byp_ad;                // 番地 [31:3]
  reg [31:0] byp_h, byp_l;
  wire       byp_hit = ib_valid & byp_v & (byp_ad == ib_ad[31:3]);

generate
if (ENABLE) begin : g_cache
  localparam WORDS  = 1 << (LINE_W - 2);       // ラインの語数 (= ビート数)
  localparam UNIT_W = LINE_W - 3;              // ライン内の 8 バイト単位の番号の幅
  localparam TAG_W  = 32 - LINE_W - SET_W;
  localparam DEP_W  = SET_W + UNIT_W;

  localparam [1:0] F_IDLE = 2'd0, F_REQ = 2'd1, F_DATA = 2'd2, F_DONE = 2'd3;

  reg [63:0]       dram [0:(1<<DEP_W)-1];      // {H, L}
  reg [TAG_W-1:0]  tram [0:(1<<SET_W)-1];
  reg [(1<<SET_W)-1:0] vbits;
  reg [63:0]       d_q;
  reg [TAG_W-1:0]  t_q;

  reg  [1:0]        fst;
  reg  [28:0]       f_ad;                       // 埋めているラインの要求番地 [31:3]
  reg  [LINE_W-3:0] f_beat;                     // 何ビート目か
  reg  [31:0]       f_hw;                       // 8 バイトの前半 (H) を待たせる
  reg               f_herr;                     // 前半がエラー応答だった
  reg               f_err;                      // このライン埋めでエラー応答があった

  wire [SET_W-1:0]  ib_idx   = ib_ad[LINE_W+SET_W-1:LINE_W];
  wire [TAG_W-1:0]  ib_tag   = ib_ad[31:LINE_W+SET_W];
  wire [SET_W-1:0]  f_idx    = f_ad[LINE_W+SET_W-4:LINE_W-3];
  wire [TAG_W-1:0]  f_tag    = f_ad[28:LINE_W+SET_W-3];
  // このビートのライン内の語番号 (WRAP なので要求した語から回る)
  wire [LINE_W-3:0] f_word   = {f_ad[LINE_W-4:0], 1'b0} + f_beat;

  // ---- RAM (読み出しは IB_AD_NXT で 1 サイクル先に)
  wire [DEP_W-1:0] rd_a = {ib_ad_nxt[LINE_W+SET_W-1:LINE_W], ib_ad_nxt[LINE_W-1:3]};
  wire             d_we = (fst == F_DATA) & fr_valid & f_word[0];
  wire [DEP_W-1:0] d_wa = {f_idx, f_word[LINE_W-3:1]};
  wire             t_we = (fst == F_DATA) & fr_valid & fr_last;

  always @(posedge clk) begin
    if (d_we) dram[d_wa] <= {f_hw, fr_data};
    d_q <= dram[rd_a];
  end
  always @(posedge clk) begin
    if (t_we) tram[f_idx] <= f_tag;
    t_q <= tram[rd_a[DEP_W-1:UNIT_W]];
  end

  // ---- ヒット判定。ライン埋めの間と直後の 1 サイクル (RAM の読み出しが
  //      書き込みと重なって古い値かもしれない) はヒットにしない。
  wire hit        = ib_valid & (fst == F_IDLE) & vbits[ib_idx] & (t_q == ib_tag);
  wire miss_start = ib_valid & (fst == F_IDLE) & !hit & !byp_hit & !io_hit;
  wire pair_err   = f_herr | fr_err;            // この 8 バイトのどちらかがエラー

  assign if_rdy   = hit | byp_hit | io_hit;
  assign if_dt_h  = io_hit ? ILL_INSN : byp_hit ? byp_h : d_q[63:32];
  assign if_dt_l  = io_hit ? ILL_INSN : byp_hit ? byp_l : d_q[31:0];

  assign fr_req   = miss_start | (fst == F_REQ);
  assign fr_addr  = (fst == F_REQ) ? {f_ad, 3'b000} : {ib_ad[31:3], 3'b000};
  assign fr_len   = WORDS - 1;
  assign fr_burst = 2'b10;                      // WRAP

  always @(posedge clk) begin
    if (rst) begin
      fst    <= F_IDLE;
      vbits  <= 0;
      byp_v  <= 1'b0;
      f_ad   <= 29'd0;
      f_beat <= 0;
      f_hw   <= 32'd0;
      f_herr <= 1'b0;
      f_err  <= 1'b0;
    end else begin
      case (fst)
        F_IDLE:
          if (miss_start) begin
            f_ad          <= ib_ad[31:3];
            f_beat        <= 0;
            f_err         <= 1'b0;
            byp_v         <= 1'b0;
            vbits[ib_idx] <= 1'b0;
            fst           <= fr_ack ? F_DATA : F_REQ;
          end
        F_REQ:
          if (fr_ack) fst <= F_DATA;
        F_DATA:
          if (fr_valid) begin
            f_beat <= f_beat + 1'b1;
            if (fr_err) f_err <= 1'b1;
            if (!f_word[0]) begin
              f_hw   <= fr_data;
              f_herr <= fr_err;
            end
            // 8 バイト揃うごとに CPU へ流す (最初は要求したもの)。
            // エラー応答なら不正命令に置き換える。
            if (f_word[0]) begin
              byp_v  <= 1'b1;
              byp_ad <= {f_ad[28:LINE_W-3], f_word[LINE_W-3:1]};
              byp_h  <= pair_err ? ILL_INSN : f_hw;
              byp_l  <= pair_err ? ILL_INSN : fr_data;
            end
            if (fr_last) begin
              // エラー応答のあったラインは有効にしない (次も読み直す)
              vbits[f_idx] <= !(f_err | fr_err);
              fst          <= F_DONE;
            end
          end
        default: // F_DONE
          fst <= F_IDLE;
      endcase
    end
  end
end else begin : g_nocache
  // ---- キャッシュ無し: 毎回 8 バイトを読み, CPU が受け取ったら捨てる
  localparam [1:0] N_IDLE = 2'd0, N_REQ = 2'd1, N_DATA = 2'd2;
  reg  [1:0]  nst;
  reg  [28:0] n_ad;
  reg         n_beat;
  reg         n_err;

  wire start = ib_valid & (nst == N_IDLE) & !byp_hit & !io_hit;

  assign if_rdy   = byp_hit | io_hit;
  assign if_dt_h  = io_hit ? ILL_INSN : byp_h;
  assign if_dt_l  = io_hit ? ILL_INSN : byp_l;

  assign fr_req   = start | (nst == N_REQ);
  assign fr_addr  = (nst == N_REQ) ? {n_ad, 3'b000} : {ib_ad[31:3], 3'b000};
  assign fr_len   = 8'd1;                       // 2 ビート
  assign fr_burst = 2'b01;                      // INCR

  always @(posedge clk) begin
    if (rst) begin
      nst    <= N_IDLE;
      byp_v  <= 1'b0;
      n_ad   <= 29'd0;
      n_beat <= 1'b0;
      n_err  <= 1'b0;
    end else begin
      if (byp_hit) byp_v <= 1'b0;               // CPU が受け取った (SU_IF_CLH)
      case (nst)
        N_IDLE:
          if (start) begin
            n_ad   <= ib_ad[31:3];
            n_beat <= 1'b0;
            nst    <= fr_ack ? N_DATA : N_REQ;
          end
        N_REQ:
          if (fr_ack) nst <= N_DATA;
        default: // N_DATA
          if (fr_valid) begin
            n_beat <= 1'b1;
            if (!n_beat) begin
              byp_h <= fr_data;
              n_err <= fr_err;
            end else
              byp_l <= fr_data;
            if (fr_last) begin
              // エラー応答なら 8 バイトとも不正命令にする
              if (n_err | fr_err) begin
                byp_h <= ILL_INSN;
                byp_l <= ILL_INSN;
              end
              byp_v  <= 1'b1;
              byp_ad <= n_ad;
              nst    <= N_IDLE;
            end
          end
      endcase
    end
  end
end
endgenerate
endmodule
