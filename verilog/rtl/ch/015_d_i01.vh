// =====================================================================
//  015_d_i01.vh  <-  hard/015-d-i01.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D サイクル(2): I0, I1 のフィールド解読
//
// 命令形式が LS / EX / JB のどれかはまだ分からないので、同じ 32bit 語を
// すべての形式として解釈したフィールドを作っておき、形式の判定結果
// (020_d_iss.vh) に応じて必要なものを使う。
// フィールドの位置は stm_fmt_ls_ex.vh / stm_fmt_jb.vh を参照。
// ---------------------------------------------------------------------

// d-i01 : decoding I0 and I1

// 【解説】I0 を LS 形式 (ロード/ストア) として見たフィールド。
assign I0_LS_STORE = ls_store(I0);
assign I0_LS_LENG = ls_leng(I0);
assign I0_LS_RD_RS = ls_rd_rs(I0);
assign I0_LS_RB = ls_rb(I0);
assign I0_LS_DISP16 = ls_disp16(I0);

// 【解説】I0 を EX 形式 (演算) として見たフィールド。
assign I0_EX_OP2MODE = ex_op2mode(I0);
assign I0_EX_SETCC = ex_setcc(I0);
assign I0_EX_EXU_OPC = ex_exu_opc(I0);
assign I0_EX_RB1 = ex_rb1(I0);
assign I0_EX_RS2 = ex_rs2(I0);
assign I0_EX_RD = ex_rd(I0);
assign I0_EX_DISP12 = ex_disp12(I0);

// 【解説】I0 を JB 形式 (分岐) として見たフィールド。
assign I0_JB_COND = jb_cond(I0);
assign I0_JB_REG = jb_reg(I0);
assign I0_JB_LINK = jb_link(I0);
assign I0_JB_CMP = jb_cmp(I0);
assign I0_JB_RD_MASK = jb_rd_mask(I0);
assign I0_JB_RB1 = jb_rb1(I0);
assign I0_JB_R2_IMM4 = jb_r2_imm4(I0);
assign I0_JB_IMM12 = jb_imm12(I0);

// 【解説】以下 I1 について同じ。
assign I1_LS_STORE = ls_store(I1);
assign I1_LS_LENG = ls_leng(I1);
assign I1_LS_RD_RS = ls_rd_rs(I1);
assign I1_LS_RB = ls_rb(I1);
assign I1_LS_DISP16 = ls_disp16(I1);

assign I1_EX_OP2MODE = ex_op2mode(I1);
assign I1_EX_SETCC = ex_setcc(I1);
assign I1_EX_EXU_OPC = ex_exu_opc(I1);
assign I1_EX_RB1 = ex_rb1(I1);
assign I1_EX_RS2 = ex_rs2(I1);
assign I1_EX_RD = ex_rd(I1);
assign I1_EX_DISP12 = ex_disp12(I1);

assign I1_JB_COND = jb_cond(I1);
assign I1_JB_REG = jb_reg(I1);
assign I1_JB_LINK = jb_link(I1);
assign I1_JB_CMP = jb_cmp(I1);
assign I1_JB_RD_MASK = jb_rd_mask(I1);
assign I1_JB_RB1 = jb_rb1(I1);
assign I1_JB_R2_IMM4 = jb_r2_imm4(I1);
assign I1_JB_IMM12 = jb_imm12(I1);

// 【解説】不正命令の検出。特権命令 (RFE/RSR/WSR) はユーザーモード
//         (PSW_USER=1) では不正命令になる。
assign I0_IS_LEGAL = is_legal_opc(I0,PSW_USER);
assign I1_IS_LEGAL = is_legal_opc(I1,PSW_USER);

// 【解説】形式判定 (020_d_iss.vh) に使う上位ビット。
assign I0_LS_OPC_H = ls_opc_h(I0);
assign I0_EX_OPC_H = ex_opc_h(I0);
assign I0_INSN_OPC = insn_opc(I0);
assign I0_PRIV_OPC = priv_opc(I0);

assign I1_LS_OPC_H = ls_opc_h(I1);
assign I1_EX_OPC_H = ex_opc_h(I1);
assign I1_INSN_OPC = insn_opc(I1);
