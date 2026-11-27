// =====================================================================
//  020_d_iss.vh  <-  hard/020-d-iss.ch
//  (stm_cntl.v の中に `include される。宣言は stm_cntl.v 側にある)
//  (included inside stm_cntl.v; the declarations are in stm_cntl.v)
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
//
// [Note] D cycle (3): kind of instruction and the resources it uses (pipe, registers, CC)
//
// STM has two execution pipes:
//   - LS pipe: loads/stores and operations with a memory operand (RM mode of EX format)
//              -> address in A, cache access in B, ALU in E
//   - EX pipe: register/immediate operations (RR, RI modes of EX format)
//              -> computed by the EXU in A
// A branch (JB) with link uses the EX pipe.
// Here, for the first instruction (FIRST = I0) and the second (SECOND = I1), we find
// which pipe it uses, which registers it reads and writes, and whether it changes CC,
// for the dual-issue decision in 030_d_sec.vh.
//
// 【ネットリスト解説】
//   入力 : 015 のフィールド (I0_* / I1_*)
//   出力 : DD_FIRST_* / DD_SECOND_*  -> 030 (同時発行の判定), 040 (分岐), 140 (バイパス),
//                                      150 (A のタグ), 070 (DD_FIRST_IS_JB)
//          DD_PRIVCODE              -> 030, 070, 150
//   回路の形: 命令語の上位 8bit 程度を入力とする小さな組合せ回路 (デコーダ) が
//   I0 用と I1 用に 1 組ずつ。各出力は 1bit で、多くは LUT 1 個で作れる。
//   DD_FIRST_WAD / DD_FIRST_RADB1 / DD_FIRST_RAD2 などのレジスタ番号は
//   命令語のビットそのもの (配線) で、DD_FIRST_RADB1 / DD_FIRST_RAD2 は
//   どこからも使われないので消える。
//   ここは IWQ の FF から数えて 2 段目くらいの浅い論理だが、次の 030 の
//   DD_ISSUE_SECOND_INSN がこれらをすべて集めるので、D サイクルの経路の入口になる。
//
// [Netlist notes]
//   Inputs : fields from 015 (I0_* / I1_*)
//   Outputs: DD_FIRST_* / DD_SECOND_*  -> 030 (dual-issue decision), 040 (branch), 140 (bypass),
//                                        150 (A-stage tags), 070 (DD_FIRST_IS_JB)
//            DD_PRIVCODE              -> 030, 070, 150
//   Circuit: one small decoder (combinational logic on roughly the top 8 bits of the
//   instruction word) for I0 and one for I1. Each output is 1 bit, and most fit in 1 LUT.
//   Register numbers such as DD_FIRST_WAD / DD_FIRST_RADB1 / DD_FIRST_RAD2 are just bits of
//   the instruction word (wires); DD_FIRST_RADB1 / DD_FIRST_RAD2 are unused and disappear.
//   This is shallow logic, about 2 levels from the IWQ FFs, but DD_ISSUE_SECOND_INSN in 030
//   gathers all of it, so it is where the long D-cycle paths begin.
// ---------------------------------------------------------------------


// d-iss : deciding insn issue


// Note: LS/EX of format and of pipe have different meaning;
// 	EX-RM is 'EX' in format but 'LS' in pipe!

// 【解説】形式の判定:
//           LS 形式 : 上位 3bit が 100
//           EX 形式 : 最上位ビットが 0 で, OP2MODE が 0 以外
//           JB 形式 : 上位 4bit が 1011
//
// [Note] Format decision:
//          LS format : top 3 bits are 100
//          EX format : top bit is 0 and OP2MODE is not 0
//          JB format : top 4 bits are 1011
assign DD_I0_LS_FMT = (I0_LS_OPC_H == 4);               // I0[31:29]==100ならLS形式: 3入力AND (LUT3) / LS format if I0[31:29]==100: 3-input AND (LUT3)
assign DD_I0_EX_FMT = (I0_EX_OPC_H == 0) & (I0_EX_OP2MODE != 0); // I0[31]=0かつOP2MODE!=0ならEX形式: 3入力のLUT / EX format if I0[31]=0 and OP2MODE!=0: 3-input LUT
assign DD_I0_JB_FMT = (I0_INSN_OPC == 11);              // I0[31:28]==1011ならJB形式: 4入力AND (LUT4) / JB format if I0[31:28]==1011: 4-input AND (LUT4)
assign DD_I1_LS_FMT = (I1_LS_OPC_H == 4);               // I1のLS形式判定 (I0と同じデコーダの2組目) / LS format of I1 (second copy of the decoder)
assign DD_I1_EX_FMT = (I1_EX_OPC_H == 0) & (I1_EX_OP2MODE != 0); // I1のEX形式判定 / EX format of I1
assign DD_I1_JB_FMT = (I1_INSN_OPC == 11);              // I1のJB形式判定 / JB format of I1

