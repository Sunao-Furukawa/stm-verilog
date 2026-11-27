// =====================================================================
//  035_d_ixx.vh  <-  hard/035-d-ixx.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D サイクル(5): パイプごとにまとめ直した命令 ILS / IEX / IJB のフィールド解読
//
// 015_d_i01.vh と同じことを、振り分け後の命令について行う。
// [Note] D cycle (5): decode the fields of ILS / IEX / IJB, the instructions regrouped per pipe
//
// The same as 015_d_i01.vh, done for the instructions after sorting.
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
//
// [Netlist notes]
//   Inputs : ILS / IEX / IJB / ILS_V (030)
//   Outputs: ILS_* -> 040 (displacement), 150 (LS-pipe tags of A)
//            IEX_* -> 140 (immediate operand), 150 (opcode, RD, SETCC)
//            IJB_* -> 040 (branch kind, displacement, mask), 140 / 150 (link), 210 (mask)
//   Circuit: only wires, except ILS_LS_FMT / ILS_EXRM_FMT (a compare of the upper bits
//   ANDed with ILS_V). ILS_RB, ILS_RD, IEX_RB1, IEX_RS2, IJB_IMM12 etc. are unused and
//   disappear (register values are read with DD_RAD* in 030 directly from I0/I1, so the
//   register numbers after sorting are not needed).
// ---------------------------------------------------------------------

// d-ixx : decoding ILS, IEX and IJB


// 【解説】LS パイプの命令 (LS 形式としてのフィールド)。
// [Note] The LS-pipe instruction (fields as LS format).
assign ILS_STORE = ls_store(ILS);                       // ILS[28]=ストアか: 配線 → 150のA_LS_STORE / ILS[28] = store?: wire -> A_LS_STORE in 150
assign ILS_LENG = ls_leng(ILS);                         // ILS[27:24]=アクセス長: 配線 / ILS[27:24] = access length: wires
assign ILS_RD_RS = ls_rd_rs(ILS);                       // ILS[23:20]=ロード先/ストア元: 配線 / ILS[23:20] = load dest / store source: wires
assign ILS_RB = ls_rb(ILS);                             // ILS[19:16]=ベース: 未使用で消える (番号はDD_RADBで読み済み) / ILS[19:16] = base: unused, removed (already read via DD_RADB)
assign ILS_DISP16 = ls_disp16(ILS);                     // ILS[15:0]=変位 → 040のDD_DISP (EAGの加算器入力) / ILS[15:0] = displacement -> DD_DISP in 040 (EAG adder input)

// 【解説】LS パイプの命令を EX-RM 形式 (メモリオペランド演算) として見たフィールド。
// [Note] Fields of the LS-pipe instruction seen as EX-RM format (operation with a memory operand).
assign ILS_OP2MODE = ex_op2mode(ILS);                   // ILS[30:29]: EX-RM形式の判定に使う / ILS[30:29]: used for the EX-RM format check
assign ILS_SETCC = ex_setcc(ILS);                       // ILS[28]: メモリオペランド演算がCCを変えるか / ILS[28]: does the mem-operand op set CC
assign ILS_EXU_OPC = ex_exu_opc(ILS);                   // ILS[27:24]: メモリオペランド演算の種類 (EのALUへ) / ILS[27:24]: mem-operand operation (to the E ALU)
//ILS-RB1 	= ex_rb1(ILS)
assign ILS_RS2 = ex_rs2(ILS);                           // ILS[15:12]: EX-RMのレジスタ側オペランドRS → 150のA_LS_RADS (Bで読む) / ILS[15:12]: EX-RM register operand RS -> A_LS_RADS in 150 (read in B)
assign ILS_RD = ex_rd(ILS);                             // ILS[23:20]: 未使用で消える (RD_RSと同じビット) / ILS[23:20]: unused, removed (same bits as RD_RS)
assign ILS_DISP12 = ex_disp12(ILS);                     // ILS[11:0]: EX-RMの変位 → 040のDD_DISP / ILS[11:0]: EX-RM displacement -> DD_DISP in 040

