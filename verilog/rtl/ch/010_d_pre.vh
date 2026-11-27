// =====================================================================
//  010_d_pre.vh  <-  hard/010-d-pre.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
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
//
// [Note] D cycle (1): take the two issue candidates I0, I1 out of the instruction queues
//
// For branch prediction STM has two instruction queues (IWQ), A and B.
//   - one holds "the stream being executed", the other "the stream not predicted"
//   - which one is current is shown by CUR_IWQ_ID (an FF)
// Each queue has 6 words (IWQ_x_0..5) with a valid bit per 2 words (8 bytes):
// V01 / V23 / V45. Instructions are fetched 8 bytes (2 instructions) at a time into
// entries 4,5, and as they are consumed they shift forward (towards 0) 2 words at a time (200_if_iwq.vh).
//
// NIP (Next Insn Pointer) is the position in the queue of the next instruction to issue:
//   0..5 : the instruction at that position issues next
//   6, 7 : the next instruction is word 0 / 1 of the 8 bytes still to arrive (queue empty)
// I0 = the instruction at NIP, I1 = the one after it (NIP+1).
//
// 【ネットリスト解説】
//   入力 (FF): IWQ_A_0..5 / IWQ_B_0..5 と有効ビット (200), NIP_A_REG / NIP_B /
//              CUR_IWQ_ID (190), G_BC_JUST_SOLVED / _TAKEN / _TKN_PREDICTED (210)
//   出力     : I0, I1, I0_V, I1_V            -> 015, 030 (デコードと発行)
//              EID                           -> 040, 170, 190 (どちらのキューを使うか)
//              NIP, NIP_0..5, V01/V23/V45    -> 040 (分岐命令の番地), 170 (キュー満杯)
//              NIP_A                         -> 190 (NIP の更新)
//   回路の形:
//     1. EID       : FF 4 本から作る XOR/AND 1 段 (LUT 1 個)。
//     2. IWQ_0..5  : 32bit x 6 語ぶんの 2:1 MUX (選択 = EID)。
//     3. I0 / I1   : NIP をデコードした NIP_0..5 で選ぶ 6:1 / 5:1 MUX (32bit 幅)。
//        2 と 3 は合成で 1 つにまとめられ、12 語 (A, B 各 6 語) から 1 語を選ぶ
//        MUX になる (LUT6 + MUXF7 の木)。
//   EID は 192 本 (32bit x 6) の MUX の選択信号に配られるので、ファンアウトが大きい。
//   EID の元の G_BC_* は前のサイクルの FF なので、分岐予測ミスのキュー切り替えは
//   「解決した次のサイクル」に組合せ回路だけで即座に効く (1 サイクルも無駄にしない)。
//
// [Netlist notes]
//   Inputs (FFs): IWQ_A_0..5 / IWQ_B_0..5 and their valid bits (200), NIP_A_REG / NIP_B /
//                 CUR_IWQ_ID (190), G_BC_JUST_SOLVED / _TAKEN / _TKN_PREDICTED (210)
//   Outputs     : I0, I1, I0_V, I1_V            -> 015, 030 (decode and issue)
//                 EID                           -> 040, 170, 190 (which queue is used)
//                 NIP, NIP_0..5, V01/V23/V45    -> 040 (address of a branch), 170 (queue full)
//                 NIP_A                         -> 190 (NIP update)
//   Circuit:
//     1. EID       : one XOR/AND level built from 4 FFs (1 LUT).
//     2. IWQ_0..5  : 2:1 muxes for 6 words x 32 bits (select = EID).
//     3. I0 / I1   : 6:1 / 5:1 muxes (32 bits wide) selected by the decoded NIP_0..5.
//        Synthesis merges 2 and 3 into one mux that picks 1 word out of 12
//        (6 words each for A and B), built as a tree of LUT6 + MUXF7.
//   EID is the select of 192 mux bits (32 bits x 6), so its fan-out is large.
//   The G_BC_* that drive EID are FFs from the previous cycle, so switching queues after a
//   misprediction takes effect through logic alone in the cycle after resolution (no cycle wasted).
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
// [Note] Effective ID: the queue actually used in this cycle (0=A, 1=B).
//        If a conditional branch was resolved in the previous cycle (G_BC_JUST_SOLVED) and
//        the prediction (G_BC_TKN_PREDICTED) and the outcome (G_BC_JUST_TAKEN) differ,
//        switch to the other queue at once.
assign EID = CUR_IWQ_ID ^ (G_BC_JUST_SOLVED & (G_BC_JUST_TAKEN ^ G_BC_TKN_PREDICTED) ); // 予測ミスなら現キューを反転: FF4本→XOR/AND→LUT4 1個, 192本のMUX選択線へ高ファンアウト / flip queue on mispredict: 4 FFs -> one LUT4, high fan-out select of 192 mux bits

