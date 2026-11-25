// =====================================================================
//  200_if_iwq.vh  <-  hard/200-if-iwq.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】命令キュー IWQ の更新
//
// SFTUP のときは 2 語ずつ前 (0 側) へずらし, 4,5 番には届いた命令
// (I_LBS_H / I_LBS_L) を入れる。4,5 番が空いているときも届いた命令を入れる。
//
// [Note] Updating the instruction queues IWQ
//
// On SFTUP, shift forward (towards 0) by 2 words and put the arrived instructions
// (I_LBS_H / I_LBS_L) into entries 4,5. The arrived instructions also go in when 4,5 are empty.
//
// 【ネットリスト解説】
//   入力 : SFTUP_A / SFTUP_B / SU_IF_CLH_NOCAN / IB_ID (190), I_LBS_H / I_LBS_L (180)
//   出力 (FF): IWQ_A_0..5 / IWQ_B_0..5 (32bit x 12 = 384 本) と有効ビット 6 本 -> 010
//              IWQ_A_V45 / IWQ_B_V45 -> 190 (SFTUP の判定) にも
//   回路の形: 2 本のシフトレジスタ (2 語単位で 0 側へずれる)。
//     ・0〜3 番: D 入力は「SFTUP ? 2 つ後ろの語 : 保持」。保持は CE になるので、
//       前の段の FF の Q をそのまま次の FF の D につなぎ、SFTUP を CE にするだけ
//       (LUT 不要)。
//     ・4,5 番: D は I_LBS_H / I_LBS_L, CE は (SFTUP | !V45)。
//       両方のキューの 4,5 番が同じ I_LBS_H/L を受け取り、どちらに入るかは
//       有効ビット側 (SU_IF_CLH_NOCAN & IB_ID) だけで決まる。データの FF は
//       「入れてもよい」ときに上書きされるだけで、有効ビットが 0 なら中身は使われない。
//     ・キューの FF は 384 本で、stm_cntl の FF の約 1/4 を占める。
//
// [Netlist notes]
//   Inputs : SFTUP_A / SFTUP_B / SU_IF_CLH_NOCAN / IB_ID (190), I_LBS_H / I_LBS_L (180)
//   Outputs (FFs): IWQ_A_0..5 / IWQ_B_0..5 (32 bits x 12 = 384 bits) and 6 valid bits -> 010
//                  IWQ_A_V45 / IWQ_B_V45 also -> 190 (SFTUP decision)
//   Circuit: two shift registers (shifting towards 0 two words at a time).
//     - Entries 0-3: D is "SFTUP ? the word two places behind : hold". The hold becomes CE,
//       so the Q of one FF is wired straight to the D of the next and SFTUP drives CE
//       (no LUT needed).
//     - Entries 4,5: D is I_LBS_H / I_LBS_L, CE is (SFTUP | !V45).
//       Entries 4,5 of both queues receive the same I_LBS_H/L; which queue the data really
//       enters is decided only on the valid-bit side (SU_IF_CLH_NOCAN & IB_ID). The data FFs are
//       simply overwritten whenever loading is allowed, and their contents are ignored while
//       the valid bit is 0.
//     - The queues have 384 FFs, about a quarter of the FFs in stm_cntl.
// ---------------------------------------------------------------------

// if-iwq
// Next State of Insn Word Queue

// IWQ :

  // 【解説】キュー A のシフト (2,3 → 0,1 / 4,5 → 2,3) と有効ビットのシフト。
  // [Note] Shift of queue A (2,3 -> 0,1 / 4,5 -> 2,3) and of its valid bits.
  assign IWQ_A_0_NEW = SFTUP_A ?  IWQ_A_2   : IWQ_A_0;
  assign IWQ_A_1_NEW = SFTUP_A ?  IWQ_A_3   : IWQ_A_1;
  assign IWQ_A_2_NEW = SFTUP_A ?  IWQ_A_4   : IWQ_A_2;
  assign IWQ_A_3_NEW = SFTUP_A ?  IWQ_A_5   : IWQ_A_3;
  assign IWQ_A_V01_NEW = SFTUP_A ?  IWQ_A_V23   : IWQ_A_V01;
  assign IWQ_A_V23_NEW = SFTUP_A ?  IWQ_A_V45   : IWQ_A_V23;

  // 【解説】キュー B も同じ。
  // [Note] The same for queue B.
  assign IWQ_B_0_NEW = SFTUP_B ?  IWQ_B_2   : IWQ_B_0;
  assign IWQ_B_1_NEW = SFTUP_B ?  IWQ_B_3   : IWQ_B_1;
  assign IWQ_B_2_NEW = SFTUP_B ?  IWQ_B_4   : IWQ_B_2;
  assign IWQ_B_3_NEW = SFTUP_B ?  IWQ_B_5   : IWQ_B_3;
  assign IWQ_B_V01_NEW = SFTUP_B ?  IWQ_B_V23   : IWQ_B_V01;
  assign IWQ_B_V23_NEW = SFTUP_B ?  IWQ_B_V45   : IWQ_B_V23;

// 【解説】4,5 番はシフトしたか空いていれば、フェッチで届いた 8 バイトを入れる。
// [Note] If entries 4,5 shifted or are empty, put in the 8 bytes that arrived from the fetch.
assign IWQ_A_4_NEW = SFTUP_A | !IWQ_A_V45 ? I_LBS_H : IWQ_A_4;
assign IWQ_A_5_NEW = SFTUP_A | !IWQ_A_V45 ? I_LBS_L : IWQ_A_5;

assign IWQ_B_4_NEW = SFTUP_B | !IWQ_B_V45 ? I_LBS_H : IWQ_B_4;
assign IWQ_B_5_NEW = SFTUP_B | !IWQ_B_V45 ? I_LBS_L : IWQ_B_5;


// 【解説】4,5 番の有効ビット: シフトで空になり、このキュー宛ての命令が届けば 1。
// [Note] Valid bit of entries 4,5: becomes 1 when, after a shift empties it, instructions for this queue arrive.
assign IWQ_A_V45_NEW = IWQ_A_V45 & !SFTUP_A | SU_IF_CLH_NOCAN & !IB_ID;
assign IWQ_B_V45_NEW = IWQ_B_V45 & !SFTUP_B | SU_IF_CLH_NOCAN &  IB_ID;
