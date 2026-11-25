// =====================================================================
//  stm_const.vh  <-  hard/const.h
//  STM 定数定義 (モジュール本体の中で `include して使う localparam)
//
// 【ネットリスト解説】
//   localparam は回路を作らない。式の中で使われると、合成ツールはその値を
//   定数として埋め込み、比較 (例: OP_B_OPC == SU_OPC_ST2) を「特定ビットの
//   AND/NOT」に、定数の代入 (例: cc = 2'd3) を電源/グランドへの接続に変える。
//   そのためコードの値を変えると、比較器の形 (LUT の真理値表) が変わるだけで
//   回路の規模はほとんど変わらない。
//   モジュールごとに `include するので、stm_cntl と stm_exu はそれぞれ
//   自分の localparam のコピーを持つ (Verilog-2001 には package が無いため)。
//
// [Netlist notes]
//   A localparam makes no circuit. When it is used in an expression, synthesis embeds the
//   value as a constant: a compare (e.g. OP_B_OPC == SU_OPC_ST2) becomes an AND/NOT of
//   specific bits, and a constant assignment (e.g. cc = 2'd3) becomes a connection to
//   power/ground. So changing a code value only changes the shape of a comparator (the truth
//   table of a LUT) and hardly changes the size of the circuit.
//   This file is `include'd in each module, so stm_cntl and stm_exu each have their own copy
//   of the localparams (Verilog-2001 has no packages).
// =====================================================================

// Operand type of EX_insn : 2nd operand is immediate/register/memory
// 【解説】EX 形式の第 2 オペランドの種類 (命令の OP2MODE フィールド)
//         RI = 即値, RR = レジスタ, RM = メモリ (LS パイプで実行される)
// [Note] Kind of second operand of the EX format (the OP2MODE field of the instruction)
//        RI = immediate, RR = register, RM = memory (executed in the LS pipe)
localparam [1:0] EXMOD_RI = 2'd3;   // B'11'
localparam [1:0] EXMOD_RR = 2'd1;   // B'01'
localparam [1:0] EXMOD_RM = 2'd2;   // B'10'

// EXU opcode (5 bit: 0-15 は EX 命令と共通, 16-31 はバイト/ハーフワード L/ST)
// 【解説】A=加算, S=減算, C=比較(結果は書かない), AU/SU/CU=符号なし版,
//         N/O/X=AND/OR/XOR, SL/SRA/SRL=シフト, SETHI=上位 16bit に即値
//         LDBn/LDHn = n 番目のバイト/ハーフワードを読む (n はアドレス下位, 0 が最上位側)
//         STBn/STHn = メモリ語の n 番目のバイト/ハーフワードを書き換える
//
// [Note] A=add, S=subtract, C=compare (result not written), AU/SU/CU=unsigned versions,
//        N/O/X=AND/OR/XOR, SL/SRA/SRL=shifts, SETHI=immediate into the upper 16 bits
//        LDBn/LDHn = read the n-th byte/halfword (n is the low address bits, 0 is the most significant side)
//        STBn/STHn = rewrite the n-th byte/halfword of the memory word
localparam [4:0] OPC_LDW   = 5'd0;
localparam [4:0] OPC_STW   = 5'd4;
localparam [4:0] OPC_A     = 5'd1;  // opcode for ADD
localparam [4:0] OPC_S     = 5'd2;
localparam [4:0] OPC_C     = 5'd3;
localparam [4:0] OPC_AU    = 5'd5;
localparam [4:0] OPC_SU    = 5'd6;
localparam [4:0] OPC_CU    = 5'd7;
localparam [4:0] OPC_N     = 5'd8;
localparam [4:0] OPC_O     = 5'd9;
localparam [4:0] OPC_X     = 5'd10;
localparam [4:0] OPC_SL    = 5'd11;
localparam [4:0] OPC_SRA   = 5'd12;
localparam [4:0] OPC_SRL   = 5'd13;
localparam [4:0] OPC_SETHI = 5'd14;

