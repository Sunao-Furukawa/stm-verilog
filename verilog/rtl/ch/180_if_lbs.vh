// =====================================================================
//  180_if_lbs.vh  <-  hard/180-if-lbs.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】命令キャッシュ側の応答
//
// SU_IF_RDY : フェッチ要求を受け付けた
// SU_IF_CLH : 要求していた 8 バイトが届いた (キャッシュヒット)
// キャッシュミス模擬が無効 (RANDOM_* = 1) なら、要求の次のサイクルに必ず届く。
// ---------------------------------------------------------------------

// if-lbs

// For cache miss simulation

// ---- #ifndef VHDL ----
// RANDOM-FOR-IFRDY = random_clh ? ((random() & 0xf) >= 8) : 1
// RANDOM-FOR-IFCLH = random_clh ? ((random() & 0xf) >= 8) : 1
//   -> Verilog 版では stm_cntl の入力ポート RANDOM_FOR_IFRDY / RANDOM_FOR_IFCLH。
// ---- #endif ----

// 【解説】要求中 (IB_V) の命令データが届いた。
assign SU_IF_CLH = IB_V     & RANDOM_FOR_IFCLH;
// 【解説】新しいフェッチ要求を受け付けられるか (要求中のものが無いか, ちょうど届いた)。
assign SU_IF_RDY = IF_REQ_V & RANDOM_FOR_IFRDY & (!IB_V | SU_IF_CLH)
		 | START_TRIGGER;

  // 【解説】届いた 2 命令 (上位 = 先の命令)。届いていないときは目印のダミー値。
  assign I_LBS_H = SU_IF_CLH ? MEM_DT_IF_H : 32'hf0f0f0f0;
  assign I_LBS_L = SU_IF_CLH ? MEM_DT_IF_L : 32'hff0f0f0f;
