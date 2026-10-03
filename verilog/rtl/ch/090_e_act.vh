// =====================================================================
//  090_e_act.vh  <-  hard/090-e-act.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】E サイクル: LS パイプの ALU と、W サイクルへの受け渡し
//
// ・メモリオペランド演算 (EX-RM) や、サブワードのロード/ストアの整形を
//   ALU (stm_exu) で行う
// ・割り込みの整理: 同じ組の 2 命令のうち、プログラム順で先の命令に割り込みが
//   出たら後の命令の結果は捨てる (HIDE)
// ・結果を W サイクルの FF (W_*) へ渡す
// ・ストアのデータはストアバッファ STB (1 エントリ) に入れる
// ---------------------------------------------------------------------

// e-act : e-cyc activity

// Bypass STB if address matches (Store-Load Bypass) ## move this part to SU?
// 【解説】メモリから読んだデータ (ALU の第 2 入力)。
assign EE_MEMOP = E_LS_LD_DT;
// ---- #if 0 (元ソースで無効化) ----
// EE-MEMOP = (E-LS-LD-V & STB-V & (E-LS-LOG-AD == STB-AD)) ? STB-DT : E-LS-LD-DT
// ---- #endif ----

// Bypass register if E-reg-num matches W-reg-num. (E-cyc to A-cyc Bypass)
// 【解説】レジスタから読んだオペランド (ストアデータ / EX-RM の第 1 オペランド)。
assign EE_OPS = E_LS_OPS_DT;
// ---- #if 0 (元ソースで無効化) ----
//    (E-LS-OPS-IS-GR & E-WE2 & (E-LS-RADS == E-WAD2) & E-FIRST-IS-EX) ? E-EX-RES :
//    (E-LS-OPS-IS-GR & W-WE1 & (E-LS-RADS == W-WAD1))	? W-WDT1  :
//    (E-LS-OPS-IS-GR & W-WE2 & (E-LS-RADS == W-WAD2))  	? W-WDT2  : E-LS-OPS-DT
// ---- #endif ----

// ---- #ifndef VHDL ----
// exu(E-LS-OPCODE,EE-OPS,EE-MEMOP,&EE-ALU-CC,&EE-ALU-OUTPUT,&EE-ALU-INT);
//   -> C 関数呼び出しを EXU モジュールのインスタンスに置き換え (LS パイプの ALU)
// 【解説】LS パイプの ALU。opcode は 110_b_act.vh で作った E_LS_OPCODE:
//           0 (LDW) ならロードデータをそのまま, 4 (STW) ならストアデータをそのまま,
//           16 以上はバイト/ハーフワードの切り出し・はめ込み, 1〜14 は EX-RM の演算。
stm_exu u_e_alu (
  .opc  (E_LS_OPCODE),
  .x    (EE_OPS),
  .y    (EE_MEMOP),
  .cc   (EE_ALU_CC),
  .z    (EE_ALU_OUTPUT),
  .intr (EE_ALU_INT)
);
// ---- #endif ----

// Handling of interruption

// 【解説】LS パイプの割り込み: S ユニットからの例外か、ALU のオーバーフロー。
assign EE_LS_INTCODE = (E_LS_INTCODE != 0) ? E_LS_INTCODE : EE_ALU_INT;
assign EE_LS_INT_V = (EE_LS_INTCODE != 0);
assign EE_EX_INT_V = (E_EX_INTCODE != 0);
// 【解説】同じ組の先の命令が割り込んだら、後の命令の結果を隠す。
//           E_FIRST_IS_EX = 1 なら EX パイプ側がプログラム順で先。
assign EE_HIDE_EX = !E_FIRST_IS_EX & EE_LS_INT_V;
assign EE_HIDE_LS =  E_FIRST_IS_EX & EE_EX_INT_V;