// 【解説】16 以上 (bit4=1) はバイト/ハーフワード系。5bit の各ビットの意味は
//           bit4 = サブワード,  bit3 = ストア,  bit2 = ハーフワード,
//           bit1..0 = 語の中の位置 (アドレス下位 2bit。110_b_act.vh で埋める)
//         なので, 例えば STH2 = 1_1_1_10 = 30。
//
// [Note] 16 and up (bit4=1) are byte/halfword operations. The 5 bits mean
//          bit4 = sub-word,  bit3 = store,  bit2 = halfword,
//          bit1..0 = position in the word (the low 2 address bits, filled in by 110_b_act.vh)
//        so, for example, STH2 = 1_1_1_10 = 30.
localparam [4:0] OPC_LDB0  = 5'd16;
localparam [4:0] OPC_LDB1  = 5'd17;
localparam [4:0] OPC_LDB2  = 5'd18;
localparam [4:0] OPC_LDB3  = 5'd19;
localparam [4:0] OPC_LDH0  = 5'd20;
localparam [4:0] OPC_LDH2  = 5'd22;
localparam [4:0] OPC_STB0  = 5'd24;
localparam [4:0] OPC_STB1  = 5'd25;
localparam [4:0] OPC_STB2  = 5'd26;
localparam [4:0] OPC_STB3  = 5'd27;
localparam [4:0] OPC_STH0  = 5'd28;
localparam [4:0] OPC_STH2  = 5'd30;

// SU opcode
// 【解説】S ユニット (オペランドキャッシュ) への要求の種類
//         LD = ロード, ST = ストアの最初のアクセス, ST2 = ストアバッファからの実書き込み
// [Note] Kinds of request to the S unit (operand cache)
//        LD = load, ST = first access of a store, ST2 = the actual write from the store buffer
localparam [1:0] SU_OPC_LD  = 2'd1;
localparam [1:0] SU_OPC_ST  = 2'd2;
localparam [1:0] SU_OPC_ST2 = 2'd3;

// Privileged operation code
// 【解説】特権命令: RFE = 割り込みからの復帰, RSR/WSR = システムレジスタの読み/書き
// [Note] Privileged instructions: RFE = return from interrupt, RSR/WSR = system register read/write
localparam [1:0] PRIVCODE_RFE = 2'd1;
localparam [1:0] PRIVCODE_RSR = 2'd2;
localparam [1:0] PRIVCODE_WSR = 2'd3;

// Interruption code
// 【解説】割り込みの種類: OP = 不正命令, CMP = アドレス比較, TLB = (未実装), OVF = 演算オーバーフロー
//         0 は「割り込み無し」で、各ステージの xx_INTCODE != 0 が割り込みの有効ビットを
//         兼ねる。W で PSW の TYPE (8bit) に 0 拡張して記録される (080_w_act.vh)。
//         Verilog 版の AXI4 構成では、バスエラーのデータアクセス例外に TLB (3) を使う。
//
// [Note] Kinds of interrupt: OP = illegal instruction, CMP = address compare, TLB = (not implemented), OVF = arithmetic overflow
//        0 means "no interrupt", so xx_INTCODE != 0 of each stage doubles as the interrupt
//        valid bit. W records it zero-extended in TYPE (8 bits) of PSW (080_w_act.vh).
//        The AXI4 configuration of the Verilog version uses TLB (3) for the data access exception on a bus error.
localparam [2:0] INTCODE_OP  = 3'd1;
localparam [2:0] INTCODE_CMP = 3'd2;
localparam [2:0] INTCODE_TLB = 3'd3;
localparam [2:0] INTCODE_OVF = 3'd4;

// System Register Number
// 【解説】PSW = 状態 (CC/ユーザー/割り込み種別), TBR = 割り込みハンドラ番地,
//         CMPR = 比較番地, XPSW/XPC/XLA = 割り込み時の退避 (PSW/PC/アドレス),
//         SVR0/1 = 退避用レジスタ
//         番号 0〜3 を WSR で書くと、動作状態が変わるとみなしてパイプラインを
//         やり直す (050_op_lb1.vh の WW_STATECHANGE。(番号 & 12) == 0 で判定)。
//         1, 7, 10〜15 番は欠番で、RSR で読むと 0 (120_a_dat.vh)。
//
// [Note] PSW = status (CC/user/interrupt type), TBR = interrupt handler address,
//        CMPR = compare address, XPSW/XPC/XLA = saved on interrupt (PSW/PC/address),
//        SVR0/1 = registers for saving values
//        Writing numbers 0-3 with WSR counts as a change of operating state, and the pipeline
//        is restarted (WW_STATECHANGE in 050_op_lb1.vh, tested by (number & 12) == 0).
//        Numbers 1, 7 and 10-15 are unused; RSR reads them as 0 (120_a_dat.vh).
localparam [3:0] SYSREG_PSW  = 4'd0;
localparam [3:0] SYSREG_TBR  = 4'd2;
localparam [3:0] SYSREG_CMPR = 4'd3;
localparam [3:0] SYSREG_XPSW = 4'd4;
localparam [3:0] SYSREG_XPC  = 4'd5;
localparam [3:0] SYSREG_XLA  = 4'd6;
localparam [3:0] SYSREG_SVR0 = 4'd8;
localparam [3:0] SYSREG_SVR1 = 4'd9;
