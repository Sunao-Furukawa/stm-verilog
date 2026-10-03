// =====================================================================
//  120_a_dat.vh  <-  hard/120-a-dat.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】A サイクル: EX パイプの演算と、LS パイプのアドレス計算
//
// ・EX パイプの EXU (stm_exu) で演算する。オペランドは D → A のときに
//   バイパス済み (140_d_dat.vh) なので、ここではそのまま使う
// ・LS パイプのアドレス (ベース + 変位) を EAG で計算する
// ・RSR (システムレジスタ読み出し) の値を選ぶ
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
// 【解説】A で使うオペランド。旧版 (#if 0) はここでバイパスしていたが、
//         現行版は 1 サイクル前の D → A の時点でバイパス済み。
assign AA_OPB = A_LS_OPB_DT;
assign AA_OP1 = A_EX_OP1_DT;
assign AA_OP2 = A_EX_OP2_DT;
// ---- #endif ----


// ---- #ifndef VHDL (C シミュレータ版を採用) ----
// exu(A-EX-OPCODE,AA-OP1,AA-OP2,&AA-EXU-CC,&AA-EXU-OUTPUT,&AA-EXU-INT)
//   -> EX パイプの EXU インスタンス。A-EX-OPCODE は 4bit なので
//      VHDL 版の FOUR2FIVE と同様に先頭に 0 を付けて 5bit にする。
// 【解説】EX パイプの EXU。分岐の比較 (C)、リンクアドレスの計算 (AU)、
//         WSR の値の素通し (LDW) にも使う (150_d_act.vh の A_EX_OPCODE)。
stm_exu u_a_exu (
  .opc  ({1'b0, A_EX_OPCODE}),
  .x    (AA_OP1),
  .y    (AA_OP2),
  .cc   (AA_EXU_CC),
  .z    (AA_EXU_OUTPUT),
  .intr (AA_EXU_INT)
);

// 【解説】EAG (実効アドレス生成): ベースレジスタ + 符号拡張した 16bit 変位。
//         レジスタ間接分岐の分岐先もここで計算する。
assign AA_EAG_OUTPUT = add_32_16(AA_OPB,A_DISP);
// ---- #endif ----

// Read SR data

// 【解説】RSR で読むシステムレジスタの値 (番号は R2 フィールド)。
assign A_SR_READ_DATA = 
        (A_EX_RAD2 == SYSREG_PSW)   ? build_psw(PSW_CC,PSW_USER,PSW_TYPE) :
        (A_EX_RAD2 == SYSREG_TBR)   ? TBR :
        (A_EX_RAD2 == SYSREG_CMPR)  ? CMPR :
        (A_EX_RAD2 == SYSREG_XPSW)  ? XPSW :
        (A_EX_RAD2 == SYSREG_XPC)   ? XPC :
        (A_EX_RAD2 == SYSREG_XLA)   ? XLA :
        (A_EX_RAD2 == SYSREG_SVR0)  ? SVR0 :
        (A_EX_RAD2 == SYSREG_SVR1)  ? SVR1 : 0;

// 【解説】EX パイプの結果: RSR ならシステムレジスタの値, それ以外は EXU の出力。
assign AA_EX_RES = (A_PRIVCODE==PRIVCODE_RSR) ? A_SR_READ_DATA : AA_EXU_OUTPUT;
