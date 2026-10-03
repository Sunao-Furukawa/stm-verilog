// =====================================================================
//  200_if_iwq.vh  <-  hard/200-if-iwq.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】命令キュー IWQ の更新
//
// SFTUP のときは 2 語ずつ前 (0 側) へずらし, 4,5 番には届いた命令
// (I_LBS_H / I_LBS_L) を入れる。4,5 番が空いているときも届いた命令を入れる。
// ---------------------------------------------------------------------

// if-iwq
// Next State of Insn Word Queue

// IWQ :

  // 【解説】キュー A のシフト (2,3 → 0,1 / 4,5 → 2,3) と有効ビットのシフト。
  assign IWQ_A_0_NEW = SFTUP_A ?  IWQ_A_2   : IWQ_A_0;
  assign IWQ_A_1_NEW = SFTUP_A ?  IWQ_A_3   : IWQ_A_1;
  assign IWQ_A_2_NEW = SFTUP_A ?  IWQ_A_4   : IWQ_A_2;
  assign IWQ_A_3_NEW = SFTUP_A ?  IWQ_A_5   : IWQ_A_3;
  assign IWQ_A_V01_NEW = SFTUP_A ?  IWQ_A_V23   : IWQ_A_V01;
  assign IWQ_A_V23_NEW = SFTUP_A ?  IWQ_A_V45   : IWQ_A_V23;

  // 【解説】キュー B も同じ。
  assign IWQ_B_0_NEW = SFTUP_B ?  IWQ_B_2   : IWQ_B_0;
  assign IWQ_B_1_NEW = SFTUP_B ?  IWQ_B_3   : IWQ_B_1;
  assign IWQ_B_2_NEW = SFTUP_B ?  IWQ_B_4   : IWQ_B_2;
  assign IWQ_B_3_NEW = SFTUP_B ?  IWQ_B_5   : IWQ_B_3;
  assign IWQ_B_V01_NEW = SFTUP_B ?  IWQ_B_V23   : IWQ_B_V01;
  assign IWQ_B_V23_NEW = SFTUP_B ?  IWQ_B_V45   : IWQ_B_V23;

// 【解説】4,5 番はシフトしたか空いていれば、フェッチで届いた 8 バイトを入れる。
assign IWQ_A_4_NEW = SFTUP_A | !IWQ_A_V45 ? I_LBS_H : IWQ_A_4;
assign IWQ_A_5_NEW = SFTUP_A | !IWQ_A_V45 ? I_LBS_L : IWQ_A_5;

assign IWQ_B_4_NEW = SFTUP_B | !IWQ_B_V45 ? I_LBS_H : IWQ_B_4;
assign IWQ_B_5_NEW = SFTUP_B | !IWQ_B_V45 ? I_LBS_L : IWQ_B_5;


// 【解説】4,5 番の有効ビット: シフトで空になり、このキュー宛ての命令が届けば 1。
assign IWQ_A_V45_NEW = IWQ_A_V45 & !SFTUP_A | SU_IF_CLH_NOCAN & !IB_ID;
assign IWQ_B_V45_NEW = IWQ_B_V45 & !SFTUP_B | SU_IF_CLH_NOCAN &  IB_ID;
