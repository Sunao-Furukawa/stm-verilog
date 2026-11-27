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
//
//  stm_icache.v  -  instruction cache (instruction fetch of stm_cntl <-> stm_axi_master)
//
//  Direct mapped, lines of 2^LINE_W bytes, 2^SET_W lines
//  (32 bytes x 128 = 4 KB by default). Read-only; it is not kept coherent with stores
//  (self-modifying code is not supported).
//
//  - The CPU fetches in 8-byte (2-instruction) units (IB_AD, IB_V).
//    The data RAM is 64 bits wide; 1 entry = 8 bytes.
//  - Hit: the RAM is read one cycle ahead with the CPU's "IB_AD of the next cycle" (IB_AD_NXT),
//    so if_rdy can be returned in the cycle after the request. This is the same timing as the
//    original stm_memory (which answers in the same cycle), so as long as it hits the CPU runs
//    in the same number of cycles as the original design.
//  - Miss: the line is filled with an AXI4 WRAP burst. Reading starts at the requested 8 bytes,
//    and they are returned to the CPU as soon as those 2 beats arrive (early restart).
//    The following 8-byte units are also passed to the CPU as they arrive (for code that runs
//    straight on, the next instructions arrive without waiting for the line fill to finish).
//    Other hits are returned after the line fill is done.
//  - If the CPU cancels a request, a line fill already started is carried out to the end (not wasted).
//    Requests are matched by address, so the CPU does not need to say where requests start.
//
//  With ENABLE=0 there is no cache, and 8 bytes (an INCR of 2 beats) are read every time
//  (the same behaviour as before the cache was added).
//
//  Both RAMs are written in the "1 write port + 1 read port, synchronous read" form,
//  so they become FPGA block RAMs. Only the valid bits are FFs.
//
//  Addresses that cannot be fetched: in the following cases the illegal instruction ILL_INSN
//  (0xE0000000; no instruction has 14 in its top 4 bits) is returned to the CPU instead.
//    - the I/O region ((address & IO_MASK) == IO_BASE, IO_EN=1): not put on the bus
//      (so instruction prefetch never reads I/O)
//    - 8 bytes for which the bus returned an error response: that line is not kept in the cache
//  Actually executing that instruction raises an illegal instruction exception (INTCODE_OP), and
//  XPC holds its address. A prefetch on the mispredicted path is just cancelled and nothing happens.
//
// 【ネットリスト解説】
//   ・ポートのつながり (stm_axi_top.v):
//       ib_valid / ib_ad / ib_ad_nxt <- stm_cntl の IB_VALID / IB_AD / IB_AD_NXT (190)
//       if_rdy / if_dt_h / if_dt_l   -> stm_cntl の RANDOM_FOR_IFCLH / MEM_DT_IF_H / MEM_DT_IF_L (180)
//       fr_*                         <-> stm_axi_master の ifr_*
//   ・既定 (LINE_W=5, SET_W=7) の大きさ:
//       データ RAM dram : 64bit x 512 エントリ (= 4KB)   -> RAMB36E1 1 個 (幅 72bit の SDP モード)
//       タグ RAM  tram  : 20bit x 128 エントリ           -> RAMB18E1 1 個 (幅 36bit の SDP モード)
//       有効ビット vbits: 128 本の FF (リセットで一斉に 0 にするため RAM にはできない)
//     Vivado の結果 (g_cache.dram_reg / g_cache.tram_reg) もこの通りで、
//     FDRE 284 個, FDSE 6 個, LUT 約 330 個, CARRY4 5 個。
//   ・RAM の読み出し番地は ib_ad ではなく ib_ad_nxt。stm_cntl の IB_AD の FF と
//     RAM の出力レジスタ (d_q, t_q) が同じクロックで更新されるので、次のサイクルには
//     ib_ad とその番地の d_q / t_q が揃う。stm_cntl の 170 → 190 の番地計算が
//     そのまま RAM の番地入力まで伸びるので、ここは CPU 側の長い経路の続きになる。
//   ・ヒット判定 hit は t_q (RAM の出力) と ib_tag (FF) の 20bit 一致比較 + vbits の選択。
//     if_rdy / if_dt_h / if_dt_l はこれで選ぶ組合せ出力で、stm_cntl の 180 → 200 を通って
//     IWQ の FF に入る。
//   ・byp_h / byp_l の上位 3bit (ILL_INSN = 0xE000_0000 の 1 のビット) は、Vivado が
//     「エラーなら 1 にする」を FF のセット端子で作るので FDSE になる
//     (byp_h[31:29] と byp_l[31:29] の 6 個が上の FDSE 6 個)。
//
// [Netlist notes]
//   - Port connections (stm_axi_top.v):
//       ib_valid / ib_ad / ib_ad_nxt <- IB_VALID / IB_AD / IB_AD_NXT of stm_cntl (190)
//       if_rdy / if_dt_h / if_dt_l   -> RANDOM_FOR_IFCLH / MEM_DT_IF_H / MEM_DT_IF_L of stm_cntl (180)
//       fr_*                         <-> ifr_* of stm_axi_master
//   - Sizes with the defaults (LINE_W=5, SET_W=7):
//       data RAM dram : 64 bits x 512 entries (= 4 KB)   -> 1 RAMB36E1 (SDP mode, 72 bits wide)
//       tag RAM  tram : 20 bits x 128 entries            -> 1 RAMB18E1 (SDP mode, 36 bits wide)
//       valid bits vbits: 128 FFs (they are cleared all at once on reset, so they can't be a RAM)
//     The Vivado result (g_cache.dram_reg / g_cache.tram_reg) matches this:
//     284 FDRE, 6 FDSE, about 330 LUTs, 5 CARRY4.
//   - The RAM read address is ib_ad_nxt, not ib_ad. The IB_AD FFs of stm_cntl and the RAM
//     output registers (d_q, t_q) update on the same clock, so in the next cycle ib_ad and the
//     d_q / t_q for that address line up. The address logic of 170 -> 190 in stm_cntl extends
//     to the address input of the RAMs, so this continues one of the long paths on the CPU side.
//   - The hit test hit is a 20-bit equality compare of t_q (RAM output) with ib_tag (FFs), plus
//     a selection of vbits. if_rdy / if_dt_h / if_dt_l are combinational outputs selected with
//     it, and they enter the IWQ FFs through 180 -> 200 of stm_cntl.
//   - The top 3 bits of byp_h / byp_l (the 1 bits of ILL_INSN = 0xE000_0000) become FDSEs,
//     because Vivado makes "set to 1 on an error" with the FF's set pin
//     (byp_h[31:29] and byp_l[31:29], the 6 FDSEs above).
// =====================================================================
module stm_icache #(                                    // 命令キャッシュ (ダイレクトマップ, ブロックRAM 2個) / instruction cache (direct mapped, 2 block RAMs)
  parameter ENABLE = 1,                                 // 1=キャッシュあり, 0=キャッシュ無し (generateでどちらかの回路だけが作られる) / 1 cache, 0 no cache (generate builds only one of them)
  parameter LINE_W = 5,             // ライン長 = 2^LINE_W バイト (4〜6: 16〜64 バイト)
                                    // line length = 2^LINE_W bytes (4-6: 16-64 bytes)
  parameter SET_W  = 7,             // ライン数 = 2^SET_W (1 以上)
                                    // number of lines = 2^SET_W (1 or more)
  parameter        IO_EN   = 1,                         // I/O領域からのフェッチを禁止する / forbid fetches from the I/O region
  parameter [31:0] IO_BASE = 32'hF000_0000,             // I/O領域の先頭 / I/O region base
  parameter [31:0] IO_MASK = 32'hF000_0000              // I/O領域の判定マスク / I/O region mask
) (                                                     // パラメータの終わり, ポートの始まり / end of parameters, start of ports
  input             clk,                                // クロック: FFとブロックRAMの両方 / clock: both the FFs and the block RAMs
  input             rst,                                // 同期リセット (状態FFと有効ビットだけ, RAMの中身は消えない) / sync reset (state FFs and valid bits only; RAM contents stay)

  // ---- stm_cntl 側
  //      (stm_cntl side)
  input             ib_valid,       // IB_VALID  -- フェッチ要求が有効 (stm_cntlのIB_VのFF) / fetch request valid (IB_V FF of stm_cntl)
  input      [31:0] ib_ad,          // IB_AD  -- 要求中のフェッチ番地 (FF出力) → タグ比較とバッファ比較 / pending fetch address (FF output) -> tag and buffer compares
  input      [31:0] ib_ad_nxt,      // IB_AD_NXT (次のサイクルの IB_AD)
                                    // IB_AD_NXT (IB_AD of the next cycle)
  output            if_rdy,         // -> RANDOM_FOR_IFCLH  -- 命令が届いた (ヒット/バッファ/I/OのOR) / insns arrived (OR of hit / buffer / I/O)
  output     [31:0] if_dt_h,        // -> MEM_DT_IF_H (先の命令, 番地 8n)
                                    // -> MEM_DT_IF_H (the earlier instruction, address 8n)
  output     [31:0] if_dt_l,        // -> MEM_DT_IF_L (後の命令, 番地 8n+4)
                                    // -> MEM_DT_IF_L (the later instruction, address 8n+4)

  // ---- stm_axi_master 側 (バースト読み出し)
  //      (stm_axi_master side: burst reads)
  output            fr_req,                             // バースト読み出し要求 → stm_axi_masterのifr_req / burst read request -> ifr_req of stm_axi_master
  output     [31:0] fr_addr,                            // 要求番地 (8バイト境界, WRAPなので要求した語から届く) / request address (8-byte aligned; WRAP so the requested word comes first)
  output     [7:0]  fr_len,                             // ARLEN = ビート数-1 / ARLEN = beats - 1
  output     [1:0]  fr_burst,                           // ARBURST (キャッシュはWRAP, 無しはINCR) / ARBURST (WRAP with the cache, INCR without)
  input             fr_ack,                             // ARが受け付けられた / AR accepted
  input             fr_valid,                           // ビートが届いた / a beat arrived
  input      [31:0] fr_data,                            // ビートのデータ / beat data
  input             fr_last,                            // 最後のビート / last beat
  input             fr_err          // このビートはエラー応答
                                    // this beat is an error response
);                                                      // ポート宣言の終わり / end of ports
  localparam [31:0] ILL_INSN = 32'hE000_0000;           // 不正命令の語 (上位4bit=1110は未定義) → エラー時にCPUへ返す / an illegal insn word (top 4 bits 1110 undefined) -> returned to the CPU on errors

  // I/O 領域からはフェッチしない (すぐに不正命令を返す)
  // no fetches from the I/O region (return an illegal instruction at once)
  wire       io_hit  = ib_valid & IO_EN & ((ib_ad & IO_MASK) == IO_BASE); // IB_ADがI/O領域: フェッチせずに不正命令を返す (定数マスクの比較) / IB_AD in I/O space: return illegal insns without fetching (constant-mask compare)

  // 直前に届いた 8 バイト (early restart / キャッシュ無しのときのデータ)
  // the 8 bytes that arrived last (data for early restart / without the cache)
  reg        byp_v;                                     // 直前に届いた8バイトが有効 (FF) / the last 8 bytes are valid (FF)
  reg [28:0] byp_ad;                // 番地 [31:3]
                                    // address [31:3]
  reg [31:0] byp_h, byp_l;                              // 直前に届いた8バイトの前半/後半 (FF 64本) / first / second half of those 8 bytes (64 FFs)
  wire       byp_hit = ib_valid & byp_v & (byp_ad == ib_ad[31:3]); // 要求がそのバッファの番地と一致: 29bit比較器 (early restart用) / request matches that buffer: 29-bit comparator (for early restart)

