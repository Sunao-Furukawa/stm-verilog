// =====================================================================
//  stm_const.vh  <-  hard/const.h
//  STM 定数定義 (モジュール本体の中で `include して使う localparam)
// =====================================================================

// Operand type of EX_insn : 2nd operand is immediate/register/memory
// 【解説】EX 形式の第 2 オペランドの種類 (命令の OP2MODE フィールド)
//         RI = 即値, RR = レジスタ, RM = メモリ (LS パイプで実行される)
localparam [1:0] EXMOD_RI = 2'd3;   // B'11'
localparam [1:0] EXMOD_RR = 2'd1;   // B'01'
localparam [1:0] EXMOD_RM = 2'd2;   // B'10'

// EXU opcode (5 bit: 0-15 は EX 命令と共通, 16-31 はバイト/ハーフワード L/ST)
// 【解説】A=加算, S=減算, C=比較(結果は書かない), AU/SU/CU=符号なし版,
//         N/O/X=AND/OR/XOR, SL/SRA/SRL=シフト, SETHI=上位 16bit に即値
//         LDBn/LDHn = n 番目のバイト/ハーフワードを読む (n はアドレス下位, 0 が最上位側)
//         STBn/STHn = メモリ語の n 番目のバイト/ハーフワードを書き換える
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
localparam [1:0] SU_OPC_LD  = 2'd1;
localparam [1:0] SU_OPC_ST  = 2'd2;
localparam [1:0] SU_OPC_ST2 = 2'd3;

// Privileged operation code
// 【解説】特権命令: RFE = 割り込みからの復帰, RSR/WSR = システムレジスタの読み/書き
localparam [1:0] PRIVCODE_RFE = 2'd1;
localparam [1:0] PRIVCODE_RSR = 2'd2;
localparam [1:0] PRIVCODE_WSR = 2'd3;

// Interruption code
// 【解説】割り込みの種類: OP = 不正命令, CMP = アドレス比較, TLB = (未実装), OVF = 演算オーバーフロー
localparam [2:0] INTCODE_OP  = 3'd1;
localparam [2:0] INTCODE_CMP = 3'd2;
localparam [2:0] INTCODE_TLB = 3'd3;
localparam [2:0] INTCODE_OVF = 3'd4;

// System Register Number
// 【解説】PSW = 状態 (CC/ユーザー/割り込み種別), TBR = 割り込みハンドラ番地,
//         CMPR = 比較番地, XPSW/XPC/XLA = 割り込み時の退避 (PSW/PC/アドレス),
//         SVR0/1 = 退避用レジスタ
localparam [3:0] SYSREG_PSW  = 4'd0;
localparam [3:0] SYSREG_TBR  = 4'd2;
localparam [3:0] SYSREG_CMPR = 4'd3;
localparam [3:0] SYSREG_XPSW = 4'd4;
localparam [3:0] SYSREG_XPC  = 4'd5;
localparam [3:0] SYSREG_XLA  = 4'd6;
localparam [3:0] SYSREG_SVR0 = 4'd8;
localparam [3:0] SYSREG_SVR1 = 4'd9;