// decide whether the first/second insn is LS, EX, JB, or privileged op.

// 【解説】どのパイプへ流すか。EX 形式でも RM モード (メモリオペランド) は
//         LS パイプを使う (元コメントの「EX-RM は形式では EX、パイプでは LS」)。
// [Note] Which pipe to use. Even in EX format, RM mode (memory operand) uses the LS pipe
//        (the original comment: "EX-RM is 'EX' in format but 'LS' in pipe").
assign DD_FIRST_IS_LS = DD_I0_LS_FMT | DD_I0_EX_FMT & (I0_EX_OP2MODE == EXMOD_RM); // I0がLSパイプへ: LS形式またはEXのRMモード (LUT1個) / I0 goes to the LS pipe: LS format or EX RM mode (1 LUT)
assign DD_SECOND_IS_LS = DD_I1_LS_FMT | DD_I1_EX_FMT & (I1_EX_OP2MODE == EXMOD_RM); // I1がLSパイプへ (同上) / I1 goes to the LS pipe (same)

assign DD_FIRST_IS_EX = DD_I0_EX_FMT & (I0_EX_OP2MODE != EXMOD_RM); // I0がEXパイプへ: EX形式でRM以外 (RR/RI) / I0 goes to the EX pipe: EX format, not RM (RR/RI)
assign DD_SECOND_IS_EX = DD_I1_EX_FMT & (I1_EX_OP2MODE != EXMOD_RM); // I1がEXパイプへ / I1 goes to the EX pipe

assign DD_FIRST_IS_JB = DD_I0_JB_FMT;                   // I0が分岐: DD_I0_JB_FMTの別名 (ゲート無し) / I0 is a branch: alias of DD_I0_JB_FMT (no gate)
assign DD_SECOND_IS_JB = DD_I1_JB_FMT;                  // I1が分岐: 別名 / I1 is a branch: alias

// 【解説】1 命令目が特権命令 (上位 4bit = 1100) ならその種類 (RFE/RSR/WSR)。
//         特権命令は 1 命令目としてしか扱わない (2 命令目なら同時発行しない)。
// [Note] If the first instruction is privileged (top 4 bits = 1100), its kind (RFE/RSR/WSR).
//        Privileged instructions are only handled as the first instruction (as the second, no dual issue).
assign DD_PRIVCODE = ((I0_INSN_OPC == 12) ? I0_PRIV_OPC : 0); // I0が特権命令(1100)なら種類, 違えば0: 2bit x (4入力一致AND) / kind if I0 is privileged (1100), else 0: 2 bits gated by a 4-input match
assign DD_SECOND_PRIV_V = (I1_INSN_OPC == 12);          // I1が特権命令か: LUT4 (030で同時発行を止める) / is I1 privileged: LUT4 (030 blocks dual issue)

// and if they use GR or set CC

//  sets   CC  <-->  EX & SETCC
//  writes RD  <-->  LD | EX & !(C/CU) | JB & LINK
//  reads  RB  <-->  LS | EX & RM      | JB & REG
//  reads  R1  <-->  EX & (RR|RI)      | JB & cmp
//  reads  R2  <-->  EX &  RR          | JB & cmp
//  reading CC or RS is never an obstacle for  second insn issue

// 【解説】1 命令目が CC (条件コード) を変えるか。
// [Note] Does the first instruction change CC (the condition code)?
assign DD_FIRST_SETCC = DD_I0_EX_FMT & I0_EX_SETCC;     // I0がCCを変える: EX形式 & SETCCビット (AND) / I0 sets CC: EX format AND SETCC bit
// 【解説】1 命令目が書き込むレジスタ番号 (RD は全形式で同じ位置 [23:20])
//         と、実際に GR へ書くかどうか (ロード / C,CU 以外の演算 / リンク付き分岐)。
// [Note] Register number written by the first instruction (RD is at the same place [23:20] in every format)
//        and whether it really writes GR (load / operation other than C,CU / branch with link).
assign DD_FIRST_WAD = I0_EX_RD;                         // I0の書き込み先番号 = I0[23:20] (配線) / I0 write register number = I0[23:20] (wires)
assign DD_FIRST_WAD_V = DD_I0_LS_FMT & !I0_LS_STORE     // I0がGRへ書くか: ロード(非ストア)... / does I0 write a GR: a load (not a store) ...
	        | DD_I0_EX_FMT & we_on(I0_EX_EXU_OPC)          // ...またはC/CU/0以外の演算 (we_onはLUT4の真理値表) ... / ... or an operation other than C/CU/0 (we_on is a LUT4 truth table) ...
	        | DD_I0_JB_FMT & I0_JB_LINK;                   // ...またはリンク付き分岐。全体で上位8bitの関数 → LUT2個程度 / ... or a branch with link. A function of the top 8 bits -> about 2 LUTs
