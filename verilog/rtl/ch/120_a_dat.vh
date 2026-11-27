// =====================================================================
//  120_a_dat.vh  <-  hard/120-a-dat.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】A サイクル: EX パイプの演算と、LS パイプのアドレス計算
//
// ・EX パイプの EXU (stm_exu) で演算する。オペランドは D → A のときに
//   バイパス済み (140_d_dat.vh) なので、ここではそのまま使う
// ・LS パイプのアドレス (ベース + 変位) を EAG で計算する
// ・RSR (システムレジスタ読み出し) の値を選ぶ
//
// [Note] A cycle: EX-pipe operation and LS-pipe address computation
//
// - the EXU (stm_exu) of the EX pipe computes. The operands were already bypassed on the
//   way from D to A (140_d_dat.vh), so they are used as they are here
// - the EAG computes the LS-pipe address (base + displacement)
// - selects the value for RSR (system register read)
//
// 【ネットリスト解説】
//   入力 : A_LS_OPB_DT / A_EX_OP1_DT / A_EX_OP2_DT / A_DISP / A_EX_RAD2 (140 の FF),
//          A_EX_OPCODE / A_PRIVCODE (150 の FF), システムレジスタと PSW (080 の FF)
//   出力 : AA_EAG_OUTPUT -> 060 (I/O 判定), 130 (B_LS_LOG_AD, B_TGT),
//                          160 (S ユニットへの番地), 170 (レジスタ間接分岐のフェッチ番地)
//          AA_EX_RES     -> 130 (B_EX_RES), 140 (A → D のバイパス)
//          AA_EXU_CC     -> 130 (B_EX_CC), 210 (EX パイプで BC を解決する)
//          AA_EXU_INT    -> 130 (オーバーフロー割り込み)
//   回路の形:
//     ・u_a_exu (stm_exu) 1 個と、EAG の 32bit 加算器 (add_32_16) 1 個。
//       どちらも入力が A の FF だけなので、A サイクルはこの 2 つの演算器から始まる。
//     ・AA_EAG_OUTPUT のファンアウトが特に大きい。B_LS_LOG_AD の FF だけでなく、
//       S ユニットの LBS_AD / OP_WAIT_AD (160) と命令フェッチの IB_AD (170 → 190) の
//       MUX にも入るので、「加算 → 別の機能ブロックの MUX → FF」が A サイクルの長い経路。
//     ・A_SR_READ_DATA は 32bit の 9:1 MUX (選択 = A_EX_RAD2 の 4bit)。
//       AA_EX_RES はその出力と EXU の出力の 2:1 MUX。
//
// [Netlist notes]
//   Inputs : A_LS_OPB_DT / A_EX_OP1_DT / A_EX_OP2_DT / A_DISP / A_EX_RAD2 (FFs in 140),
//            A_EX_OPCODE / A_PRIVCODE (FFs in 150), system registers and PSW (FFs in 080)
//   Outputs: AA_EAG_OUTPUT -> 060 (I/O check), 130 (B_LS_LOG_AD, B_TGT),
//                            160 (address to the S unit), 170 (fetch address of a register-indirect branch)
//            AA_EX_RES     -> 130 (B_EX_RES), 140 (bypass from A to D)
//            AA_EXU_CC     -> 130 (B_EX_CC), 210 (BC resolved in the EX pipe)
//            AA_EXU_INT    -> 130 (overflow interrupt)
//   Circuit:
//     - One u_a_exu (stm_exu) and one 32-bit EAG adder (add_32_16).
//       Both take only A FFs as inputs, so the A cycle starts at these two units.
//     - AA_EAG_OUTPUT has a particularly large fan-out. Besides the B_LS_LOG_AD FFs it goes into
//       the muxes of the S unit's LBS_AD / OP_WAIT_AD (160) and of the fetch address IB_AD
//       (170 -> 190), so "add -> a mux in another functional block -> FF" is the long A-cycle path.
//     - A_SR_READ_DATA is a 32-bit 9:1 mux (select = the 4 bits of A_EX_RAD2).
//       AA_EX_RES is a 2:1 mux of its output and the EXU output.
// ---------------------------------------------------------------------

// a-dat
// Bypass register if A-reg-num matches X-reg-num. (Execute-Execute Bypass)

// Note :
// o The order of 'else-if' is important here because LATEST one should be used.
//   For example, if B- and E-cycs write same GR, B-cyc data should be used.

// o Two insns which write same GR are never issued concurrently.  Therefore
//   we don't have to worry about that possibility here. (ex. W-WAD1 != W-WAD2)


//   MEMOP is itself a bypassed data.  May be critical path!

