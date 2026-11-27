// =====================================================================
//  015_d_i01.vh  <-  hard/015-d-i01.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D サイクル(2): I0, I1 のフィールド解読
//
// 命令形式が LS / EX / JB のどれかはまだ分からないので、同じ 32bit 語を
// すべての形式として解釈したフィールドを作っておき、形式の判定結果
// (020_d_iss.vh) に応じて必要なものを使う。
// フィールドの位置は stm_fmt_ls_ex.vh / stm_fmt_jb.vh を参照。
//
// [Note] D cycle (2): decode the fields of I0, I1
//
// It is not known yet whether the format is LS / EX / JB, so the same 32-bit word
// is cut into the fields of every format, and the ones needed are used according to
// the format decision (020_d_iss.vh).
// For the field positions see stm_fmt_ls_ex.vh / stm_fmt_jb.vh.
//
// 【ネットリスト解説】
//   入力 : I0, I1 (010), PSW_USER (080 の FF)
//   出力 : 形式判定用の上位ビット (I0_LS_OPC_H など) -> 020
//          レジスタ番号 (I0_EX_RB1 / I0_EX_RS2 / I0_LS_RB) -> 020, 030
//          I0_IS_LEGAL / I1_IS_LEGAL -> 030
//   回路の形: is_legal_opc の 2 組 (LUT 数個) 以外は、I0 / I1 のネットに別名を
//   付けているだけで、ゲートは 1 つも無い。I0_JB_IMM12, I0_LS_DISP16 などどこからも
//   使われないフィールドは、合成で何も残らない (D サイクルの変位は 035 で
//   振り分け後の ILS / IJB から取り直している)。
//
// [Netlist notes]
//   Inputs : I0, I1 (010), PSW_USER (FF in 080)
//   Outputs: upper bits for format decode (I0_LS_OPC_H etc.) -> 020
//            register numbers (I0_EX_RB1 / I0_EX_RS2 / I0_LS_RB) -> 020, 030
//            I0_IS_LEGAL / I1_IS_LEGAL -> 030
//   Circuit: apart from the two copies of is_legal_opc (a few LUTs), these only give
//   new names to the nets of I0 / I1; there is not a single gate. Fields nothing uses,
//   such as I0_JB_IMM12 and I0_LS_DISP16, leave nothing after synthesis (the displacements
//   of the D cycle are taken again from ILS / IJB in 035, after the instructions are sorted).
// ---------------------------------------------------------------------

// d-i01 : decoding I0 and I1

// 【解説】I0 を LS 形式 (ロード/ストア) として見たフィールド。
// [Note] Fields of I0 seen as LS format (load/store).
assign I0_LS_STORE = ls_store(I0);                      // I0[28]=ストアか: 1本の配線に名前を付けるだけ(ゲート0) / I0[28] = store?: just a name for one wire (no gate)
assign I0_LS_LENG = ls_leng(I0);                        // I0[27:24]=アクセス長(0=語,他=サブワード): 4本の配線 / I0[27:24] = access length (0 = word): 4 wires
assign I0_LS_RD_RS = ls_rd_rs(I0);                      // I0[23:20]=ロード先/ストア元のGR番号: 配線 / I0[23:20] = load dest / store source GR: wires
assign I0_LS_RB = ls_rb(I0);                            // I0[19:16]=ベースレジスタ番号: 配線 (EXのRB1と同じビット) / I0[19:16] = base register: wires (same bits as EX RB1)
assign I0_LS_DISP16 = ls_disp16(I0);                    // I0[15:0]=変位: どこからも使われず合成で消える (035でILSから取り直す) / I0[15:0] = displacement: unused, removed by synthesis (035 takes it from ILS)