// 【解説】読み出すレジスタの有無:
//           RADB : ベースレジスタ (LS パイプ, レジスタ間接分岐)
//           RAD2 : 第 2 オペランド (RR モード, 比較分岐, WSR)
//           RAD1 : 第 1 オペランド (RI / RR モード, 比較分岐)
//
// [Note] Which registers are read:
//          RADB : base register (LS pipe, register-indirect branch)
//          RAD2 : second operand (RR mode, compare branch, WSR)
//          RAD1 : first operand (RI / RR mode, compare branch)
assign DD_FIRST_RADB_V = DD_FIRST_IS_LS | DD_I0_JB_FMT & I0_JB_REG; // I0がベースレジスタRBを読む: LSパイプ行き or レジスタ間接分岐 / I0 reads base RB: LS pipe or register-indirect branch
assign DD_FIRST_RAD2_V = DD_I0_EX_FMT & (I0_EX_OP2MODE == EXMOD_RR) // I0が第2オペランドR2を読む: RRモード ... / I0 reads operand R2: RR mode ...
                | DD_I0_JB_FMT & I0_JB_CMP | (DD_PRIVCODE == PRIVCODE_WSR); // ...比較分岐, WSR (R2の値をシステムレジスタへ書く) / ... compare branch, WSR (writes R2 to a system register)
assign DD_FIRST_RAD1_V = DD_I0_EX_FMT & (I0_EX_OP2MODE == EXMOD_RI) | DD_FIRST_RAD2_V; // I0がR1を読む: RIモード or R2を読む命令すべて (OR 1段) / I0 reads R1: RI mode or anything that reads R2 (one OR)
assign DD_FIRST_RADB1 = I0_EX_RB1;                      // I0のR1/RB番号 I0[19:16]: 未使用で合成で消える / I0 R1/RB number I0[19:16]: unused, removed by synthesis
assign DD_FIRST_RAD2 = I0_EX_RS2;                       // I0のR2番号 I0[15:12]: 未使用で消える / I0 R2 number I0[15:12]: unused, removed

// 【解説】以下 2 命令目 (I1) について同じ。
// [Note] The same for the second instruction (I1) below.
assign DD_SECOND_SETCC = DD_I1_EX_FMT & I1_EX_SETCC;    // I1がCCを変える (I0と同じ形) / I1 sets CC (same form as I0)
assign DD_SECOND_WAD = I1_EX_RD;                        // I1の書き込み先番号 I1[23:20] (配線) / I1 write register number I1[23:20] (wires)
assign DD_SECOND_WAD_V = DD_I1_LS_FMT & !I1_LS_STORE    // I1がGRへ書くか: ロード ... / does I1 write a GR: a load ...
		  | DD_I1_EX_FMT & we_on(I1_EX_EXU_OPC)               // ...C/CU以外の演算 ... / ... an operation other than C/CU ...
	          | DD_I1_JB_FMT & I1_JB_LINK;                 // ...リンク付き分岐 (LUT2個程度) / ... a branch with link (about 2 LUTs)
assign DD_SECOND_RADB_V = DD_SECOND_IS_LS | DD_I1_JB_FMT & I1_JB_REG; // I1がRBを読む / I1 reads RB
assign DD_SECOND_RAD2_V = DD_I1_EX_FMT & (I1_EX_OP2MODE == EXMOD_RR) // I1がR2を読む: RRモード ... / I1 reads R2: RR mode ...
		  | DD_I1_JB_FMT & I1_JB_CMP;                         // ...比較分岐 (2命令目にWSRは来ないので項が無い) / ... compare branch (no WSR term: never the second insn)
assign DD_SECOND_RAD1_V = DD_I1_EX_FMT & (I1_EX_OP2MODE == EXMOD_RI) | DD_SECOND_RAD2_V; // I1がR1を読む / I1 reads R1
assign DD_SECOND_RADB1 = I1_EX_RB1;                     // I1のR1/RB番号: 未使用で消える / I1 R1/RB number: unused, removed
assign DD_SECOND_RAD2 = I1_EX_RS2;                      // I1のR2番号: 未使用で消える / I1 R2 number: unused, removed