// 【解説】CC をどちらのパイプの結果で更新するか。両方が CC を変えるなら
//         プログラム順で後の命令を採る (同時発行の段階で両方が CC を変える組は
//         作らないが、式としては両方の場合を扱っている)。
assign EE_SET_CC_FROM_LS = E_LS_SETCC & !EE_LS_INT_V & !EE_HIDE_LS
			& !(E_EX_SETCC & !E_FIRST_IS_EX & !EE_EX_INT_V);
assign EE_SET_CC_FROM_EX = E_EX_SETCC & !EE_EX_INT_V & !EE_HIDE_EX
			& !(E_LS_SETCC &  E_FIRST_IS_EX & !EE_LS_INT_V);
//##   Set w-tags
//##   These tags can be always copied to W-cyc
  // 【解説】値の種類のタグは無条件に W へコピーしてよい (有効ビットで制御するため)。
  assign W_WAD1_NEW = E_WAD1;
  assign W_WAD2_NEW = E_WAD2;
  assign W_WDT1_NEW = EE_ALU_OUTPUT;
  assign W_WDT2_NEW = E_EX_RES;
  assign W_TGT_NEW = E_TGT;
  assign W_IS_SUPERSCALAR_NEW = E_IS_SUPERSCALAR;
  assign W_LATTER_IS_JB_NEW = E_LATTER_IS_JB;
  assign W_FIRST_IS_EX_NEW = E_FIRST_IS_EX;
  assign W_CC_NEW = ( EE_SET_CC_FROM_LS ? EE_ALU_CC : E_EX_CC );

// if (!E-FWD) # In next cycle, E-cyc won't release and W-cyc will be empty
// 	      # except STB, which depends on INTLK.  Clear GR/CC/PC valids.
  // 【解説】有効ビット類は E が進むとき (E_FWD) だけセットし、そうでなければ 0
  //         (W は空になる)。割り込みを起こした命令は GR に書かない。
  assign W_WE1_NEW = E_FWD ?  E_WE1 & !EE_LS_INT_V & !EE_HIDE_LS   : 0;
  assign W_WE2_NEW = E_FWD ?  E_WE2 & !EE_EX_INT_V & !EE_HIDE_EX   : 0;
  assign W_SETCC_NEW = E_FWD ?  EE_SET_CC_FROM_LS | EE_SET_CC_FROM_EX   : 0;
  assign W_COMPLETE_NEW = E_FWD ?  1   : 0;
  assign W_PRIVCODE_NEW = E_FWD ?  E_PRIVCODE   : 0;
  assign W_EX_INTCODE_NEW = E_FWD ?  E_EX_INTCODE   : 0;
  assign W_LS_INTCODE_NEW = E_FWD ?  EE_LS_INTCODE	: 0;

// Set W-JB-V iff branch is taken.
// Usually E-cyc ALU-CC is first latched in G-XXX and then
// used.  Setting W-JB-V is the only exception, where
// ALU-CC is used directly, i.e. in the same cycle.
  // 【解説】W で分岐を実行するか (taken の分岐だけ 1)。未解決だった BC が
  //         この E サイクルで解決する場合は、ALU の CC を直接見て判定する。
  assign W_JB_V_NEW = E_FWD ?  E_JB_V & (!E_JB_IS_BC | E_LS_SOLVING_BC
		 & cc_match(EE_ALU_CC,G_BC_MASK) | G_BC_JUST_TAKEN) : 0;

// 【解説】ストアバッファ: E のストアが進むときにアドレスとデータを入れ、
//         S ユニットが ST2 を受け付けたら (WW_ST_GO) 空になる。
assign STB_V_NEW = ( STB_V & !WW_ST_GO ) | E_LS_ST_V & E_FWD & !EE_HIDE_LS;

  assign STB_AD_NEW = E_FWD & E_LS_ST_V ? E_LS_LOG_AD    : STB_AD;
  assign STB_DT_NEW = E_FWD & E_LS_ST_V ? EE_ALU_OUTPUT  : STB_DT;