// 【解説】EX パイプの命令のフィールド。
// [Note] Fields of the EX-pipe instruction.
assign IEX_OP2MODE = ex_op2mode(IEX);                   // IEX[30:29]: RR/RIの区別 → 140 (即値かレジスタか) / IEX[30:29]: RR or RI -> 140 (immediate or register)
assign IEX_SETCC = ex_setcc(IEX);                       // IEX[28]: CCを変えるか → 150 / IEX[28]: set CC -> 150
assign IEX_EXU_OPC = ex_exu_opc(IEX);                   // IEX[27:24]: EXUの演算 → 150のA_EX_OPC / IEX[27:24]: EXU operation -> A_EX_OPC in 150
assign IEX_RB1 = ex_rb1(IEX);                           // IEX[19:16]: 未使用で消える / IEX[19:16]: unused, removed
assign IEX_RS2 = ex_rs2(IEX);                           // IEX[15:12]: 未使用で消える / IEX[15:12]: unused, removed
assign IEX_RD = ex_rd(IEX);                             // IEX[23:20]: 書き込み先 → 150のA_EX_WAD / IEX[23:20]: destination -> A_EX_WAD in 150
assign IEX_DISP12 = ex_disp12(IEX);                     // IEX[11:0]: 未使用で消える / IEX[11:0]: unused, removed

// 【解説】分岐命令のフィールド。
// [Note] Fields of the branch instruction.
assign IJB_COND = jb_cond(IJB);                         // IJB[27]: 条件分岐 → 040, 210 / IJB[27]: conditional -> 040, 210
assign IJB_REG = jb_reg(IJB);                           // IJB[26]: レジスタ相対 → 040 (EAGを使うか) / IJB[26]: register-relative -> 040 (uses the EAG)
assign IJB_LINK = jb_link(IJB);                         // IJB[25]: リンク → 140, 150 (戻り番地をEXパイプで書く) / IJB[25]: link -> 140, 150 (return address written via EX pipe)
assign IJB_CMP = jb_cmp(IJB);                           // IJB[24]: 比較分岐 / IJB[24]: compare branch
assign IJB_RD_MASK = jb_rd_mask(IJB);                   // IJB[23:20]: リンク先GRまたはCCマスク → 150, 210 / IJB[23:20]: link GR or CC mask -> 150, 210
assign IJB_RB1 = jb_rb1(IJB);                           // IJB[19:16]: 未使用で消える / IJB[19:16]: unused, removed
assign IJB_R2_IMM4 = jb_r2_imm4(IJB);                   // IJB[15:12]: 未使用で消える / IJB[15:12]: unused, removed
assign IJB_IMM12 = jb_imm12(IJB);                       // IJB[11:0]: 未使用で消える (比較分岐は未完成) / IJB[11:0]: unused, removed (compare branch unfinished)


assign IEX_IMM16 = ex_imm16(IEX);                       // IEX[15:0]: RIモードの即値 → 140で符号拡張 / IEX[15:0]: RI-mode immediate -> sign-extended in 140

assign IJB_IMM16 = jb_imm16(IJB);                       // IJB[15:0]: レジスタ相対分岐の変位 → 040 / IJB[15:0]: register-relative displacement -> 040
assign IJB_IMM20 = jb_imm20(IJB);                       // IJB[19:0]: PC相対の変位 → 040のDD_TGT加算器 / IJB[19:0]: PC-relative displacement -> DD_TGT adder in 040
assign IJB_BACKWARD = jb_backward(IJB);                 // IJB[19]: 変位の符号=後ろ向き分岐 → 静的予測 (後ろ向きは成立と予測) / IJB[19]: sign = backward -> static prediction (backward = taken)


assign ILS_LS_OPC_H = ls_opc_h(ILS);                    // ILS[31:29]: LS形式判定用 / ILS[31:29]: for LS-format check
assign ILS_EX_OPC_H = ex_opc_h(ILS);                    // ILS[31]: EX形式判定用 / ILS[31]: for EX-format check

// 【解説】LS パイプの命令が本物のロード/ストアか、メモリオペランド演算 (EX-RM) か。
// [Note] Is the LS-pipe instruction a real load/store, or an operation with a memory operand (EX-RM)?
assign ILS_LS_FMT = (ILS_LS_OPC_H == 4) & ILS_V;        // 本物のロード/ストア: 3bit一致とILS_VのAND (LUT4) / a real load/store: 3-bit match AND ILS_V (LUT4)
assign ILS_EXRM_FMT = (ILS_EX_OPC_H == 0) & (ILS_OP2MODE != 0) & ILS_V; // メモリオペランド演算: ILS[31]=0 & OP2MODE!=0 & ILS_V (LUT4) / mem-operand op: ILS[31]=0 & OP2MODE!=0 & ILS_V (LUT4)