generate                                                // パラメータで回路を選ぶ (合成時に片方だけ残る) / choose the circuit by parameter (only one survives synthesis)
if (ENABLE) begin : g_cache                             // キャッシュあり: 階層名g_cache / with cache: hierarchy name g_cache
  localparam WORDS  = 1 << (LINE_W - 2);       // ラインの語数 (= ビート数)
                                               // words per line (= number of beats)
  localparam UNIT_W = LINE_W - 3;              // ライン内の 8 バイト単位の番号の幅
                                               // width of the 8-byte unit number within a line
  localparam TAG_W  = 32 - LINE_W - SET_W;              // タグの幅 = 32 - ライン番号 - ライン内 (既定20bit) / tag width = 32 - index - offset (20 by default)
  localparam DEP_W  = SET_W + UNIT_W;                   // データRAMの番地幅 = ライン番号 + 8バイト単位番号 (既定9bit = 512語x64bit) / data RAM address width (9 by default = 512 x 64 bits)

  localparam [1:0] F_IDLE = 2'd0, F_REQ = 2'd1, F_DATA = 2'd2, F_DONE = 2'd3; // ライン埋めの状態の符号 (2bitの状態FF fst) / line-fill state codes (2-bit state FFs fst)

  reg [63:0]       dram [0:(1<<DEP_W)-1];      // {H, L}  -- データRAM: 8バイト (先の命令が上位) を1語として格納 → RAMB36E1 1個 / data RAM: 8 bytes per entry (earlier insn on top) -> one RAMB36E1
  reg [TAG_W-1:0]  tram [0:(1<<SET_W)-1];               // タグRAM: 128語x20bit → ブロックRAM (RAMB18) / tag RAM: 128 x 20 bits -> block RAM (RAMB18)
  reg [(1<<SET_W)-1:0] vbits;                           // ラインの有効ビット: FF 128本 (リセットで一斉に0にするのでRAMにしない) / line valid bits: 128 FFs (cleared at once by reset, so not a RAM)
  reg [63:0]       d_q;                                 // データRAMの読み出し: RAMの出力レジスタそのもの / data RAM read: the RAM's own output register
  reg [TAG_W-1:0]  t_q;                                 // タグRAMの読み出し: RAMの出力レジスタ / tag RAM read: the RAM's output register

  reg  [1:0]        fst;                                // ライン埋めの状態FF / line-fill state FFs
  reg  [28:0]       f_ad;                       // 埋めているラインの要求番地 [31:3]
                                                // requested address of the line being filled [31:3]
  reg  [LINE_W-3:0] f_beat;                     // 何ビート目か
                                                // which beat
  reg  [31:0]       f_hw;                       // 8 バイトの前半 (H) を待たせる
                                                // holds the first half (H) of the 8 bytes
  reg               f_herr;                     // 前半がエラー応答だった
                                                // the first half was an error response
  reg               f_err;                      // このライン埋めでエラー応答があった
                                                // this line fill had an error response

  wire [SET_W-1:0]  ib_idx   = ib_ad[LINE_W+SET_W-1:LINE_W]; // 要求のライン番号 = IB_ADの[11:5] (配線) / line number of the request = IB_AD[11:5] (wires)
  wire [TAG_W-1:0]  ib_tag   = ib_ad[31:LINE_W+SET_W];  // 要求のタグ = IB_ADの[31:12] / tag of the request = IB_AD[31:12]
  wire [SET_W-1:0]  f_idx    = f_ad[LINE_W+SET_W-4:LINE_W-3]; // 埋めているラインの番号 / line number being filled
  wire [TAG_W-1:0]  f_tag    = f_ad[28:LINE_W+SET_W-3]; // 埋めているラインのタグ / tag of the line being filled
  // このビートのライン内の語番号 (WRAP なので要求した語から回る)
  // word number within the line of this beat (WRAP, so it wraps around from the requested word)
  wire [LINE_W-3:0] f_word   = {f_ad[LINE_W-4:0], 1'b0} + f_beat; // このビートのライン内の語番号: 要求語 + ビート数 (3bitの小さな加算器, 桁あふれで回る) / word index of this beat: requested word + beat count (small 3-bit adder that wraps)

  // 【解説】番地の分け方 (既定値の場合):
  //           [31:12] タグ (20bit) | [11:5] ライン番号 (7bit) | [4:3] ライン内の 8 バイト単位 | [2:0]
  //         データ RAM の番地は {ライン番号, ライン内の 8 バイト単位} の 9bit。
  // [Note] How the address is split (with the defaults):
  //          [31:12] tag (20 bits) | [11:5] line number (7 bits) | [4:3] 8-byte unit in the line | [2:0]
  //        The data RAM address is the 9 bits {line number, 8-byte unit in the line}.
  // ---- RAM (読み出しは IB_AD_NXT で 1 サイクル先に)
  //      (RAM: read one cycle ahead with IB_AD_NXT)
  wire [DEP_W-1:0] rd_a = {ib_ad_nxt[LINE_W+SET_W-1:LINE_W], ib_ad_nxt[LINE_W-1:3]}; // RAMの読み出し番地: IB_AD_NXT (FFのD入力) から作るので, IB_ADのFFと同じクロックで揃う / RAM read address from IB_AD_NXT (the FF's D), so it lines up with the IB_AD FFs on the same clock
  wire             d_we = (fst == F_DATA) & fr_valid & f_word[0]; // データRAMへの書き込み: 8バイトの後半が届いたとき / data RAM write: when the second half of 8 bytes arrives
  wire [DEP_W-1:0] d_wa = {f_idx, f_word[LINE_W-3:1]};  // データRAMの書き込み番地 / data RAM write address
  wire             t_we = (fst == F_DATA) & fr_valid & fr_last; // タグRAMへの書き込み: ラインの最後のビート / tag RAM write: last beat of the line

  // 【解説】この 2 つの always が「書き 1 ポート + 同期読み 1 ポート」のブロック RAM の
  //         定型。d_q / t_q は RAM の内部の出力レジスタになり、別の FF にはならない。
  //         1 ビートは 32bit なので、前半 (H) を f_hw に貯めておき、後半 (L) が来た
  //         サイクルに 64bit まとめて書く (d_we は f_word[0] = 後半のときだけ)。
  //
  // [Note] These two always blocks are the standard template of a block RAM with "1 write port + 1
  //        synchronous read port". d_q / t_q become the RAM's internal output registers, not separate FFs.
  //        A beat is 32 bits, so the first half (H) is kept in f_hw and the 64 bits are written
  //        together in the cycle the second half (L) arrives (d_we only when f_word[0] = second half).
  always @(posedge clk) begin                           // データRAM: 書き1+同期読み1 → RAMB36 (64bit幅) / data RAM: 1 write + 1 sync read -> RAMB36 (64 bits wide)
    if (d_we) dram[d_wa] <= {f_hw, fr_data};            // 前半(f_hw)と後半(今のビート)を64bitで書く / write first half (f_hw) and this beat as 64 bits
    d_q <= dram[rd_a];                                  // 同期読み出し (次のサイクルにd_qに出る) / synchronous read (appears in d_q next cycle)
  end                                                   // always の終わり / end of always
  always @(posedge clk) begin                           // タグRAM: 書き1+同期読み1 / tag RAM: 1 write + 1 sync read
    if (t_we) tram[f_idx] <= f_tag;                     // ラインを埋め終えたらタグを書く / write the tag when the line is filled
    t_q <= tram[rd_a[DEP_W-1:UNIT_W]];                  // 同じ読み出し番地のライン番号部分でタグを読む / read the tag with the line-number part of the same address
  end                                                   // always の終わり / end of always

  // ---- ヒット判定。ライン埋めの間と直後の 1 サイクル (RAM の読み出しが
  //      書き込みと重なって古い値かもしれない) はヒットにしない。
  // ---- hit test. Not a hit during a line fill or in the cycle right after it (the RAM read
  //      may overlap the write and return an old value).
  wire hit        = ib_valid & (fst == F_IDLE) & vbits[ib_idx] & (t_q == ib_tag); // ヒット: 待機中で有効ビットが1でタグ一致 (20bit比較器 + 128:1 MUXの有効ビット) / hit: idle, valid bit set, tag equal (20-bit comparator + 128:1 valid-bit mux)
  wire miss_start = ib_valid & (fst == F_IDLE) & !hit & !byp_hit & !io_hit; // ミス: ライン埋めを始める (バッファにもI/Oにも当たらない) / miss: start a line fill (not in the buffer, not I/O)
  wire pair_err   = f_herr | fr_err;            // この 8 バイトのどちらかがエラー
                                                // either half of these 8 bytes is an error

  assign if_rdy   = hit | byp_hit | io_hit;             // CPUへ「命令が届いた」 → RANDOM_FOR_IFCLH / tell the CPU "insns arrived" -> RANDOM_FOR_IFCLH
  assign if_dt_h  = io_hit ? ILL_INSN : byp_hit ? byp_h : d_q[63:32]; // 前半の命令: I/Oなら不正命令, バッファ, RAMの順 (32bit 3:1 MUX) / first insn: illegal for I/O, then buffer, then RAM (32-bit 3:1 mux)
  assign if_dt_l  = io_hit ? ILL_INSN : byp_hit ? byp_l : d_q[31:0]; // 後半の命令 (同じ形) / second insn (same form)

  assign fr_req   = miss_start | (fst == F_REQ);        // バースト要求: ミスした瞬間 (組合せ) か受け付け待ちの間 / burst request: at the miss (combinational) or while waiting for acceptance
  assign fr_addr  = (fst == F_REQ) ? {f_ad, 3'b000} : {ib_ad[31:3], 3'b000}; // 要求番地: 待ちの間はf_ad, 最初は今のIB_AD (32bit 2:1 MUX) / request address: f_ad while waiting, else the current IB_AD (32-bit 2:1 mux)
  assign fr_len   = WORDS - 1;                          // 1ラインの語数-1 (定数, 既定7 = 8ビート) / words per line - 1 (constant, 7 = 8 beats by default)
  assign fr_burst = 2'b10;                      // WRAP  -- 要求した語から読み始めて回り込む (early restartのため) / start at the requested word and wrap (for early restart)

  always @(posedge clk) begin                           // ライン埋めの状態機械 / line-fill state machine
    if (rst) begin                                      // リセット / reset
      fst    <= F_IDLE;                                 // 待機へ / to idle
      vbits  <= 0;                                      // 全ラインを無効に (128本のFFのR) / invalidate every line (R of the 128 FFs)
      byp_v  <= 1'b0;                                   // バッファ無効 / buffer invalid
      f_ad   <= 29'd0;                                  // 0クリア / clear
      f_beat <= 0;                                      // 0クリア / clear
      f_hw   <= 32'd0;                                  // 0クリア / clear
      f_herr <= 1'b0;                                   // 0クリア / clear
      f_err  <= 1'b0;                                   // 0クリア / clear
    end else begin                                      // 通常動作 / normal operation
      case (fst)                                        // 状態ごとの動作 / per-state behaviour
        F_IDLE:                                         // 待機 / idle
          if (miss_start) begin                         // ミスした / a miss
            f_ad          <= ib_ad[31:3];               // 要求番地を覚える / remember the request address
            f_beat        <= 0;                         // ビート数を0から / beat count from 0
            f_err         <= 1'b0;                      // エラー無しから / no error yet
            byp_v         <= 1'b0;                      // 古いバッファを無効に / invalidate the old buffer
            vbits[ib_idx] <= 1'b0;                      // 埋めるラインを無効に (デコーダ→128本のFFの1本) / invalidate the line being filled (decoder -> 1 of 128 FFs)
            fst           <= fr_ack ? F_DATA : F_REQ;   // すぐ受け付けられたらデータ待ち / to data wait if accepted at once
          end                                           // if の終わり / end of if
        F_REQ:                                          // ARの受け付け待ち / waiting for AR acceptance
          if (fr_ack) fst <= F_DATA;                    // 受け付けられた / accepted
        F_DATA:                                         // ビートを受け取る / receiving beats
          if (fr_valid) begin                           // ビートが届いた / a beat arrived
            f_beat <= f_beat + 1'b1;                    // ビート数+1 (3bitカウンタ) / beat count + 1 (3-bit counter)
            if (fr_err) f_err <= 1'b1;                  // エラーを覚える / remember an error
            if (!f_word[0]) begin                       // 8バイトの前半なら / first half of 8 bytes
              f_hw   <= fr_data;                        // 前半を貯める (FF32本) / store the first half (32 FFs)
              f_herr <= fr_err;                         // 前半のエラー / error of the first half
            end                                         // if の終わり / end of if
            // 8 バイト揃うごとに CPU へ流す (最初は要求したもの)。
            // エラー応答なら不正命令に置き換える。
            // Every time 8 bytes are complete, pass them to the CPU (the requested ones first).
            // Replace them with illegal instructions on an error response.
            if (f_word[0]) begin                        // 8バイトの後半なら / second half of 8 bytes
              byp_v  <= 1'b1;                           // バッファに入れてCPUへ (early restart: ラインを待たずに流す) / into the buffer for the CPU (early restart: no wait for the whole line)
              byp_ad <= {f_ad[28:LINE_W-3], f_word[LINE_W-3:1]}; // その8バイトの番地 / address of those 8 bytes
              byp_h  <= pair_err ? ILL_INSN : f_hw;     // 前半 (エラーなら不正命令) / first half (illegal insn on error)
              byp_l  <= pair_err ? ILL_INSN : fr_data;  // 後半 (エラーなら不正命令) / second half (illegal insn on error)
            end                                         // if の終わり / end of if
            if (fr_last) begin                          // ラインの最後のビート / last beat of the line
              // エラー応答のあったラインは有効にしない (次も読み直す)
              // a line with an error response is not made valid (it is read again next time)
              vbits[f_idx] <= !(f_err | fr_err);        // エラーが無ければラインを有効に / make the line valid if no error
              fst          <= F_DONE;                   // 1サイクル休む (RAMの読み書きの重なり回避) / rest one cycle (avoid RAM read/write overlap)
            end                                         // if の終わり / end of if
          end                                           // if (fr_valid) の終わり / end of if (fr_valid)
        default: // F_DONE  -- ライン埋めの直後の1サイクル (状態値3) / the cycle right after a line fill (state 3)
          fst <= F_IDLE;                                // (F_DONE) 待機へ戻る / (F_DONE) back to idle
      endcase                                           // caseの終わり / end of case
    end                                                 // else の終わり / end of else
  end                                                   // always の終わり / end of always
end else begin : g_nocache                              // キャッシュ無し: 階層名g_nocache / no cache: hierarchy name g_nocache
  // ---- キャッシュ無し: 毎回 8 バイトを読み, CPU が受け取ったら捨てる
  //      (no cache: read 8 bytes every time, drop them once the CPU has taken them)
  // 【ネットリスト解説】generate の else 側なので、ENABLE=0 のときだけこちらの回路が
  //   作られ (RAM は 0 個)、ENABLE=1 のときは丸ごと存在しない。byp_* の FF
  //   (8 バイトのバッファ 1 つ) と 3 状態の状態機械だけの回路になる。
  //   ib_ad_nxt はここでは使わないので、stm_cntl の IB_AD_NXT はどこにもつながらない。
  //
  // [Netlist notes] This is the else side of generate, so this circuit is built only with
  //   ENABLE=0 (0 RAMs), and with ENABLE=1 it does not exist at all. It is just the byp_* FFs
  //   (one 8-byte buffer) and a 3-state state machine.
  //   ib_ad_nxt is not used here, so IB_AD_NXT of stm_cntl is connected to nothing.
  localparam [1:0] N_IDLE = 2'd0, N_REQ = 2'd1, N_DATA = 2'd2; // 状態の符号 (3状態) / state codes (3 states)
  reg  [1:0]  nst;                                      // 状態FF / state FFs
  reg  [28:0] n_ad;                                     // 読んでいる8バイトの番地 / address of the 8 bytes being read
  reg         n_beat;                                   // 何ビート目か (0/1) / which beat (0/1)
  reg         n_err;                                    // 前半がエラーだった / the first half was an error

  wire start = ib_valid & (nst == N_IDLE) & !byp_hit & !io_hit; // 読み出し開始: 要求があり, バッファにもI/Oにも当たらない / start a read: request, not in the buffer, not I/O

  assign if_rdy   = byp_hit | io_hit;                   // CPUへの到着: バッファかI/O / arrival to the CPU: buffer or I/O
  assign if_dt_h  = io_hit ? ILL_INSN : byp_h;          // 前半: I/Oなら不正命令, そうでなければバッファ / first half: illegal for I/O, else the buffer
  assign if_dt_l  = io_hit ? ILL_INSN : byp_l;          // 後半 / second half

  assign fr_req   = start | (nst == N_REQ);             // 要求: 開始の瞬間か受け付け待ち / request: at start or while waiting
  assign fr_addr  = (nst == N_REQ) ? {n_ad, 3'b000} : {ib_ad[31:3], 3'b000}; // 要求番地 (32bit 2:1 MUX) / request address (32-bit 2:1 mux)
  assign fr_len   = 8'd1;                       // 2 ビート
                                                // 2 beats
  assign fr_burst = 2'b01;                      // INCR  -- キャッシュ無し: 8バイトを順に2ビート読む / no cache: read the 8 bytes in 2 ascending beats

  always @(posedge clk) begin                           // 状態機械 / state machine
    if (rst) begin                                      // リセット / reset
      nst    <= N_IDLE;                                 // 待機へ / to idle
      byp_v  <= 1'b0;                                   // バッファ無効 / buffer invalid
      n_ad   <= 29'd0;                                  // 0クリア / clear
      n_beat <= 1'b0;                                   // 0クリア / clear
      n_err  <= 1'b0;                                   // 0クリア / clear
    end else begin                                      // 通常動作 / normal operation
      if (byp_hit) byp_v <= 1'b0;               // CPU が受け取った (SU_IF_CLH)
                                                // the CPU took it (SU_IF_CLH)
      case (nst)                                        // 状態ごと / per state
        N_IDLE:                                         // 待機 / idle
          if (start) begin                              // 開始 / start
            n_ad   <= ib_ad[31:3];                      // 番地を覚える / remember the address
            n_beat <= 1'b0;                             // 前半から / from the first half
            nst    <= fr_ack ? N_DATA : N_REQ;          // すぐ受け付けられたらデータ待ち / to data wait if accepted at once
          end                                           // if の終わり / end of if
        N_REQ:                                          // 受け付け待ち / waiting for acceptance
          if (fr_ack) nst <= N_DATA;                    // 受け付けられた / accepted
        default: // N_DATA  -- キャッシュ無しのデータ待ちの状態 (状態値2) / no-cache data-wait state (state 2)
          if (fr_valid) begin                           // (N_DATA) ビートが届いた / (N_DATA) a beat arrived
            n_beat <= 1'b1;                             // 次は後半 / next is the second half
            if (!n_beat) begin                          // 前半なら / first half
              byp_h <= fr_data;                         // 前半をバッファへ / first half to the buffer
              n_err <= fr_err;                          // そのエラー / its error
            end else                                    // 後半なら / second half
              byp_l <= fr_data;                         // 後半をバッファへ / second half to the buffer
            if (fr_last) begin                          // 最後のビート / last beat
              // エラー応答なら 8 バイトとも不正命令にする
              // on an error response, make all 8 bytes illegal instructions
              if (n_err | fr_err) begin                 // どちらかがエラーなら / either half failed
                byp_h <= ILL_INSN;                      // 前半を不正命令に / first half -> illegal insn
                byp_l <= ILL_INSN;                      // 後半を不正命令に / second half -> illegal insn
              end                                       // if の終わり / end of if
              byp_v  <= 1'b1;                           // バッファ有効 → CPUへ / buffer valid -> to the CPU
              byp_ad <= n_ad;                           // バッファの番地 / buffer address
              nst    <= N_IDLE;                         // 待機へ / to idle
            end                                         // if (fr_last) の終わり / end of if (fr_last)
          end                                           // if (fr_valid) の終わり / end of if (fr_valid)
      endcase                                           // caseの終わり / end of case
    end                                                 // else の終わり / end of else
  end                                                   // always の終わり / end of always
end                                                     // generate の if/else の終わり / end of the generate if/else
endgenerate                                             // generateの終わり / end of generate
endmodule                                               // モジュールの終わり / end of module
