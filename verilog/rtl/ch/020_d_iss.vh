// =====================================================================
//  020_d_iss.vh  <-  hard/020-d-iss.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
// =====================================================================
// ---------------------------------------------------------------------
// 【解説】D サイクル(3): 命令の種類と、使う資源 (パイプ, レジスタ, CC) の判定
//
// STM には 2 本の実行パイプがある:
//   ・LS パイプ: ロード/ストアと、メモリオペランドを持つ演算 (EX 形式の RM モード)
//                → A でアドレス計算, B でキャッシュアクセス, E で ALU
//   ・EX パイプ: レジスタ/即値どうしの演算 (EX 形式の RR, RI モード)
//                → A で EXU により演算
// 分岐 (JB) はリンク付きなら EX パイプを使う。
// ここで 1 命令目 (FIRST = I0) と 2 命令目 (SECOND = I1) それぞれについて、
// どのパイプか、どのレジスタを読み書きするか、CC を変えるかを求め、
// 030_d_sec.vh での同時発行の判定に使う。
// ---------------------------------------------------------------------


// d-iss : deciding insn issue


// Note: LS/EX of format and of pipe have different meaning;
// 	EX-RM is 'EX' in format but 'LS' in pipe!

// 【解説】形式の判定:
//           LS 形式 : 上位 3bit が 100
//           EX 形式 : 最上位ビットが 0 で, OP2MODE が 0 以外
//           JB 形式 : 上位 4bit が 1011
assign DD_I0_LS_FMT = (I0_LS_OPC_H == 4);
assign DD_I0_EX_FMT = (I0_EX_OPC_H == 0) & (I0_EX_OP2MODE != 0);
assign DD_I0_JB_FMT = (I0_INSN_OPC == 11);
assign DD_I1_LS_FMT = (I1_LS_OPC_H == 4);
assign DD_I1_EX_FMT = (I1_EX_OPC_H == 0) & (I1_EX_OP2MODE != 0);
assign DD_I1_JB_FMT = (I1_INSN_OPC == 11);

// decide whether the first/second insn is LS, EX, JB, or privileged op.

// 【解説】どのパイプへ流すか。EX 形式でも RM モード (メモリオペランド) は
//         LS パイプを使う (元コメントの「EX-RM は形式では EX、パイプでは LS」)。
assign DD_FIRST_IS_LS = DD_I0_LS_FMT | DD_I0_EX_FMT & (I0_EX_OP2MODE == EXMOD_RM);
assign DD_SECOND_IS_LS = DD_I1_LS_FMT | DD_I1_EX_FMT & (I1_EX_OP2MODE == EXMOD_RM);

assign DD_FIRST_IS_EX = DD_I0_EX_FMT & (I0_EX_OP2MODE != EXMOD_RM);
assign DD_SECOND_IS_EX = DD_I1_EX_FMT & (I1_EX_OP2MODE != EXMOD_RM);

assign DD_FIRST_IS_JB = DD_I0_JB_FMT;
assign DD_SECOND_IS_JB = DD_I1_JB_FMT;

// 【解説】1 命令目が特権命令 (上位 4bit = 1100) ならその種類 (RFE/RSR/WSR)。
//         特権命令は 1 命令目としてしか扱わない (2 命令目なら同時発行しない)。
assign DD_PRIVCODE = ((I0_INSN_OPC == 12) ? I0_PRIV_OPC : 0);
assign DD_SECOND_PRIV_V = (I1_INSN_OPC == 12);

// and if they use GR or set CC

//  sets   CC  <-->  EX & SETCC
//  writes RD  <-->  LD | EX & !(C/CU) | JB & LINK
//  reads  RB  <-->  LS | EX & RM      | JB & REG
//  reads  R1  <-->  EX & (RR|RI)      | JB & cmp
//  reads  R2  <-->  EX &  RR          | JB & cmp
//  reading CC or RS is never an obstacle for  second insn issue

// 【解説】1 命令目が CC (条件コード) を変えるか。
assign DD_FIRST_SETCC = DD_I0_EX_FMT & I0_EX_SETCC;
// 【解説】1 命令目が書き込むレジスタ番号 (RD は全形式で同じ位置 [23:20])
//         と、実際に GR へ書くかどうか (ロード / C,CU 以外の演算 / リンク付き分岐)。
assign DD_FIRST_WAD = I0_EX_RD;
assign DD_FIRST_WAD_V = DD_I0_LS_FMT & !I0_LS_STORE
	        | DD_I0_EX_FMT & we_on(I0_EX_EXU_OPC)
	        | DD_I0_JB_FMT & I0_JB_LINK;
// 【解説】読み出すレジスタの有無:
//           RADB : ベースレジスタ (LS パイプ, レジスタ間接分岐)
//           RAD2 : 第 2 オペランド (RR モード, 比較分岐, WSR)
//           RAD1 : 第 1 オペランド (RI / RR モード, 比較分岐)
assign DD_FIRST_RADB_V = DD_FIRST_IS_LS | DD_I0_JB_FMT & I0_JB_REG;
assign DD_FIRST_RAD2_V = DD_I0_EX_FMT & (I0_EX_OP2MODE == EXMOD_RR)
                | DD_I0_JB_FMT & I0_JB_CMP | (DD_PRIVCODE == PRIVCODE_WSR);
assign DD_FIRST_RAD1_V = DD_I0_EX_FMT & (I0_EX_OP2MODE == EXMOD_RI) | DD_FIRST_RAD2_V;
assign DD_FIRST_RADB1 = I0_EX_RB1;
assign DD_FIRST_RAD2 = I0_EX_RS2;

// 【解説】以下 2 命令目 (I1) について同じ。
assign DD_SECOND_SETCC = DD_I1_EX_FMT & I1_EX_SETCC;
assign DD_SECOND_WAD = I1_EX_RD;
assign DD_SECOND_WAD_V = DD_I1_LS_FMT & !I1_LS_STORE
		  | DD_I1_EX_FMT & we_on(I1_EX_EXU_OPC)
	          | DD_I1_JB_FMT & I1_JB_LINK;
assign DD_SECOND_RADB_V = DD_SECOND_IS_LS | DD_I1_JB_FMT & I1_JB_REG;
assign DD_SECOND_RAD2_V = DD_I1_EX_FMT & (I1_EX_OP2MODE == EXMOD_RR)
		  | DD_I1_JB_FMT & I1_JB_CMP;
assign DD_SECOND_RAD1_V = DD_I1_EX_FMT & (I1_EX_OP2MODE == EXMOD_RI) | DD_SECOND_RAD2_V;
assign DD_SECOND_RADB1 = I1_EX_RB1;
assign DD_SECOND_RAD2 = I1_EX_RS2;
