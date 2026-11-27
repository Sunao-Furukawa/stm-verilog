// =====================================================================
//  axi4_mem_slave.v  -  テスト用の AXI4 スレーブ (メモリ) モデル
//
//  ・INCR / FIXED / WRAP バースト, WSTRB, ID 付きの複数未完了トランザクション
//  ・rnd=1 のとき乱数で:
//      READY を落とす (AR/AW/W), 応答を遅らせる (R/B),
//      ID の違う読み出しの応答順を入れ替え, ビート単位でインタリーブする
//    rnd=0 なら READY は常に 1 で, 最短 (アドレスの次のサイクル) で応答する。
//  ・マスタ側の AXI の規則違反を検査して errors に数える:
//      VALID を READY 前に下げた / VALID 中に内容が変わった /
//      WLAST がバースト長と合わない / 4KB 境界をまたぐバースト など
//  メモリは語 (32bit) の配列 mem[]。番地は 2^AW 語で折り返す。
//  ただし次の 2 つの領域は別扱い (上位 4bit で判定):
//    0xF000_0000〜 : テスト用の I/O デバイス
//        +0 (DEV_A) 読むたびに「それまでに読まれた回数」を返し, 1 増える
//                   (投機的な読み出しがあれば数が合わなくなる)。書き込みは無視
//        +4 (DEV_B) 書いた値のビット反転を返す
//                   (ストアのデータをフォワーディングで読むと反転していない)
//        +8 (CONSOLE) 書いた語の下位 8bit を 1 文字として表示する ($write)
//        他         読むと 0, 書き込みは無視
//    0xE000_0000〜 : エラー領域。読み書きとも SLVERR を返す (書き込みはしない)
//  SWAP=1 なら I/O デバイスの値はバイトを入れ替えて扱う (マスタの BYTE_SWAP=1 用)。
//  シミュレーション専用 (合成不可)。
//
//  axi4_mem_slave.v  -  AXI4 slave (memory) model for testing
//
//  - INCR / FIXED / WRAP bursts, WSTRB, several outstanding transactions with IDs
//  - with rnd=1, at random:
//      drops READY (AR/AW/W), delays responses (R/B),
//      reorders the responses of reads with different IDs and interleaves them beat by beat
//    with rnd=0 READY is always 1 and it answers as fast as possible (the cycle after the address).
//  - checks the master for AXI rule violations and counts them in errors:
//      VALID dropped before READY / contents changed while VALID /
//      WLAST does not match the burst length / a burst crossing a 4 KB boundary, etc.
//  The memory is an array of words (32 bits), mem[]. Addresses wrap at 2^AW words,
//  except for the following 2 regions (decided by the top 4 bits):
//    0xF000_0000- : test I/O devices
//        +0 (DEV_A) each read returns "the number of reads so far" and then counts up
//                   (a speculative read would make the count wrong). Writes are ignored
//        +4 (DEV_B) returns the bit inverse of the value written
//                   (reading store data by forwarding would give it uninverted)
//        +8 (CONSOLE) prints the low 8 bits of the written word as a character ($write)
//        others     read as 0, writes are ignored
//    0xE000_0000- : error region. Returns SLVERR for both reads and writes (nothing is written)
//  With SWAP=1 the I/O device values are byte-swapped (for a master with BYTE_SWAP=1).
//  Simulation only (not synthesizable).
//
// 【解説】このモデルの書き方について
//   ・実際の回路ではなく「振る舞い」のモデル。always ブロックの中でブロッキング
//     代入 (=) と integer, for ループを自由に使い、キュー (rq_*, wq_*, wd, bq_*) を
//     配列で表している。出力の *_ready / *_valid / r* / b* だけはノンブロッキング (<=)
//     で書き、クロックの立ち上がりで変わる FF の出力のように見せている。
//     そのため DUT (stm_axi_top) から見ると、普通の同期回路のスレーブと同じタイミングになる。
//   ・ネット (ポート) の向き: s_axi_aw* / s_axi_w* / s_axi_ar* / s_axi_bready / s_axi_rready
//     が入力 (マスタが駆動), s_axi_*ready (AW/W/AR) と s_axi_b* / s_axi_r* が出力。
//   ・規則違反の検査 (ar_stall など) は、前のサイクルに VALID=1 & READY=0 だったのに
//     このサイクルで VALID が落ちたか内容が変わったら数える。AXI の
//     「VALID を出したら READY まで取り下げない・変えない」の検査そのもの。
//
// [Note] How this model is written
//   - It is a "behavioural" model, not a real circuit. Inside the always blocks it freely uses
//     blocking assignments (=), integers and for loops, and represents the queues
//     (rq_*, wq_*, wd, bq_*) as arrays. Only the outputs *_ready / *_valid / r* / b* are written
//     with non-blocking assignments (<=), so they look like FF outputs changing on the rising clock edge.
//     So, seen from the DUT (stm_axi_top), it has the same timing as an ordinary synchronous slave.
//   - Direction of the nets (ports): s_axi_aw* / s_axi_w* / s_axi_ar* / s_axi_bready / s_axi_rready
//     are inputs (driven by the master); s_axi_*ready (AW/W/AR) and s_axi_b* / s_axi_r* are outputs.
//   - The protocol checks (ar_stall etc.) count a violation when VALID=1 & READY=0 in the previous
//     cycle and in this cycle VALID dropped or the contents changed. That is exactly AXI's
//     rule "once VALID is raised, do not withdraw or change it until READY".
// =====================================================================
module axi4_mem_slave #(                                // AXI4スレーブのメモリモデル+規則検査 (シミュレーション専用, 合成不可: integer配列や$randomを使う) / AXI4 slave memory model + protocol checker (simulation only; not synthesizable: integer arrays, $random)
  parameter AW   = 10,              // 語アドレス幅 (2^AW 語)
                                    // word address width (2^AW words)
  parameter ID_W = 4,                                   // IDの幅 / ID width
  parameter QD   = 4,               // 読み出し / 書き込みアドレスの受付数
                                    // number of read / write addresses accepted
  parameter SWAP = 0                // I/O デバイスの値のバイト入れ替え
                                    // byte swap of the I/O device values
) (                                                     // パラメータの終わり, ポートの始まり / end of parameters, start of ports
  input                 aclk,                           // クロック / clock
  input                 aresetn,                        // 負論理リセット / active-low reset
  input                 rnd,        // 1: 乱数でウェイト・順序入れ替え
                                    // 1: random waits and reordering

  input      [ID_W-1:0] s_axi_awid,                     // 書き込みアドレスのID / write address ID
  input      [31:0]     s_axi_awaddr,                   // 書き込み番地 / write address
  input      [7:0]      s_axi_awlen,                    // バースト長-1 / burst length - 1
  input      [2:0]      s_axi_awsize,                   // ビートのサイズ (2^size バイト) / beat size (2^size bytes)
  input      [1:0]      s_axi_awburst,                  // バーストの種類 (0=FIXED 1=INCR 2=WRAP) / burst type (0 FIXED, 1 INCR, 2 WRAP)
  input                 s_axi_awvalid,                  // AW有効 / AW valid
  output reg            s_axi_awready,                  // AW受け付け (乱数で止める) / AW ready (randomly stalled)
  input      [31:0]     s_axi_wdata,                    // 書き込みデータ / write data
  input      [3:0]      s_axi_wstrb,                    // バイトストローブ / byte strobes
  input                 s_axi_wlast,                    // 最後のビート / last beat
  input                 s_axi_wvalid,                   // W有効 / W valid
  output reg            s_axi_wready,                   // W受け付け / W ready
  output reg [ID_W-1:0] s_axi_bid,                      // 書き込み応答のID / write response ID
  output reg [1:0]      s_axi_bresp,                    // 書き込み応答 (0=OKAY, 2=SLVERR) / write response (0 OKAY, 2 SLVERR)
  output reg            s_axi_bvalid,                   // B有効 / B valid
  input                 s_axi_bready,                   // B受け取り可 / B ready
  input      [ID_W-1:0] s_axi_arid,                     // 読み出しアドレスのID / read address ID
  input      [31:0]     s_axi_araddr,                   // 読み出し番地 / read address
  input      [7:0]      s_axi_arlen,                    // バースト長-1 / burst length - 1
  input      [2:0]      s_axi_arsize,                   // ビートのサイズ / beat size
  input      [1:0]      s_axi_arburst,                  // バーストの種類 / burst type
  input                 s_axi_arvalid,                  // AR有効 / AR valid
  output reg            s_axi_arready,                  // AR受け付け / AR ready
  output reg [ID_W-1:0] s_axi_rid,                      // 読み出しデータのID / read data ID
  output reg [31:0]     s_axi_rdata,                    // 読み出しデータ / read data
  output reg [1:0]      s_axi_rresp,                    // 読み出し応答 / read response
  output reg            s_axi_rlast,                    // 最後のビート / last beat
  output reg            s_axi_rvalid,                   // R有効 / R valid
  input                 s_axi_rready                    // R受け取り可 / R ready
);                                                      // ポート宣言の終わり / end of ports
  reg [31:0] mem [0:(1<<AW)-1];                         // メモリ本体 (tbから$readmemhで直接読み込む) / memory array (loaded by the tb with $readmemh)
  integer    seed;                  // テストベンチから設定してよい
                                    // may be set by the testbench
  integer    errors;                // 規則違反の数
                                    // number of rule violations
  integer    n_rd, n_wr;            // 受け付けたトランザクション数
                                    // number of transactions accepted
  integer    dev_rd;                // I/O デバイスが読まれた回数 (ビート数)
                                    // number of reads of the I/O devices (beats)
  integer    dev_a;                 // DEV_A の値 (= DEV_A が読まれた回数)
                                    // value of DEV_A (= number of times DEV_A was read)
  reg [31:0] dev_b;                 // DEV_B に書かれた値
                                    // value written to DEV_B
  integer    n_rd_err, n_wr_err;    // エラーを返した数
                                    // number of error responses returned

  function [31:0] dsw;              // I/O デバイスの値 <-> バスの語
                                    // I/O device value <-> bus word
    input [31:0] d;                                     // 関数の入力 / function input
    dsw = SWAP ? {d[7:0], d[15:8], d[23:16], d[31:24]} : d; // SWAP=1ならバイト順を反転 / reverse bytes when SWAP=1
  endfunction                                           // 関数の終わり / end of function
  function is_dev;  input [31:0] a; is_dev = (a[31:28] == 4'hF); endfunction // 0xF... はI/Oデバイス領域 / 0xF... is the I/O device region
  function is_err;  input [31:0] a; is_err = (a[31:28] == 4'hE); endfunction // 0xE... はエラーを返す領域 (バスエラーの試験用) / 0xE... returns errors (for bus-error tests)

  integer k;                                            // 初期化ループの変数 / init loop variable
  initial begin                                         // シミュレーション開始時の初期化 / initialization at time 0
    for (k = 0; k < (1<<AW); k = k + 1) mem[k] = 32'd0; // メモリを0クリア / clear the memory
    seed = 1; errors = 0; n_rd = 0; n_wr = 0;           // 種とカウンタの初期値 / initial seed and counters
    dev_rd = 0; dev_a = 0; dev_b = 0; n_rd_err = 0; n_wr_err = 0; // デバイスの状態とエラー数を0に / clear the device state and error counts
  end                                                   // initial の終わり / end of initial

  function chance;                  // rnd のとき確率 1/2 で 0
                                    // 0 with probability 1/2 when rnd
    input dummy;                                        // 引数無しの関数は書けないので仮の入力 / dummy input (functions need one)
    chance = !rnd || ($random(seed) & 1);               // rnd=0なら常に1, rnd=1なら1/2で1 / always 1 when rnd=0, 1 with probability 1/2 when rnd=1
  endfunction                                           // 関数の終わり / end of function

  // バーストの次の番地
  // next address of a burst
  function [31:0] next_addr;                            // バーストの次のビートの番地 / address of the next beat of a burst
    input [31:0] a; input [7:0] len; input [2:0] size; input [1:0] burst; // 引数: 今の番地, 長さ, サイズ, 種類 / args: address, length, size, type
    reg [31:0] bytes, wmask;                            // 作業変数 / work variables
    begin                                               // 関数本体 / body
      bytes = 32'd1 << size;                            // 1ビートのバイト数 / bytes per beat
      case (burst)                                      // 種類ごと / per type
        2'b00:   next_addr = a;                                   // FIXED  -- 同じ番地を繰り返す / repeat the same address
        2'b10: begin                                              // WRAP  -- 範囲の中で回り込む / wrap inside the window
          wmask = bytes * (len + 1) - 1;                // (WRAP) 折り返す範囲のマスク = バースト全体のバイト数-1 / (WRAP) wrap mask = total bytes of the burst - 1
          next_addr = (a & ~wmask) | ((a + bytes) & wmask); // 範囲の中で+bytesし, はみ出したら先頭へ回る / add bytes inside the window, wrapping to its start
        end                                             // WRAPの終わり / end of WRAP
        default: next_addr = a + bytes;                           // INCR  -- 1ビートぶん進める / advance by one beat
      endcase                                           // caseの終わり / end of case
    end                                                 // 関数本体の終わり / end of body
  endfunction                                           // 関数の終わり / end of function

  // ---- 規則違反の検査
  //      (protocol checks)
  task check_addr;                                      // AR/AWのアドレスがAXIの規則に合うか検査するタスク / task: check an AR/AW address against AXI rules
    input [8*2-1:0] ch; input [31:0] a; input [7:0] len; input [2:0] size; // 引数: チャネル名, 番地, 長さ, サイズ ... / args: channel name, address, length, size ...
    input [1:0] burst;                                  // ...バーストの種類 / ... burst type
    begin                                               // タスク本体 / body
      if (size > 3'd2) begin                            // 32bitバスより幅の広いビートは違反 / beats wider than the 32-bit bus are illegal
        $display("AXI ERROR: %s size=%0d is wider than the 32bit bus", ch, size); // 違反を表示 / report it
        errors = errors + 1;                            // 違反数を数える / count it
      end                                               // if の終わり / end of if
      if (burst == 2'b11) begin                         // 予約済みのバースト種類 / reserved burst type
        $display("AXI ERROR: %s reserved burst type", ch); errors = errors + 1; // 違反を表示して数える / report and count
      end                                               // if の終わり / end of if
      if (burst == 2'b01 &&                             // INCRバーストが ... / an INCR burst that ...
          ((a & 32'hfff) + ((len + 1) << size) - 1) > 32'hfff) begin // ...4KB境界をまたぐのは違反 / ... crosses a 4 KB boundary is illegal
        $display("AXI ERROR: %s burst at %h crosses a 4KB boundary", ch, a); // 違反を表示 / report it
        errors = errors + 1;                            // 数える / count it
      end                                               // if の終わり / end of if
    end                                                 // タスク本体の終わり / end of body
  endtask                                               // タスクの終わり / end of task

  reg [ID_W+44:0] ar_prev, aw_prev;                     // 前のサイクルのAR/AWの内容 (ID+番地+長さ+サイズ+種類) / AR/AW contents of the previous cycle (ID + addr + len + size + burst)
  reg [36:0]      w_prev;                               // 前のサイクルのWの内容 {data, strb, last} / W contents of the previous cycle {data, strb, last}
  reg             ar_stall, aw_stall, w_stall;          // 前のサイクルにVALIDなのにREADYが0だった / VALID without READY in the previous cycle
  always @(posedge aclk) begin                          // 「VALIDを出したらREADYまで変えてはいけない」規則の検査 / check the rule "once VALID, hold until READY"
    if (!aresetn) begin                                 // リセット中 / in reset
      ar_stall <= 0; aw_stall <= 0; w_stall <= 0;       // 待ちの印を消す / clear the stall marks
    end else begin                                      // 通常 / normal
      if (ar_stall && (!s_axi_arvalid ||                // ARが待たされていたのにVALIDを下げたか ... / AR was stalled but VALID dropped or ...
          ar_prev != {s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst})) begin // ...内容が変わった / ... the contents changed
        $display("AXI ERROR: AR changed or dropped before ARREADY at %0t", $time); // 違反を表示 / report it
        errors = errors + 1;                            // 数える / count it
      end                                               // if の終わり / end of if
      if (aw_stall && (!s_axi_awvalid ||                // AWについて同じ検査 ... / the same check for AW ...
          aw_prev != {s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst})) begin // ...内容が変わった / ... contents changed
        $display("AXI ERROR: AW changed or dropped before AWREADY at %0t", $time); // 違反を表示 / report it
        errors = errors + 1;                            // 数える / count it
      end                                               // if の終わり / end of if
      if (w_stall && (!s_axi_wvalid ||                  // Wについて同じ検査 ... / the same check for W ...
          w_prev != {s_axi_wdata, s_axi_wstrb, s_axi_wlast})) begin // ...内容が変わった / ... contents changed
        $display("AXI ERROR: W changed or dropped before WREADY at %0t", $time); // 違反を表示 / report it
        errors = errors + 1;                            // 数える / count it
      end                                               // if の終わり / end of if
      ar_stall <= s_axi_arvalid & !s_axi_arready;       // 今サイクルARが待たされたか / was AR stalled this cycle
      aw_stall <= s_axi_awvalid & !s_axi_awready;       // 今サイクルAWが待たされたか / was AW stalled this cycle
      w_stall  <= s_axi_wvalid  & !s_axi_wready;        // 今サイクルWが待たされたか / was W stalled this cycle
      ar_prev  <= {s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst}; // ARの内容を覚える / remember the AR contents
      aw_prev  <= {s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst}; // AWの内容を覚える / remember the AW contents
      w_prev   <= {s_axi_wdata, s_axi_wstrb, s_axi_wlast}; // Wの内容を覚える / remember the W contents
    end                                                 // else の終わり / end of else
  end                                                   // always の終わり / end of always

  // =================================================================
  //  読み出し
  //  Reads
  // =================================================================
  // 【解説】受け付けた読み出しアドレスの表 (最大 QD 個)。1 つの AR = 1 行で、
  //         ビートを返すたびに rq_addr / rq_len を進め, 最後のビートで rq_v を落とす。
  //         rnd=1 では返す行を乱数で選ぶので, ID の違う応答が入れ替わり, ビート単位で
  //         インタリーブする (同じ ID どうしは rq_seq で受付順を守る)。
  //
  // [Note] Table of accepted read addresses (up to QD). One AR = one row; each returned beat
  //        advances rq_addr / rq_len, and the last beat drops rq_v.
  //        With rnd=1 the row to answer is chosen at random, so responses with different IDs swap
  //        order and interleave beat by beat (rq_seq keeps the order within one ID).
  reg            rq_v    [0:QD-1];                      // 読み出し表の行が使用中 / read-table row in use
  reg [ID_W-1:0] rq_id   [0:QD-1];                      // その行のARID / ARID of the row
  reg [31:0]     rq_addr [0:QD-1];                      // 次に返すビートの番地 / address of the next beat to return
  reg [7:0]      rq_len  [0:QD-1];    // 残りビート数 - 1
                                      // remaining beats - 1
  reg [7:0]      rq_olen [0:QD-1];    // 元の ARLEN (WRAP 用)
                                      // original ARLEN (for WRAP)
  reg [2:0]      rq_size [0:QD-1];                      // ARSIZE / ARSIZE  -- 1ビートのサイズ / beat size
  reg [1:0]      rq_burst[0:QD-1];                      // ARBURST / ARBURST  -- バーストの種類 / burst type
  reg [3:0]      rq_wait [0:QD-1];    // 応答を始めるまでのサイクル数
                                      // cycles before the response starts
  integer        rq_seq  [0:QD-1];    // 受付順 (同じ ID の順序を守る)
                                      // acceptance order (keeps the order within one ID)
  integer        rseq, r_cur;                           // 次の受付番号, 今出しているビートの行 (-1=無し) / next sequence number, row of the beat being driven (-1 = none)
  integer        i, j, cnt, start, pick;                // 作業変数 / work variables
  reg            older;                                 // 同じIDでもっと古い行があるか / an older row with the same ID exists

  always @(posedge aclk) begin                          // 読み出し側の動作 (振る舞い記述: ブロッキング代入で表を更新) / read side (behavioural: the table is updated with blocking assignments)
    if (!aresetn) begin                                 // リセット / reset
      for (i = 0; i < QD; i = i + 1) rq_v[i] = 0;       // 表を空に / empty the table
      s_axi_arready <= 0;                               // AR受け付けを止める / stop accepting ARs
      s_axi_rvalid  <= 0;                               // Rを出さない / no R
      s_axi_rlast   <= 0;                               // LASTも0 / LAST 0
      rseq = 0; r_cur = -1;                             // 受付番号と現在行を初期化 / reset sequence number and current row
    end else begin                                      // 通常 / normal
      // ---- 出していたビートが受け取られた
      //      (the beat being driven was taken)
      if (s_axi_rvalid && s_axi_rready) begin           // 出していたビートが受け取られた / the driven beat was taken
        if (rq_len[r_cur] == 0) rq_v[r_cur] = 0;        // 最後のビートなら行を空ける / free the row after its last beat
        else begin                                      // まだ続くなら / more beats follow
          rq_addr[r_cur] = next_addr(rq_addr[r_cur], rq_olen[r_cur], // 次のビートの番地へ ... / advance to the next beat address ...
                                     rq_size[r_cur], rq_burst[r_cur]); // ...(サイズと種類に従う) / ... (by size and type)
          rq_len[r_cur]  = rq_len[r_cur] - 1;           // 残りビート数を減らす / one fewer beat left
        end                                             // else の終わり / end of else
        r_cur = -1;                                     // 出しているビートは無くなった / no beat is being driven now
      end                                               // if の終わり / end of if
      for (i = 0; i < QD; i = i + 1)                    // 全行について / for every row
        if (rq_v[i] && rq_wait[i] != 0) rq_wait[i] = rq_wait[i] - 1; // 応答開始までの待ちを1減らす / count down the wait before responding

      // ---- 次のビートを選ぶ (RVALID を出していない時だけ: 出したら保持)
      //      (choose the next beat; only while not driving RVALID: once driven it is held)
      if (!(s_axi_rvalid && !s_axi_rready)) begin       // RVALIDを出して待たされている間は変えない (規則) / do not change R while stalled (rule)
        pick = -1;                                      // まだ選んでいない / nothing chosen yet
        if (chance(0)) begin                            // 乱数で1/2はこのサイクル何も返さない / randomly skip half the cycles
          start = rnd ? ($random(seed) & 32'h7fffffff) % QD : 0; // 乱数モードでは探し始める行を乱数で決める (応答の順序を入れ替える) / random start row in random mode (reorders responses)
          for (j = 0; j < QD; j = j + 1) begin          // 全行を順に見る / scan every row
            i = (start + j) % QD;                       // 見る行 / row to look at
            if (pick < 0 && rq_v[i] && rq_wait[i] == 0) begin // 使用中で待ちが終わった行 ... / a row in use whose wait is over ...
              // 同じ ID でもっと古いものがあれば, そちらが先
              // if there is an older one with the same ID, it goes first
              older = 0;                                // ...同じIDの古い行があるか調べる / ... check for an older row with the same ID
              for (cnt = 0; cnt < QD; cnt = cnt + 1)    // 全行について / every row
                if (rq_v[cnt] && rq_id[cnt] == rq_id[i] && rq_seq[cnt] < rq_seq[i]) // 同じIDで受付番号が小さい行 / same ID with a smaller sequence number
                  older = 1;                            // あればこの行はまだ返せない (同じIDは順序を守るのがAXIの規則) / then this row must wait (AXI keeps order within an ID)
              if (!older) pick = i;                     // 無ければこの行を選ぶ / otherwise choose this row
            end                                         // if の終わり / end of if
          end                                           // for の終わり / end of for
          // rnd=0 では一番古いものから
          // with rnd=0, the oldest one first
          if (!rnd) begin                               // 乱数モードでなければ / not in random mode
            pick = -1;                                  // 選び直す / choose again
            for (i = 0; i < QD; i = i + 1)              // 全行から ... / among all rows ...
              if (rq_v[i] && rq_wait[i] == 0 && (pick < 0 || rq_seq[i] < rq_seq[pick])) // ...一番古い行 ... / ... the oldest row ...
                pick = i;                               // ...を選ぶ / ... is chosen
          end                                           // if の終わり / end of if
        end                                             // if (chance) の終わり / end of if (chance)
        if (pick >= 0) begin                            // 返す行があれば / a row to answer
          r_cur = pick;                                 // 今出している行 / the row being driven
          s_axi_rvalid <= 1;                            // RVALIDを出す / raise RVALID
          s_axi_rid    <= rq_id[pick];                  // その行のID / that row's ID
          s_axi_rlast  <= (rq_len[pick] == 0);          // 最後のビートか / last beat?
          s_axi_rresp  <= 2'b00;                        // OKAY / OKAY  -- 正常応答 / normal response
          if (is_err(rq_addr[pick])) begin              // エラー領域 (0xE...) なら / error region (0xE...)
            s_axi_rdata <= 32'hBAD0BAD0;                // 目印のデータ / marker data
            s_axi_rresp <= 2'b10;                       // SLVERR  -- スレーブのエラー応答: CPUの例外の試験用 / slave error response: for testing CPU exceptions
            n_rd_err = n_rd_err + 1;                    // エラーを返した数 / count error responses
          end else if (is_dev(rq_addr[pick])) begin     // I/Oデバイス領域 (0xF...) なら / I/O device region (0xF...)
            dev_rd = dev_rd + 1;                        // デバイスの読み出し数 / device read count
            case (rq_addr[pick][7:2])                   // デバイスのレジスタ番号 / device register number
              6'd0: begin s_axi_rdata <= dsw(dev_a); dev_a = dev_a + 1; end // DEV_A: 読むたびに1増える (読み出しに副作用: 投機ロードの検出用) / DEV_A: increments on every read (side effect, to catch speculative loads)
              6'd1:       s_axi_rdata <= dsw(~dev_b);   // DEV_B: 書いた値の反転を返す / DEV_B: returns the inverse of what was written
              default:    s_axi_rdata <= 32'd0;         // その他は0 / others read 0
            endcase                                     // caseの終わり / end of case
          end else                                      // 普通のメモリなら / ordinary memory
            s_axi_rdata <= mem[rq_addr[pick][AW+1:2]];  // メモリの語を返す / return the memory word
        end else begin                                  // 返す行が無ければ / nothing to answer
          s_axi_rvalid <= 0;                            // Rを出さない / no R
          s_axi_rlast  <= 0;                            // LASTも0 / LAST 0
        end                                             // else の終わり / end of else
      end                                               // if の終わり / end of if

      // ---- アドレスの受け付け
      //      (accepting an address)
      if (s_axi_arvalid && s_axi_arready) begin         // ARを受け付けた / an AR was accepted
        check_addr("AR", s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst); // 規則に合うか検査 / check it
        pick = -1;                                      // 空き行を探す / look for a free row
        for (i = QD - 1; i >= 0; i = i - 1) if (!rq_v[i]) pick = i; // 番号の小さい空き行 / the lowest free row
        rq_v[pick]     = 1;                             // 使用中に / mark in use
        rq_id[pick]    = s_axi_arid;                    // IDを記録 / record the ID
        rq_addr[pick]  = s_axi_araddr;                  // 番地を記録 / record the address
        rq_len[pick]   = s_axi_arlen;                   // 残りビート数 / remaining beats
        rq_olen[pick]  = s_axi_arlen;                   // 元の長さ (WRAPの計算用) / original length (for WRAP)
        rq_size[pick]  = s_axi_arsize;                  // サイズ / size
        rq_burst[pick] = s_axi_arburst;                 // 種類 / type
        rq_wait[pick]  = rnd ? ($random(seed) & 7) : 0; // 応答までの待ち (乱数なら0~7サイクル) / wait before responding (0-7 cycles when random)
        rq_seq[pick]   = rseq;                          // 受付番号 / sequence number
        rseq = rseq + 1;                                // 次の受付番号 / next sequence number
        n_rd = n_rd + 1;                                // 読み出しトランザクション数 / read transaction count
      end                                               // if の終わり / end of if
      cnt = 0;                                          // 使用中の行を数える / count rows in use
      for (i = 0; i < QD; i = i + 1) if (rq_v[i]) cnt = cnt + 1; // 使用中なら+1 / +1 per row in use
      s_axi_arready <= (cnt < QD) && chance(0);         // 空きがあればARを受け付ける (乱数で止めることも) / accept ARs while there is room (sometimes stalled at random)
    end                                                 // else の終わり / end of else
  end                                                   // always の終わり / end of always

  // =================================================================
  //  書き込み
  //  Writes
  // =================================================================
  // 【解説】書き込み側は AW / W / B の 3 本の FIFO。AXI では W が AW より先に来てもよいので
  //         別々に貯め, 両方の先頭が揃ったら 1 ビートずつメモリに書き,
  //         バーストの最後のビートで B 応答の FIFO に積む。
  // [Note] The write side has 3 FIFOs, AW / W / B. In AXI, W may come before AW, so they are queued
  //        separately; when both heads are present one beat at a time is written to memory,
  //        and the last beat of a burst pushes a B response onto its FIFO.
  reg [ID_W-1:0] wq_id   [0:QD-1];    // AW の FIFO
                                      // FIFO of AW
  reg [31:0]     wq_addr [0:QD-1];                      // AWのFIFO: 番地 / AW FIFO: address
  reg [7:0]      wq_len  [0:QD-1];                      // AWのFIFO: 残りビート数 / AW FIFO: remaining beats
  reg [7:0]      wq_olen [0:QD-1];                      // AWのFIFO: 元の長さ / AW FIFO: original length
  reg [2:0]      wq_size [0:QD-1];                      // AWのFIFO: サイズ / AW FIFO: size
  reg [1:0]      wq_burst[0:QD-1];                      // AWのFIFO: 種類 / AW FIFO: type
  integer        wq_n;                                  // AWのFIFOの個数 / number of entries in the AW FIFO
  reg [36:0]     wd      [0:7];       // W の FIFO {data, strb, last}
                                      // FIFO of W {data, strb, last}
  integer        wd_n;                                  // WのFIFOの個数 / number of entries in the W FIFO
  reg [ID_W-1:0] bq_id   [0:QD-1];    // B 応答の FIFO
                                      // FIFO of B responses
  reg [1:0]      bq_resp [0:QD-1];                      // BのFIFO: 応答 / B FIFO: response
  reg            w_err;               // 書いているバーストにエラー領域のビートがあった
                                      // the burst being written had a beat in the error region
  integer        bq_n, b_wait;                          // BのFIFOの個数, 次のBまでの待ち / B FIFO count, wait before the next B
  reg [31:0]     wa, wv;                                // 書く番地と語 (作業変数) / address and word being written (work variables)
  reg [36:0]     wbeat;                                 // 取り出したWのビート / the W beat taken out

  always @(posedge aclk) begin                          // 書き込み側の動作 / write side
    if (!aresetn) begin                                 // リセット / reset
      wq_n = 0; wd_n = 0; bq_n = 0; b_wait = 0; w_err = 0; // FIFOを空に / empty the FIFOs
      s_axi_awready <= 0;                               // AWを受け付けない / not ready for AW
      s_axi_wready  <= 0;                               // Wを受け付けない / not ready for W
      s_axi_bvalid  <= 0;                               // Bを出さない / no B
    end else begin                                      // 通常 / normal
      // ---- B 応答が受け取られた
      //      (the B response was taken)
      if (s_axi_bvalid && s_axi_bready) begin           // B応答が受け取られた / the B response was taken
        for (i = 0; i < QD - 1; i = i + 1) begin        // FIFOを1つ詰める / shift the FIFO by one
          bq_id[i] = bq_id[i+1]; bq_resp[i] = bq_resp[i+1]; // 後ろの要素を前へ / move entries forward
        end                                             // for の終わり / end of for
        bq_n = bq_n - 1;                                // 個数を減らす / one fewer entry
        b_wait = rnd ? ($random(seed) & 3) : 0;         // 次のBまでの待ち (乱数なら0~3) / wait before the next B (0-3 when random)
      end                                               // if の終わり / end of if

      // ---- 受け付け
      //      (accepting)
      if (s_axi_awvalid && s_axi_awready) begin         // AWを受け付けた / an AW was accepted
        check_addr("AW", s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst); // 規則に合うか検査 / check it
        wq_id[wq_n]    = s_axi_awid;                    // FIFOの末尾にIDを積む / push the ID
        wq_addr[wq_n]  = s_axi_awaddr;                  // 番地 / address
        wq_len[wq_n]   = s_axi_awlen;                   // 残りビート数 / remaining beats
        wq_olen[wq_n]  = s_axi_awlen;                   // 元の長さ / original length
        wq_size[wq_n]  = s_axi_awsize;                  // サイズ / size
        wq_burst[wq_n] = s_axi_awburst;                 // 種類 / type
        wq_n = wq_n + 1;                                // 個数を増やす / one more entry
        n_wr = n_wr + 1;                                // 書き込みトランザクション数 / write transaction count
      end                                               // if の終わり / end of if
      if (s_axi_wvalid && s_axi_wready) begin           // Wのビートを受け付けた / a W beat was accepted
        wd[wd_n] = {s_axi_wdata, s_axi_wstrb, s_axi_wlast}; // {データ, ストローブ, LAST} をFIFOに積む / push {data, strobes, last}
        wd_n = wd_n + 1;                                // 個数を増やす / one more entry
      end                                               // if の終わり / end of if

      // ---- アドレスとデータが揃ったら 1 ビート書く
      //      (once the address and data are both there, write 1 beat)
      if (wq_n > 0 && wd_n > 0 && bq_n < QD) begin      // 番地とデータが揃い, B応答に空きがあれば / address and data present and room for a B response
        wbeat = wd[0];                                  // Wの先頭を取り出す / take the head W beat
        for (i = 0; i < 7; i = i + 1) wd[i] = wd[i+1];  // WのFIFOを詰める / shift the W FIFO
        wd_n = wd_n - 1;                                // 個数を減らす / one fewer entry
        wa = wq_addr[0];                                // 書く番地 = AWの先頭の今の番地 / write address = current address of the head AW
        if (is_err(wa)) begin                           // エラー領域なら / error region
          w_err = 1;                                    // このバーストはエラー応答にする / this burst gets an error response
        end else if (is_dev(wa)) begin                  // I/Oデバイス領域なら / I/O device region
          if (wa[7:2] == 6'd1) dev_b = dsw(wbeat[36:5]); // DEV_Bに書く / write DEV_B
          if (wa[7:2] == 6'd2) begin wv = dsw(wbeat[36:5]); $write("%c", wv[7:0]); end // DEV_C (コンソール) なら1文字表示 / DEV_C (console): print one character
        end else begin                                  // 普通のメモリなら / ordinary memory
          wv = mem[wa[AW+1:2]];                         // 元の語を読み ... / read the old word ...
          if (wbeat[1]) wv[ 7: 0] = wbeat[12:5];        // ...ストローブ0ならバイト0を置換 ... / ... strobe 0: replace byte lane 0 ...
          if (wbeat[2]) wv[15: 8] = wbeat[20:13];       // ...ストローブ1 ... / ... strobe 1 ...
          if (wbeat[3]) wv[23:16] = wbeat[28:21];       // ...ストローブ2 ... / ... strobe 2 ...
          if (wbeat[4]) wv[31:24] = wbeat[36:29];       // ...ストローブ3 / ... strobe 3
          mem[wa[AW+1:2]] = wv;                         // 書き戻す / write it back
        end                                             // else の終わり / end of else
        if (wbeat[0] != (wq_len[0] == 0)) begin         // WLASTがバースト長と合わなければ違反 / WLAST disagreeing with the burst length is a violation
          $display("AXI ERROR: WLAST=%b does not match the burst length (addr %h)", // 違反を表示 / report it
                   wbeat[0], wa);                       // 表示する値 / values shown
          errors = errors + 1;                          // 数える / count it
        end                                             // if の終わり / end of if
        if (wq_len[0] == 0) begin                       // バーストの最後のビートなら / last beat of the burst
          bq_id[bq_n]   = wq_id[0];                     // B応答をFIFOに積む: ID / push a B response: ID
          bq_resp[bq_n] = w_err ? 2'b10 : 2'b00;        // エラーがあればSLVERR / SLVERR if there was an error
          if (w_err) n_wr_err = n_wr_err + 1;           // エラーを返した数 / count error responses
          w_err = 0;                                    // 次のバーストのためにクリア / clear for the next burst
          bq_n = bq_n + 1;                              // Bの個数を増やす / one more B
          for (i = 0; i < QD - 1; i = i + 1) begin      // AWのFIFOを1つ詰める / shift the AW FIFO by one
            wq_id[i] = wq_id[i+1];       wq_addr[i] = wq_addr[i+1]; // ID, 番地 / ID, address
            wq_len[i] = wq_len[i+1];     wq_olen[i] = wq_olen[i+1]; // 長さ / lengths
            wq_size[i] = wq_size[i+1];   wq_burst[i] = wq_burst[i+1]; // サイズ, 種類 / size, type
          end                                           // for の終わり / end of for
          wq_n = wq_n - 1;                              // AWの個数を減らす / one fewer AW
        end else begin                                  // まだ続くなら / more beats follow
          wq_addr[0] = next_addr(wa, wq_olen[0], wq_size[0], wq_burst[0]); // 次のビートの番地へ / advance to the next beat address
          wq_len[0]  = wq_len[0] - 1;                   // 残りビート数を減らす / one fewer beat left
        end                                             // else の終わり / end of else
      end                                               // if の終わり / end of if

      // ---- B 応答 (出したら BREADY まで保持)
      //      (B response; once driven it is held until BREADY)
      if (!(s_axi_bvalid && !s_axi_bready)) begin       // Bを出して待たされている間は変えない / do not change B while stalled
        if (b_wait > 0) b_wait = b_wait - 1;            // 待ちを数える / count down the wait
        if (bq_n > 0 && b_wait == 0 && chance(0)) begin // 返すBがあり待ちが終わったら / a B to return and the wait is over
          s_axi_bvalid <= 1;                            // BVALIDを出す / raise BVALID
          s_axi_bid    <= bq_id[0];                     // 先頭のID / head ID
          s_axi_bresp  <= bq_resp[0];                   // 先頭の応答 / head response
        end else                                        // 無ければ / otherwise
          s_axi_bvalid <= 0;                            // Bを出さない / no B
      end                                               // if の終わり / end of if

      s_axi_awready <= (wq_n < QD - 1) && chance(0);    // AWのFIFOに空きがあれば受け付ける (乱数で止めることも) / accept AW while the FIFO has room (sometimes stalled)
      s_axi_wready  <= (wd_n < 6) && chance(0);         // WのFIFOに空きがあれば受け付ける / accept W while its FIFO has room
    end                                                 // else の終わり / end of else
  end                                                   // always の終わり / end of always
endmodule                                               // モジュールの終わり / end of module