// 【解説】EID で選んだ側のキューの 6 語。
// [Note] The 6 words of the queue selected by EID.
assign IWQ_0 = (EID ? IWQ_B_0 : IWQ_A_0);               // キューA/Bの0語目を選ぶ: 32bit 2:1 MUX (後段I0/I1のMUXと合成で融合) / word 0 of queue A/B: 32-bit 2:1 mux (merged with the I0/I1 mux)
assign IWQ_1 = (EID ? IWQ_B_1 : IWQ_A_1);               // 1語目の2:1 MUX (選択=EID, 32本のLUT入力) / 2:1 mux for word 1 (select = EID, 32 LUT inputs)
assign IWQ_2 = (EID ? IWQ_B_2 : IWQ_A_2);               // 2語目の2:1 MUX (選択=EID) / 2:1 mux for word 2 (select = EID)
assign IWQ_3 = (EID ? IWQ_B_3 : IWQ_A_3);               // 3語目の2:1 MUX (選択=EID) / 2:1 mux for word 3 (select = EID)
assign IWQ_4 = (EID ? IWQ_B_4 : IWQ_A_4);               // 4語目の2:1 MUX (新しく届いた8バイトの前半) / 2:1 mux for word 4 (first half of the newest 8 bytes)
assign IWQ_5 = (EID ? IWQ_B_5 : IWQ_A_5);               // 5語目の2:1 MUX (新しく届いた8バイトの後半) / 2:1 mux for word 5 (second half of the newest 8 bytes)

// 【解説】NIP_A は FF に「値 ^ 6」の形で格納している (NIP_A_REG)。
//         こうするとリセット (0) 直後の NIP_A が 6 = 「キューは空」になる。
// [Note] NIP_A is stored in the FF as "value ^ 6" (NIP_A_REG).
//        That way NIP_A is 6 = "queue empty" right after reset (0).
assign NIP_A = NIP_A_REG ^ 6;                           // FFの値^6で本当のNIP: 定数XORはビット1,2の反転(NOT)だけで、LUTに吸収される / real NIP = FF ^ 6: only bits 1,2 inverted, absorbed into LUTs
// 【解説】選択中のキューの NIP と、その値ごとのデコード信号。
// [Note] NIP of the selected queue, and a decode signal for each of its values.
assign NIP = (EID ? NIP_B     : NIP_A);                 // 使うキューの3bit NIP: 3bit 2:1 MUX (LUT3 x3) / 3-bit NIP of the used queue: 3-bit 2:1 mux (3 LUT3s)
assign NIP_0 = (NIP == 0);                              // NIP==0 のデコード: 3入力AND (後段MUXの選択線) / decode NIP==0: 3-input AND (mux select)
assign NIP_1 = (NIP == 1);                              // NIP==1 のデコード / decode NIP==1
assign NIP_2 = (NIP == 2);                              // NIP==2 のデコード / decode NIP==2
assign NIP_3 = (NIP == 3);                              // NIP==3 のデコード / decode NIP==3
assign NIP_4 = (NIP == 4);                              // NIP==4 のデコード / decode NIP==4
assign NIP_5 = (NIP == 5);                              // NIP==5 のデコード (6,7はどれも0=キュー空) / decode NIP==5 (6,7 give all 0 = queue empty)

// 【解説】選択中のキューの有効ビット (2 語ごと)。
// [Note] Valid bits of the selected queue (one per 2 words).
assign V01 = (EID ? IWQ_B_V01 : IWQ_A_V01);             // 0,1語目の有効ビット: 1bit 2:1 MUX / valid bit of words 0,1: 1-bit 2:1 mux
assign V23 = (EID ? IWQ_B_V23 : IWQ_A_V23);             // 2,3語目の有効ビット: 1bit 2:1 MUX / valid bit of words 2,3: 1-bit 2:1 mux
assign V45 = (EID ? IWQ_B_V45 : IWQ_A_V45);             // 4,5語目の有効ビット: 1bit 2:1 MUX / valid bit of words 4,5: 1-bit 2:1 mux

