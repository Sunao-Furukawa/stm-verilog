// =====================================================================
//  035_d_ixx.vh  <-  hard/035-d-ixx.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D サイクル(5): パイプごとにまとめ直した命令 ILS / IEX / IJB のフィールド解読
//
// 015_d_i01.vh と同じことを、振り分け後の命令について行う。
//
// 【ネットリスト解説】
//   入力 : ILS / IEX / IJB / ILS_V (030)
//   出力 : ILS_* -> 040 (変位), 150 (A の LS パイプのタグ)
//          IEX_* -> 140 (即値オペランド), 150 (opcode, RD, SETCC)
//          IJB_* -> 040 (分岐の種類, 変位, マスク), 140 / 150 (リンク), 210 (マスク)
//   回路の形: ILS_LS_FMT / ILS_EXRM_FMT の 2 つ (上位ビットの比較と ILS_V の AND)
//   以外は配線だけ。ILS_RB, ILS_RD, IEX_RB1, IEX_RS2, IJB_IMM12 などは
//   どこからも使われないので消える (レジスタの値は 030 の DD_RAD* で I0/I1 から
//   直接読んでいるため、振り分け後の番号は要らない)。
// ---------------------------------------------------------------------

// d-ixx : decoding ILS, IEX and IJB


// 【解説】LS パイプの命令 (LS 形式としてのフィールド)。
assign ILS_STORE = ls_store(ILS);
assign ILS_LENG = ls_leng(ILS);
assign ILS_RD_RS = ls_rd_rs(ILS);
assign ILS_RB = ls_rb(ILS);
assign ILS_DISP16 = ls_disp16(ILS);

// 【解説】LS パイプの命令を EX-RM 形式 (メモリオペランド演算) として見たフィールド。
assign ILS_OP2MODE = ex_op2mode(ILS);
assign ILS_SETCC = ex_setcc(ILS);
assign ILS_EXU_OPC = ex_exu_opc(ILS);
//ILS-RB1 	= ex_rb1(ILS)
assign ILS_RS2 = ex_rs2(ILS);
assign ILS_RD = ex_rd(ILS);
assign ILS_DISP12 = ex_disp12(ILS);

// 【解説】EX パイプの命令のフィールド。
assign IEX_OP2MODE = ex_op2mode(IEX);
assign IEX_SETCC = ex_setcc(IEX);
assign IEX_EXU_OPC = ex_exu_opc(IEX);
assign IEX_RB1 = ex_rb1(IEX);
assign IEX_RS2 = ex_rs2(IEX);
assign IEX_RD = ex_rd(IEX);
assign IEX_DISP12 = ex_disp12(IEX);

// 【解説】分岐命令のフィールド。
assign IJB_COND = jb_cond(IJB);
assign IJB_REG = jb_reg(IJB);
assign IJB_LINK = jb_link(IJB);
assign IJB_CMP = jb_cmp(IJB);
assign IJB_RD_MASK = jb_rd_mask(IJB);
assign IJB_RB1 = jb_rb1(IJB);
assign IJB_R2_IMM4 = jb_r2_imm4(IJB);
assign IJB_IMM12 = jb_imm12(IJB);


assign IEX_IMM16 = ex_imm16(IEX);

assign IJB_IMM16 = jb_imm16(IJB);
assign IJB_IMM20 = jb_imm20(IJB);
assign IJB_BACKWARD = jb_backward(IJB);


assign ILS_LS_OPC_H = ls_opc_h(ILS);
assign ILS_EX_OPC_H = ex_opc_h(ILS);

// 【解説】LS パイプの命令が本物のロード/ストアか、メモリオペランド演算 (EX-RM) か。
assign ILS_LS_FMT = (ILS_LS_OPC_H == 4) & ILS_V;
assign ILS_EXRM_FMT = (ILS_EX_OPC_H == 0) & (ILS_OP2MODE != 0) & ILS_V;
