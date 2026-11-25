// =====================================================================
//  180_if_lbs.vh  <-  hard/180-if-lbs.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】命令キャッシュ側の応答
//
// SU_IF_RDY : フェッチ要求を受け付けた
// SU_IF_CLH : 要求していた 8 バイトが届いた (キャッシュヒット)
// キャッシュミス模擬が無効 (RANDOM_* = 1) なら、要求の次のサイクルに必ず届く。
//
// [Note] Response of the instruction cache side
//
// SU_IF_RDY : the fetch request was accepted
// SU_IF_CLH : the requested 8 bytes have arrived (cache hit)
// With cache-miss simulation off (RANDOM_* = 1), they always arrive in the cycle after the request.
//
// 【ネットリスト解説】
//   入力 : IB_V (190 の FF), IF_REQ_V (170), START_TRIGGER (080),
//          ポート RANDOM_FOR_IFCLH / RANDOM_FOR_IFRDY / MEM_DT_IF_H / MEM_DT_IF_L
//   出力 : SU_IF_CLH / SU_IF_RDY -> 190 ;  I_LBS_H / I_LBS_L -> 200 (IWQ の 4,5 番)
//   回路の形: 1bit の AND 2 つと、32bit x 2 の 2:1 MUX (届いていなければダミー値)。
//     メモリ (または stm_icache) の出力 MEM_DT_IF_H/L が、この MUX と 200 の MUX を
//     通ってそのまま IWQ の FF に入る。命令フェッチのデータ側の経路は短い。
//
// [Netlist notes]
//   Inputs : IB_V (FF in 190), IF_REQ_V (170), START_TRIGGER (080),
//            ports RANDOM_FOR_IFCLH / RANDOM_FOR_IFRDY / MEM_DT_IF_H / MEM_DT_IF_L
//   Outputs: SU_IF_CLH / SU_IF_RDY -> 190 ;  I_LBS_H / I_LBS_L -> 200 (entries 4,5 of the IWQ)
//   Circuit: two 1-bit ANDs and 32-bit x 2 2:1 muxes (a dummy value when nothing arrived).
//     The output of the memory (or stm_icache), MEM_DT_IF_H/L, goes through this mux and the
//     mux in 200 straight into the IWQ FFs. The data path of instruction fetch is short.
// ---------------------------------------------------------------------

// if-lbs

// For cache miss simulation

// ---- #ifndef VHDL ----
// RANDOM-FOR-IFRDY = random_clh ? ((random() & 0xf) >= 8) : 1
// RANDOM-FOR-IFCLH = random_clh ? ((random() & 0xf) >= 8) : 1
//   -> Verilog 版では stm_cntl の入力ポート RANDOM_FOR_IFRDY / RANDOM_FOR_IFCLH。
//   -> In the Verilog version these are the input ports RANDOM_FOR_IFRDY / RANDOM_FOR_IFCLH of stm_cntl.
// ---- #endif ----

// 【解説】要求中 (IB_V) の命令データが届いた。
// [Note] The instruction data of the pending request (IB_V) has arrived.
assign SU_IF_CLH = IB_V     & RANDOM_FOR_IFCLH;
// 【解説】新しいフェッチ要求を受け付けられるか (要求中のものが無いか, ちょうど届いた)。
// [Note] Can a new fetch request be accepted (nothing pending, or it just arrived)?
assign SU_IF_RDY = IF_REQ_V & RANDOM_FOR_IFRDY & (!IB_V | SU_IF_CLH)
		 | START_TRIGGER;

  // 【解説】届いた 2 命令 (上位 = 先の命令)。届いていないときは目印のダミー値。
  // [Note] The 2 instructions that arrived (upper = the earlier one). A marker dummy value when nothing arrived.
  assign I_LBS_H = SU_IF_CLH ? MEM_DT_IF_H : 32'hf0f0f0f0;
  assign I_LBS_L = SU_IF_CLH ? MEM_DT_IF_L : 32'hff0f0f0f;