// ---- #if 0 (元ソースで無効化) ----
//      (#if 0: disabled in the original source)
// AA-OPB = 
//  (A-LS-OPB-IS-GR & B-WE2 & (A-LS-RADB == B-WAD2)) ? B-EX-RES  :
//  (A-LS-OPB-IS-GR & E-WE1 & (A-LS-RADB == E-WAD1) & (E-LS-OPCODE==0))? EE-MEMOP :
//  (A-LS-OPB-IS-GR & E-WE2 & (A-LS-RADB == E-WAD2)) ? E-EX-RES  :
//  (A-LS-OPB-IS-GR & W-WE1 & (A-LS-RADB == W-WAD1)) ? W-WDT1 :
//  (A-LS-OPB-IS-GR & W-WE2 & (A-LS-RADB == W-WAD2)) ? W-WDT2 :  A-LS-OPB-DT 
//
// AA-OP1 = 
//  (A-EX-OP1-IS-GR & B-WE2 & (A-EX-RAD1 == B-WAD2)) ? B-EX-RES  :
//  (A-EX-OP1-IS-GR & E-WE1 & (A-EX-RAD1 == E-WAD1) & (E-LS-OPCODE==0))? EE-MEMOP :
//  (A-EX-OP1-IS-GR & E-WE2 & (A-EX-RAD1 == E-WAD2)) ? E-EX-RES  :
//  (A-EX-OP1-IS-GR & W-WE1 & (A-EX-RAD1 == W-WAD1)) ? W-WDT1 :
//  (A-EX-OP1-IS-GR & W-WE2 & (A-EX-RAD1 == W-WAD2)) ? W-WDT2 : A-EX-OP1-DT
//
// AA-OP2 = 
//  (A-EX-OP2-IS-GR & B-WE2 & (A-EX-RAD2 == B-WAD2)) ? B-EX-RES  :
//  (A-EX-OP2-IS-GR & E-WE1 & (A-EX-RAD2 == E-WAD1) & (E-LS-OPCODE==0))? EE-MEMOP :
//  (A-EX-OP2-IS-GR & E-WE2 & (A-EX-RAD2 == E-WAD2)) ? E-EX-RES  :
//  (A-EX-OP2-IS-GR & W-WE1 & (A-EX-RAD2 == W-WAD1)) ? W-WDT1 :
//  (A-EX-OP2-IS-GR & W-WE2 & (A-EX-RAD2 == W-WAD2)) ? W-WDT2 : A-EX-OP2-DT
// ---- #else (有効) ----
//      (#else: this is the version in effect)
// 【解説】A で使うオペランド。旧版 (#if 0) はここでバイパスしていたが、
//         現行版は 1 サイクル前の D → A の時点でバイパス済み。
// [Note] Operands used in A. The old version (#if 0) bypassed here; the current version
//        has already bypassed them one cycle earlier, on the way from D to A.
assign AA_OPB = A_LS_OPB_DT;                            // EAGのベース値: A_LS_OPB_DTのFFそのもの (Dの時点でバイパス済み) / EAG base: the A_LS_OPB_DT FFs (bypassed already in D)
assign AA_OP1 = A_EX_OP1_DT;                            // EXUの第1オペランド: FFの別名 / EXU operand 1: alias of FFs
assign AA_OP2 = A_EX_OP2_DT;                            // EXUの第2オペランド: FFの別名 / EXU operand 2: alias of FFs
// ---- #endif ----