// 【解説】I0 を EX 形式 (演算) として見たフィールド。
// [Note] Fields of I0 seen as EX format (arithmetic).
assign I0_EX_OP2MODE = ex_op2mode(I0);                  // I0[30:29]=第2オペランド(3=即値,1=レジスタ,2=メモリ): 配線 / I0[30:29] = operand-2 mode (3 imm, 1 reg, 2 mem): wires
assign I0_EX_SETCC = ex_setcc(I0);                      // I0[28]=CCを更新するか (LSのSTOREと同じビット): 配線 / I0[28] = set CC? (same bit as LS STORE): wire
assign I0_EX_EXU_OPC = ex_exu_opc(I0);                  // I0[27:24]=演算の種類 (OPC_A..SETHI): 配線 / I0[27:24] = operation (OPC_A..SETHI): wires
assign I0_EX_RB1 = ex_rb1(I0);                          // I0[19:16]=第1オペランド/ベースのGR番号: 配線→020,030 / I0[19:16] = operand 1 / base GR: wires -> 020, 030
assign I0_EX_RS2 = ex_rs2(I0);                          // I0[15:12]=第2オペランドのGR番号: 配線→020,030 / I0[15:12] = operand-2 GR: wires -> 020, 030
assign I0_EX_RD = ex_rd(I0);                            // I0[23:20]=書き込み先GR番号: 配線 / I0[23:20] = destination GR: wires
assign I0_EX_DISP12 = ex_disp12(I0);                    // I0[11:0]=メモリオペランドの変位: 未使用で消える / I0[11:0] = memory-operand displacement: unused, removed

// 【解説】I0 を JB 形式 (分岐) として見たフィールド。
// [Note] Fields of I0 seen as JB format (branch).
assign I0_JB_COND = jb_cond(I0);                        // I0[27]=条件分岐か: 配線 / I0[27] = conditional?: wire
assign I0_JB_REG = jb_reg(I0);                          // I0[26]=レジスタ+変位の分岐か (0=PC相対): 配線 / I0[26] = register+disp branch? (0 = PC-relative): wire
assign I0_JB_LINK = jb_link(I0);                        // I0[25]=戻り番地をGRへ保存するか: 配線 / I0[25] = save return address to GR?: wire
assign I0_JB_CMP = jb_cmp(I0);                          // I0[24]=2つのGRを比較して分岐するか: 配線 / I0[24] = compare two GRs and branch?: wire
assign I0_JB_RD_MASK = jb_rd_mask(I0);                  // I0[23:20]=リンク先GRまたはCCマスク: 配線 / I0[23:20] = link GR or CC mask: wires
assign I0_JB_RB1 = jb_rb1(I0);                          // I0[19:16]=ベース/比較の第1GR: 配線 / I0[19:16] = base / first compare GR: wires
assign I0_JB_R2_IMM4 = jb_r2_imm4(I0);                  // I0[15:12]=比較の第2GR: 配線 / I0[15:12] = second compare GR: wires
assign I0_JB_IMM12 = jb_imm12(I0);                      // I0[11:0]=比較分岐の変位: 未使用で消える / I0[11:0] = compare-branch displacement: unused, removed

// 【解説】以下 I1 について同じ。
// [Note] The same for I1 below.
assign I1_LS_STORE = ls_store(I1);                      // I1[28]=ストアか: 配線 / I1[28] = store?: wire
assign I1_LS_LENG = ls_leng(I1);                        // I1[27:24]=アクセス長: 配線 / I1[27:24] = access length: wires
assign I1_LS_RD_RS = ls_rd_rs(I1);                      // I1[23:20]=ロード先/ストア元: 配線 / I1[23:20] = load dest / store source: wires
assign I1_LS_RB = ls_rb(I1);                            // I1[19:16]=ベースレジスタ: 配線 / I1[19:16] = base register: wires
assign I1_LS_DISP16 = ls_disp16(I1);                    // I1[15:0]=変位: 未使用で消える / I1[15:0] = displacement: unused, removed