// 【解説】I0 / I1 が有効か: その命令が入っている 2 語ペアの有効ビットを見る。
//         I1 は NIP+1 の位置なので、NIP=5 (キューの最後) なら I1 は無い。
// [Note] Are I0 / I1 valid: look at the valid bit of the word pair holding the instruction.
//        I1 is at NIP+1, so with NIP=5 (the end of the queue) there is no I1.
assign I0_V = (NIP_0 | NIP_1) ? V01 : (NIP_2 | NIP_3) ? V23 : (NIP_4 | NIP_5) ? V45 : 0; // I0が入る語ペアの有効ビット: NIP(3bit)+V(3本)の6入力→LUT6 1個 / valid of I0's word pair: NIP(3)+V(3) = 6 inputs -> one LUT6
assign I1_V = (NIP_0        ) ? V01 : (NIP_1 | NIP_2) ? V23 : (NIP_3 | NIP_4) ? V45 : 0; // I1(=NIP+1)の語ペアの有効ビット, NIP>=5で0: LUT6 1個 / valid of I1 (=NIP+1), 0 for NIP>=5: one LUT6

// 【解説】NIP の位置の命令語 (無効なら 0)。
// [Note] The instruction word at NIP (0 if not valid).
assign I0_CANDID = NIP_0 ? IWQ_0 : NIP_1 ? IWQ_1 : NIP_2 ? IWQ_2 : // NIPの位置の語を選ぶ優先MUXの前半: one-hotなので実際は6:1 MUX / first half of the priority mux at NIP: one-hot, so really a 6:1 mux
            NIP_3 ? IWQ_3 : NIP_4 ? IWQ_4 : NIP_5 ? IWQ_5 : 0; // 後半: どれでもなければ0. IWQ_xの2:1と合わせ12:1 MUX(LUT6+MUXF7)x32bit / second half: else 0. With the IWQ 2:1 it is a 12:1 mux (LUT6+MUXF7) x 32 bits
assign I0 = I0_V ? I0_CANDID : 0;                       // 無効なら0にマスク: 32本のAND (MUXの最終段LUTに吸収) / mask to 0 when not valid: 32 ANDs (absorbed into the last mux LUT)

// 【解説】NIP+1 の位置の命令語 (無効なら 0)。
// [Note] The instruction word at NIP+1 (0 if not valid).
assign I1_CANDID = NIP_0 ? IWQ_1 : NIP_1 ? IWQ_2 : NIP_2 ? IWQ_3 : // NIP+1の位置の語を選ぶMUXの前半 (I0より1語ずれた配線) / first half of the mux at NIP+1 (wired one word later than I0)
            NIP_3 ? IWQ_4 : NIP_4 ? IWQ_5 : 0;          // 後半: NIP=5,6,7なら0. 10:1 MUX x32bit / second half: 0 for NIP=5,6,7. 10:1 mux x 32 bits
assign I1 = I1_V ? I1_CANDID : 0;                       // I1_Vで0にマスク→015/020のデコーダへ / mask with I1_V -> decoders in 015/020


//# These are solely for simulation convenience (serve as probe) ##

//IWQA-PROBE-H = ((IWQ-A[0] & 0xff000000)>>8)|((IWQ-A[1] & 0xff000000)>>16)
//                                           |((IWQ-A[2] & 0xff000000)>>24)
//IWQA-PROBE-L = ((IWQ-A[3] & 0xff000000)>>8)|((IWQ-A[4] & 0xff000000)>>16)
//                                           |((IWQ-A[5] & 0xff000000)>>24)
//IWQB-PROBE-H = ((IWQ-B[0] & 0xff000000)>>8)|((IWQ-B[1] & 0xff000000)>>16)
//                                           |((IWQ-B[2] & 0xff000000)>>24)
//IWQB-PROBE-L = ((IWQ-B[3] & 0xff000000)>>8)|((IWQ-B[4] & 0xff000000)>>16)
//                                           |((IWQ-B[5] & 0xff000000)>>24)

