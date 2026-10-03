// =====================================================================
//  010_d_pre.vh  <-  hard/010-d-pre.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D サイクル(1): 命令キューから発行候補の 2 命令 I0, I1 を取り出す
//
// STM は分岐予測のため命令キュー (IWQ) を A, B の 2 本持つ。
//   ・一方は「今実行している流れ」、もう一方は「予測しなかった側の流れ」
//   ・どちらが今の流れかは CUR_IWQ_ID (FF) が示す
// 各キューは 6 語 (IWQ_x_0..5) で、2 語 (8 バイト) 単位で有効ビット
// V01 / V23 / V45 を持つ。命令は 8 バイト (2 命令) ずつフェッチされ 4,5 番に入り、
// 消費が進むと 2 語ずつ前 (0 側) へシフトする (200_if_iwq.vh)。
//
// NIP (Next Insn Pointer) はキューの中で次に発行する命令の位置:
//   0..5 : その位置の命令を次に発行する
//   6, 7 : 次の命令はこれから届く 8 バイトの 0 / 1 語目 (キューは空)
// I0 = NIP の位置の命令、I1 = その次 (NIP+1) の命令。
// ---------------------------------------------------------------------

// d-pre : Insn Presentation
// Selecting insn from IWQs


//    IWQ-A0 B0  A1 B1         A5 B5                                   #
//         | |    | |           | |                                    #
//        -----  -----  ...    -----  <-- EID                          #
//          |      |             |                                     #
//         C0     C1            C5  (IWQ)                              #

//       C0 C1    C5      C1    C5                                     #
//        |  | ..  |       | ..  |                                     #
//       ------------     ---------   <-- NIPA/B                       #
//             |              |                                        #
//           INSN0          INSN1                                      #


// 'Effective' ID, which should be presented
// Dont forget to CUR-ID := EID even if !DRel.

// 【解説】Effective ID: このサイクルで実際に使うキュー (0=A, 1=B)。
//         前サイクルで条件分岐が解決し (G_BC_JUST_SOLVED)、予測 (G_BC_TKN_PREDICTED) と
//         実際 (G_BC_JUST_TAKEN) が食い違っていたら、もう一方のキューへ即座に切り替える。
assign EID = CUR_IWQ_ID ^ (G_BC_JUST_SOLVED & (G_BC_JUST_TAKEN ^ G_BC_TKN_PREDICTED) );

// 【解説】EID で選んだ側のキューの 6 語。
assign IWQ_0 = (EID ? IWQ_B_0 : IWQ_A_0);
assign IWQ_1 = (EID ? IWQ_B_1 : IWQ_A_1);
assign IWQ_2 = (EID ? IWQ_B_2 : IWQ_A_2);
assign IWQ_3 = (EID ? IWQ_B_3 : IWQ_A_3);
assign IWQ_4 = (EID ? IWQ_B_4 : IWQ_A_4);
assign IWQ_5 = (EID ? IWQ_B_5 : IWQ_A_5);

// 【解説】NIP_A は FF に「値 ^ 6」の形で格納している (NIP_A_REG)。
//         こうするとリセット (0) 直後の NIP_A が 6 = 「キューは空」になる。
assign NIP_A = NIP_A_REG ^ 6;
// 【解説】選択中のキューの NIP と、その値ごとのデコード信号。
assign NIP = (EID ? NIP_B     : NIP_A);
assign NIP_0 = (NIP == 0);
assign NIP_1 = (NIP == 1);
assign NIP_2 = (NIP == 2);
assign NIP_3 = (NIP == 3);
assign NIP_4 = (NIP == 4);
assign NIP_5 = (NIP == 5);

// 【解説】選択中のキューの有効ビット (2 語ごと)。
assign V01 = (EID ? IWQ_B_V01 : IWQ_A_V01);
assign V23 = (EID ? IWQ_B_V23 : IWQ_A_V23);
assign V45 = (EID ? IWQ_B_V45 : IWQ_A_V45);

// 【解説】I0 / I1 が有効か: その命令が入っている 2 語ペアの有効ビットを見る。
//         I1 は NIP+1 の位置なので、NIP=5 (キューの最後) なら I1 は無い。
assign I0_V = (NIP_0 | NIP_1) ? V01 : (NIP_2 | NIP_3) ? V23 : (NIP_4 | NIP_5) ? V45 : 0;
assign I1_V = (NIP_0        ) ? V01 : (NIP_1 | NIP_2) ? V23 : (NIP_3 | NIP_4) ? V45 : 0;

// 【解説】NIP の位置の命令語 (無効なら 0)。
assign I0_CANDID = NIP_0 ? IWQ_0 : NIP_1 ? IWQ_1 : NIP_2 ? IWQ_2 :
            NIP_3 ? IWQ_3 : NIP_4 ? IWQ_4 : NIP_5 ? IWQ_5 : 0;
assign I0 = I0_V ? I0_CANDID : 0;

// 【解説】NIP+1 の位置の命令語 (無効なら 0)。
assign I1_CANDID = NIP_0 ? IWQ_1 : NIP_1 ? IWQ_2 : NIP_2 ? IWQ_3 :
            NIP_3 ? IWQ_4 : NIP_4 ? IWQ_5 : 0;
assign I1 = I1_V ? I1_CANDID : 0;


//# These are solely for simulation convenience (serve as probe) ##

//IWQA-PROBE-H = ((IWQ-A[0] & 0xff000000)>>8)|((IWQ-A[1] & 0xff000000)>>16)
//                                           |((IWQ-A[2] & 0xff000000)>>24)
//IWQA-PROBE-L = ((IWQ-A[3] & 0xff000000)>>8)|((IWQ-A[4] & 0xff000000)>>16)
//                                           |((IWQ-A[5] & 0xff000000)>>24)
//IWQB-PROBE-H = ((IWQ-B[0] & 0xff000000)>>8)|((IWQ-B[1] & 0xff000000)>>16)
//                                           |((IWQ-B[2] & 0xff000000)>>24)
//IWQB-PROBE-L = ((IWQ-B[3] & 0xff000000)>>8)|((IWQ-B[4] & 0xff000000)>>16)
//                                           |((IWQ-B[5] & 0xff000000)>>24)