assign I1_EX_OP2MODE = ex_op2mode(I1);                  // I1[30:29]=第2オペランドの種類: 配線 / I1[30:29] = operand-2 mode: wires
assign I1_EX_SETCC = ex_setcc(I1);                      // I1[28]=CC更新: 配線 / I1[28] = set CC: wire
assign I1_EX_EXU_OPC = ex_exu_opc(I1);                  // I1[27:24]=演算の種類: 配線 / I1[27:24] = operation: wires
assign I1_EX_RB1 = ex_rb1(I1);                          // I1[19:16]=第1オペランドGR: 配線 / I1[19:16] = operand-1 GR: wires
assign I1_EX_RS2 = ex_rs2(I1);                          // I1[15:12]=第2オペランドGR: 配線 / I1[15:12] = operand-2 GR: wires
assign I1_EX_RD = ex_rd(I1);                            // I1[23:20]=書き込み先GR: 配線 / I1[23:20] = destination GR: wires
assign I1_EX_DISP12 = ex_disp12(I1);                    // I1[11:0]=変位: 未使用で消える / I1[11:0] = displacement: unused, removed

assign I1_JB_COND = jb_cond(I1);                        // I1[27]=条件分岐: 配線 / I1[27] = conditional: wire
assign I1_JB_REG = jb_reg(I1);                          // I1[26]=レジスタ相対: 配線 / I1[26] = register-relative: wire
assign I1_JB_LINK = jb_link(I1);                        // I1[25]=リンク: 配線 / I1[25] = link: wire
assign I1_JB_CMP = jb_cmp(I1);                          // I1[24]=比較分岐: 配線 / I1[24] = compare branch: wire
assign I1_JB_RD_MASK = jb_rd_mask(I1);                  // I1[23:20]=リンク先/CCマスク: 配線 / I1[23:20] = link GR / CC mask: wires
assign I1_JB_RB1 = jb_rb1(I1);                          // I1[19:16]=ベース/比較の第1GR: 配線 / I1[19:16] = base / first compare GR: wires
assign I1_JB_R2_IMM4 = jb_r2_imm4(I1);                  // I1[15:12]=比較の第2GR: 配線 / I1[15:12] = second compare GR: wires
assign I1_JB_IMM12 = jb_imm12(I1);                      // I1[11:0]=変位: 未使用で消える / I1[11:0] = displacement: unused, removed

// 【解説】不正命令の検出。特権命令 (RFE/RSR/WSR) はユーザーモード
//         (PSW_USER=1) では不正命令になる。
// [Note] Illegal instruction detection. Privileged instructions (RFE/RSR/WSR) are illegal
//        in user mode (PSW_USER=1).
assign I0_IS_LEGAL = is_legal_opc(I0,PSW_USER);         // I0の上位8bit+PSW_USERの9入力→LUT2~3個の正当性判定 / legality of I0 from top 8 bits + PSW_USER (9 inputs -> 2-3 LUTs)
assign I1_IS_LEGAL = is_legal_opc(I1,PSW_USER);         // I1の正当性判定 (I0と同じ回路をもう1組) / legality of I1 (a second copy of the same logic)

// 【解説】形式判定 (020_d_iss.vh) に使う上位ビット。
// [Note] Upper bits used for the format decision (020_d_iss.vh).
assign I0_LS_OPC_H = ls_opc_h(I0);                      // I0[31:29]: 100ならLS形式 (020で比較) / I0[31:29]: 100 means LS format (compared in 020)
assign I0_EX_OPC_H = ex_opc_h(I0);                      // I0[31]: 0ならEX形式の候補 / I0[31]: 0 means EX-format candidate
assign I0_INSN_OPC = insn_opc(I0);                      // I0[31:28]: 1011=JB, 1100=特権命令 / I0[31:28]: 1011 = JB, 1100 = privileged
assign I0_PRIV_OPC = priv_opc(I0);                      // I0[25:24]: 特権命令の種類 1=RFE 2=RSR 3=WSR / I0[25:24]: privileged kind 1 RFE, 2 RSR, 3 WSR

assign I1_LS_OPC_H = ls_opc_h(I1);                      // I1[31:29]: LS形式判定用 / I1[31:29]: for LS-format decode
assign I1_EX_OPC_H = ex_opc_h(I1);                      // I1[31]: EX形式判定用 / I1[31]: for EX-format decode
assign I1_INSN_OPC = insn_opc(I1);                      // I1[31:28]: JB/特権の判定用 (I1のPRIV_OPCは不要なので無い) / I1[31:28]: JB / priv decode (I1 needs no PRIV_OPC)