// ---- #ifndef VHDL (C シミュレータ版を採用) ----
//      (#ifndef VHDL: the C-simulator version is used)
// exu(A-EX-OPCODE,AA-OP1,AA-OP2,&AA-EXU-CC,&AA-EXU-OUTPUT,&AA-EXU-INT)
//   -> EX パイプの EXU インスタンス。A-EX-OPCODE は 4bit なので
//      VHDL 版の FOUR2FIVE と同様に先頭に 0 を付けて 5bit にする。
//   -> the EXU instance of the EX pipe. A-EX-OPCODE is 4 bits, so, like FOUR2FIVE of the
//      VHDL version, a 0 is added in front to make it 5 bits.
// 【解説】EX パイプの EXU。分岐の比較 (C)、リンクアドレスの計算 (AU)、
//         WSR の値の素通し (LDW) にも使う (150_d_act.vh の A_EX_OPCODE)。
// [Note] The EXU of the EX pipe. Also used for branch compares (C), the link address (AU)
//        and passing the WSR value through (LDW) (A_EX_OPCODE in 150_d_act.vh).
stm_exu u_a_exu (                                       // EXパイプのEXUのインスタンス: 合成ではstm_cntlの中に展開される / EX-pipe EXU instance: flattened into stm_cntl by synthesis
  .opc  ({1'b0, A_EX_OPCODE}),                          // 4bitのopcodeに0を付けて5bit (bit4=0なのでサブワード回路は定数で消える) / 4-bit opcode padded to 5 (bit4=0, so the sub-word logic is removed)
  .x    (AA_OP1),                                       // 第1オペランド ← FF / operand x <- FFs
  .y    (AA_OP2),                                       // 第2オペランド ← FF / operand y <- FFs
  .cc   (AA_EXU_CC),                                    // CC → 130のB_EX_CC, 210 (EXでBC解決) / CC -> B_EX_CC in 130, 210 (BC solved by EX)
  .z    (AA_EXU_OUTPUT),                                // 演算結果 → AA_EX_RES / result -> AA_EX_RES
  .intr (AA_EXU_INT)                                    // オーバーフロー → 130のB_INTCODE / overflow -> B_INTCODE in 130
);                                                      // インスタンスの終わり / end of instance

// 【解説】EAG (実効アドレス生成): ベースレジスタ + 符号拡張した 16bit 変位。
//         レジスタ間接分岐の分岐先もここで計算する。
// [Note] EAG (effective address generation): base register + sign-extended 16-bit displacement.
//        The target of a register-indirect branch is computed here too.
assign AA_EAG_OUTPUT = add_32_16(AA_OPB,A_DISP);        // 実効アドレス = ベース + 符号拡張16bit変位: 32bit加算器 (CARRY4 x8). ファンアウト大 / effective address = base + sign-extended disp16: 32-bit adder (8 CARRY4s), large fan-out
// ---- #endif ----

// Read SR data

// 【解説】RSR で読むシステムレジスタの値 (番号は R2 フィールド)。
// [Note] Value of the system register read by RSR (the number is in the R2 field).
assign A_SR_READ_DATA =                                 // RSRで読むシステムレジスタ: A_EX_RAD2(4bit)で選ぶ32bit 9:1 MUX ... / system register read by RSR: 32-bit 9:1 mux on A_EX_RAD2 (4 bits) ...
        (A_EX_RAD2 == SYSREG_PSW)   ? build_psw(PSW_CC,PSW_USER,PSW_TYPE) : // ...0: PSW (CC/USER/TYPEのFFを配線で組み立て, 他bitは0) / ... 0: PSW (CC/USER/TYPE FFs wired together, other bits 0)
        (A_EX_RAD2 == SYSREG_TBR)   ? TBR :             // ...2: TBR / ... 2: TBR  -- A_EX_RAD2==2のとき (4bit一致) / when A_EX_RAD2 == 2 (4-bit match)
        (A_EX_RAD2 == SYSREG_CMPR)  ? CMPR :            // ...3: CMPR / ... 3: CMPR  -- A_EX_RAD2==3のとき / when A_EX_RAD2 == 3
        (A_EX_RAD2 == SYSREG_XPSW)  ? XPSW :            // ...4: XPSW / ... 4: XPSW  -- A_EX_RAD2==4のとき / when A_EX_RAD2 == 4
        (A_EX_RAD2 == SYSREG_XPC)   ? XPC :             // ...5: XPC / ... 5: XPC  -- A_EX_RAD2==5のとき / when A_EX_RAD2 == 5
        (A_EX_RAD2 == SYSREG_XLA)   ? XLA :             // ...6: XLA / ... 6: XLA  -- A_EX_RAD2==6のとき / when A_EX_RAD2 == 6
        (A_EX_RAD2 == SYSREG_SVR0)  ? SVR0 :            // ...8: SVR0 / ... 8: SVR0  -- A_EX_RAD2==8のとき (7番は欠番) / when A_EX_RAD2 == 8 (7 is unused)
        (A_EX_RAD2 == SYSREG_SVR1)  ? SVR1 : 0;         // ...9: SVR1, 欠番は0 (LUT6+MUXF7の木 x32bit) / ... 9: SVR1, gaps give 0 (LUT6+MUXF7 tree x 32 bits)

// 【解説】EX パイプの結果: RSR ならシステムレジスタの値, それ以外は EXU の出力。
// [Note] Result of the EX pipe: the system register value for RSR, otherwise the EXU output.
assign AA_EX_RES = (A_PRIVCODE==PRIVCODE_RSR) ? A_SR_READ_DATA : AA_EXU_OUTPUT; // EXの結果: RSRならSRの値, そうでなければEXU出力 (32bit 2:1 MUX) → 130, 140 / EX result: SR value for RSR, else EXU output (32-bit 2:1 mux) -> 130, 140
