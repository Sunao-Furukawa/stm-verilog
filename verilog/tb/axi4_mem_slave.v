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
// =====================================================================
module axi4_mem_slave #(
  parameter AW   = 10,              // 語アドレス幅 (2^AW 語)
  parameter ID_W = 4,
  parameter QD   = 4,               // 読み出し / 書き込みアドレスの受付数
  parameter SWAP = 0                // I/O デバイスの値のバイト入れ替え
) (
  input                 aclk,
  input                 aresetn,
  input                 rnd,        // 1: 乱数でウェイト・順序入れ替え

  input      [ID_W-1:0] s_axi_awid,
  input      [31:0]     s_axi_awaddr,
  input      [7:0]      s_axi_awlen,
  input      [2:0]      s_axi_awsize,
  input      [1:0]      s_axi_awburst,
  input                 s_axi_awvalid,
  output reg            s_axi_awready,
  input      [31:0]     s_axi_wdata,
  input      [3:0]      s_axi_wstrb,
  input                 s_axi_wlast,
  input                 s_axi_wvalid,
  output reg            s_axi_wready,
  output reg [ID_W-1:0] s_axi_bid,
  output reg [1:0]      s_axi_bresp,
  output reg            s_axi_bvalid,
  input                 s_axi_bready,
  input      [ID_W-1:0] s_axi_arid,
  input      [31:0]     s_axi_araddr,
  input      [7:0]      s_axi_arlen,
  input      [2:0]      s_axi_arsize,
  input      [1:0]      s_axi_arburst,
  input                 s_axi_arvalid,
  output reg            s_axi_arready,
  output reg [ID_W-1:0] s_axi_rid,
  output reg [31:0]     s_axi_rdata,
  output reg [1:0]      s_axi_rresp,
  output reg            s_axi_rlast,
  output reg            s_axi_rvalid,
  input                 s_axi_rready
);
  reg [31:0] mem [0:(1<<AW)-1];
  integer    seed;                  // テストベンチから設定してよい
  integer    errors;                // 規則違反の数
  integer    n_rd, n_wr;            // 受け付けたトランザクション数
  integer    dev_rd;                // I/O デバイスが読まれた回数 (ビート数)
  integer    dev_a;                 // DEV_A の値 (= DEV_A が読まれた回数)
  reg [31:0] dev_b;                 // DEV_B に書かれた値
  integer    n_rd_err, n_wr_err;    // エラーを返した数

  function [31:0] dsw;              // I/O デバイスの値 <-> バスの語
    input [31:0] d;
    dsw = SWAP ? {d[7:0], d[15:8], d[23:16], d[31:24]} : d;
  endfunction
  function is_dev;  input [31:0] a; is_dev = (a[31:28] == 4'hF); endfunction
  function is_err;  input [31:0] a; is_err = (a[31:28] == 4'hE); endfunction

  integer k;
  initial begin
    for (k = 0; k < (1<<AW); k = k + 1) mem[k] = 32'd0;
    seed = 1; errors = 0; n_rd = 0; n_wr = 0;
    dev_rd = 0; dev_a = 0; dev_b = 0; n_rd_err = 0; n_wr_err = 0;
  end

  function chance;                  // rnd のとき確率 1/2 で 0
    input dummy;
    chance = !rnd || ($random(seed) & 1);
  endfunction

  // バーストの次の番地
  function [31:0] next_addr;
    input [31:0] a; input [7:0] len; input [2:0] size; input [1:0] burst;
    reg [31:0] bytes, wmask;
    begin
      bytes = 32'd1 << size;
      case (burst)
        2'b00:   next_addr = a;                                   // FIXED
        2'b10: begin                                              // WRAP
          wmask = bytes * (len + 1) - 1;
          next_addr = (a & ~wmask) | ((a + bytes) & wmask);
        end
        default: next_addr = a + bytes;                           // INCR
      endcase
    end
  endfunction

  // ---- 規則違反の検査
  task check_addr;
    input [8*2-1:0] ch; input [31:0] a; input [7:0] len; input [2:0] size;
    input [1:0] burst;
    begin
      if (size > 3'd2) begin
        $display("AXI ERROR: %s size=%0d is wider than the 32bit bus", ch, size);
        errors = errors + 1;
      end
      if (burst == 2'b11) begin
        $display("AXI ERROR: %s reserved burst type", ch); errors = errors + 1;
      end
      if (burst == 2'b01 &&
          ((a & 32'hfff) + ((len + 1) << size) - 1) > 32'hfff) begin
        $display("AXI ERROR: %s burst at %h crosses a 4KB boundary", ch, a);
        errors = errors + 1;
      end
    end
  endtask

  reg [ID_W+44:0] ar_prev, aw_prev;
  reg [36:0]      w_prev;
  reg             ar_stall, aw_stall, w_stall;
  always @(posedge aclk) begin
    if (!aresetn) begin
      ar_stall <= 0; aw_stall <= 0; w_stall <= 0;
    end else begin
      if (ar_stall && (!s_axi_arvalid ||
          ar_prev != {s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst})) begin
        $display("AXI ERROR: AR changed or dropped before ARREADY at %0t", $time);
        errors = errors + 1;
      end
      if (aw_stall && (!s_axi_awvalid ||
          aw_prev != {s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst})) begin
        $display("AXI ERROR: AW changed or dropped before AWREADY at %0t", $time);
        errors = errors + 1;
      end
      if (w_stall && (!s_axi_wvalid ||
          w_prev != {s_axi_wdata, s_axi_wstrb, s_axi_wlast})) begin
        $display("AXI ERROR: W changed or dropped before WREADY at %0t", $time);
        errors = errors + 1;
      end
      ar_stall <= s_axi_arvalid & !s_axi_arready;
      aw_stall <= s_axi_awvalid & !s_axi_awready;
      w_stall  <= s_axi_wvalid  & !s_axi_wready;
      ar_prev  <= {s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst};
      aw_prev  <= {s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst};
      w_prev   <= {s_axi_wdata, s_axi_wstrb, s_axi_wlast};
    end
  end

  // =================================================================
  //  読み出し
  // =================================================================
  reg            rq_v    [0:QD-1];
  reg [ID_W-1:0] rq_id   [0:QD-1];
  reg [31:0]     rq_addr [0:QD-1];
  reg [7:0]      rq_len  [0:QD-1];    // 残りビート数 - 1
  reg [7:0]      rq_olen [0:QD-1];    // 元の ARLEN (WRAP 用)
  reg [2:0]      rq_size [0:QD-1];
  reg [1:0]      rq_burst[0:QD-1];
  reg [3:0]      rq_wait [0:QD-1];    // 応答を始めるまでのサイクル数
  integer        rq_seq  [0:QD-1];    // 受付順 (同じ ID の順序を守る)
  integer        rseq, r_cur;
  integer        i, j, cnt, start, pick;
  reg            older;

  always @(posedge aclk) begin
    if (!aresetn) begin
      for (i = 0; i < QD; i = i + 1) rq_v[i] = 0;
      s_axi_arready <= 0;
      s_axi_rvalid  <= 0;
      s_axi_rlast   <= 0;
      rseq = 0; r_cur = -1;
    end else begin
      // ---- 出していたビートが受け取られた
      if (s_axi_rvalid && s_axi_rready) begin
        if (rq_len[r_cur] == 0) rq_v[r_cur] = 0;
        else begin
          rq_addr[r_cur] = next_addr(rq_addr[r_cur], rq_olen[r_cur],
                                     rq_size[r_cur], rq_burst[r_cur]);
          rq_len[r_cur]  = rq_len[r_cur] - 1;
        end
        r_cur = -1;
      end
      for (i = 0; i < QD; i = i + 1)
        if (rq_v[i] && rq_wait[i] != 0) rq_wait[i] = rq_wait[i] - 1;

      // ---- 次のビートを選ぶ (RVALID を出していない時だけ: 出したら保持)
      if (!(s_axi_rvalid && !s_axi_rready)) begin
        pick = -1;
        if (chance(0)) begin
          start = rnd ? ($random(seed) & 32'h7fffffff) % QD : 0;
          for (j = 0; j < QD; j = j + 1) begin
            i = (start + j) % QD;
            if (pick < 0 && rq_v[i] && rq_wait[i] == 0) begin
              // 同じ ID でもっと古いものがあれば, そちらが先
              older = 0;
              for (cnt = 0; cnt < QD; cnt = cnt + 1)
                if (rq_v[cnt] && rq_id[cnt] == rq_id[i] && rq_seq[cnt] < rq_seq[i])
                  older = 1;
              if (!older) pick = i;
            end
          end
          // rnd=0 では一番古いものから
          if (!rnd) begin
            pick = -1;
            for (i = 0; i < QD; i = i + 1)
              if (rq_v[i] && rq_wait[i] == 0 && (pick < 0 || rq_seq[i] < rq_seq[pick]))
                pick = i;
          end
        end
        if (pick >= 0) begin
          r_cur = pick;
          s_axi_rvalid <= 1;
          s_axi_rid    <= rq_id[pick];
          s_axi_rlast  <= (rq_len[pick] == 0);
          s_axi_rresp  <= 2'b00;
          if (is_err(rq_addr[pick])) begin
            s_axi_rdata <= 32'hBAD0BAD0;
            s_axi_rresp <= 2'b10;                       // SLVERR
            n_rd_err = n_rd_err + 1;
          end else if (is_dev(rq_addr[pick])) begin
            dev_rd = dev_rd + 1;
            case (rq_addr[pick][7:2])
              6'd0: begin s_axi_rdata <= dsw(dev_a); dev_a = dev_a + 1; end
              6'd1:       s_axi_rdata <= dsw(~dev_b);
              default:    s_axi_rdata <= 32'd0;
            endcase
          end else
            s_axi_rdata <= mem[rq_addr[pick][AW+1:2]];
        end else begin
          s_axi_rvalid <= 0;
          s_axi_rlast  <= 0;
        end
      end

      // ---- アドレスの受け付け
      if (s_axi_arvalid && s_axi_arready) begin
        check_addr("AR", s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst);
        pick = -1;
        for (i = QD - 1; i >= 0; i = i - 1) if (!rq_v[i]) pick = i;
        rq_v[pick]     = 1;
        rq_id[pick]    = s_axi_arid;
        rq_addr[pick]  = s_axi_araddr;
        rq_len[pick]   = s_axi_arlen;
        rq_olen[pick]  = s_axi_arlen;
        rq_size[pick]  = s_axi_arsize;
        rq_burst[pick] = s_axi_arburst;
        rq_wait[pick]  = rnd ? ($random(seed) & 7) : 0;
        rq_seq[pick]   = rseq;
        rseq = rseq + 1;
        n_rd = n_rd + 1;
      end
      cnt = 0;
      for (i = 0; i < QD; i = i + 1) if (rq_v[i]) cnt = cnt + 1;
      s_axi_arready <= (cnt < QD) && chance(0);
    end
  end

  // =================================================================
  //  書き込み
  // =================================================================
  reg [ID_W-1:0] wq_id   [0:QD-1];    // AW の FIFO
  reg [31:0]     wq_addr [0:QD-1];
  reg [7:0]      wq_len  [0:QD-1];
  reg [7:0]      wq_olen [0:QD-1];
  reg [2:0]      wq_size [0:QD-1];
  reg [1:0]      wq_burst[0:QD-1];
  integer        wq_n;
  reg [36:0]     wd      [0:7];       // W の FIFO {data, strb, last}
  integer        wd_n;
  reg [ID_W-1:0] bq_id   [0:QD-1];    // B 応答の FIFO
  reg [1:0]      bq_resp [0:QD-1];
  reg            w_err;               // 書いているバーストにエラー領域のビートがあった
  integer        bq_n, b_wait;
  reg [31:0]     wa, wv;
  reg [36:0]     wbeat;

  always @(posedge aclk) begin
    if (!aresetn) begin
      wq_n = 0; wd_n = 0; bq_n = 0; b_wait = 0; w_err = 0;
      s_axi_awready <= 0;
      s_axi_wready  <= 0;
      s_axi_bvalid  <= 0;
    end else begin
      // ---- B 応答が受け取られた
      if (s_axi_bvalid && s_axi_bready) begin
        for (i = 0; i < QD - 1; i = i + 1) begin
          bq_id[i] = bq_id[i+1]; bq_resp[i] = bq_resp[i+1];
        end
        bq_n = bq_n - 1;
        b_wait = rnd ? ($random(seed) & 3) : 0;
      end

      // ---- 受け付け
      if (s_axi_awvalid && s_axi_awready) begin
        check_addr("AW", s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst);
        wq_id[wq_n]    = s_axi_awid;
        wq_addr[wq_n]  = s_axi_awaddr;
        wq_len[wq_n]   = s_axi_awlen;
        wq_olen[wq_n]  = s_axi_awlen;
        wq_size[wq_n]  = s_axi_awsize;
        wq_burst[wq_n] = s_axi_awburst;
        wq_n = wq_n + 1;
        n_wr = n_wr + 1;
      end
      if (s_axi_wvalid && s_axi_wready) begin
        wd[wd_n] = {s_axi_wdata, s_axi_wstrb, s_axi_wlast};
        wd_n = wd_n + 1;
      end

      // ---- アドレスとデータが揃ったら 1 ビート書く
      if (wq_n > 0 && wd_n > 0 && bq_n < QD) begin
        wbeat = wd[0];
        for (i = 0; i < 7; i = i + 1) wd[i] = wd[i+1];
        wd_n = wd_n - 1;
        wa = wq_addr[0];
        if (is_err(wa)) begin
          w_err = 1;
        end else if (is_dev(wa)) begin
          if (wa[7:2] == 6'd1) dev_b = dsw(wbeat[36:5]);
          if (wa[7:2] == 6'd2) begin wv = dsw(wbeat[36:5]); $write("%c", wv[7:0]); end
        end else begin
          wv = mem[wa[AW+1:2]];
          if (wbeat[1]) wv[ 7: 0] = wbeat[12:5];
          if (wbeat[2]) wv[15: 8] = wbeat[20:13];
          if (wbeat[3]) wv[23:16] = wbeat[28:21];
          if (wbeat[4]) wv[31:24] = wbeat[36:29];
          mem[wa[AW+1:2]] = wv;
        end
        if (wbeat[0] != (wq_len[0] == 0)) begin
          $display("AXI ERROR: WLAST=%b does not match the burst length (addr %h)",
                   wbeat[0], wa);
          errors = errors + 1;
        end
        if (wq_len[0] == 0) begin
          bq_id[bq_n]   = wq_id[0];
          bq_resp[bq_n] = w_err ? 2'b10 : 2'b00;
          if (w_err) n_wr_err = n_wr_err + 1;
          w_err = 0;
          bq_n = bq_n + 1;
          for (i = 0; i < QD - 1; i = i + 1) begin
            wq_id[i] = wq_id[i+1];       wq_addr[i] = wq_addr[i+1];
            wq_len[i] = wq_len[i+1];     wq_olen[i] = wq_olen[i+1];
            wq_size[i] = wq_size[i+1];   wq_burst[i] = wq_burst[i+1];
          end
          wq_n = wq_n - 1;
        end else begin
          wq_addr[0] = next_addr(wa, wq_olen[0], wq_size[0], wq_burst[0]);
          wq_len[0]  = wq_len[0] - 1;
        end
      end

      // ---- B 応答 (出したら BREADY まで保持)
      if (!(s_axi_bvalid && !s_axi_bready)) begin
        if (b_wait > 0) b_wait = b_wait - 1;
        if (bq_n > 0 && b_wait == 0 && chance(0)) begin
          s_axi_bvalid <= 1;
          s_axi_bid    <= bq_id[0];
          s_axi_bresp  <= bq_resp[0];
        end else
          s_axi_bvalid <= 0;
      end

      s_axi_awready <= (wq_n < QD - 1) && chance(0);
      s_axi_wready  <= (wd_n < 6) && chance(0);
    end
  end
endmodule
