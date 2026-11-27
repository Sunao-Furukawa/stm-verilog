// =====================================================================
//  stm_const.vh  <-  hard/const.h
//  STM 定数定義 (モジュール本体の中で `include して使う localparam)
//  STM constant definitions (localparams, `include'd inside module bodies)
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
localparam [1:0] EXMOD_RI = 2'd3;   // B'11'  -- 即値モード (R1 op imm16) / immediate mode (R1 op imm16)
localparam [1:0] EXMOD_RR = 2'd1;   // B'01'  -- レジスタモード (R1 op R2) / register mode (R1 op R2)
localparam [1:0] EXMOD_RM = 2'd2;   // B'10'  -- メモリモード (RS op M) → LSパイプで実行 / memory mode (RS op M) -> runs in the LS pipe

// EXU opcode (5 bit: 0-15 は EX 命令と共通, 16-31 はバイト/ハーフワード L/ST)
//      (5 bits: 0-15 are shared with the EX instructions, 16-31 are byte/halfword L/ST)
// 【解説】A=加算, S=減算, C=比較(結果は書かない), AU/SU/CU=符号なし版,
//         N/O/X=AND/OR/XOR, SL/SRA/SRL=シフト, SETHI=上位 16bit に即値
//         LDBn/LDHn = n 番目のバイト/ハーフワードを読む (n はアドレス下位, 0 が最上位側)
//         STBn/STHn = メモリ語の n 番目のバイト/ハーフワードを書き換える
//
// [Note] A=add, S=subtract, C=compare (result not written), AU/SU/CU=unsigned versions,
//        N/O/X=AND/OR/XOR, SL/SRA/SRL=shifts, SETHI=immediate into the upper 16 bits
//        LDBn/LDHn = read the n-th byte/halfword (n is the low address bits, 0 is the most significant side)
//        STBn/STHn = rewrite the n-th byte/halfword of the memory word
localparam [4:0] OPC_LDW   = 5'd0;                      // 語ロード (ALUはyを素通し) = 00000 / word load (ALU passes y) = 00000
localparam [4:0] OPC_STW   = 5'd4;                      // 語ストア (ALUはxを素通し) = 00100 / word store (ALU passes x) = 00100
localparam [4:0] OPC_A     = 5'd1;  // opcode for ADD  -- 加算 x+y (オーバーフロー例外あり) / add x+y (with overflow trap)
localparam [4:0] OPC_S     = 5'd2;                      // 減算 x-y (CCとオーバーフロー) / subtract x-y (CC and overflow)
localparam [4:0] OPC_C     = 5'd3;                      // 比較 = 減算してCCだけ (GRに書かない) / compare = subtract, CC only (no GR write)
localparam [4:0] OPC_AU    = 5'd5;                      // 符号なし加算 (オーバーフロー例外なし, リンク番地の計算にも使う) / unsigned add (no overflow trap; also used for the link address)
localparam [4:0] OPC_SU    = 5'd6;                      // 符号なし減算 / unsigned subtract
localparam [4:0] OPC_CU    = 5'd7;                      // 符号なし比較 (GRに書かない) / unsigned compare (no GR write)
localparam [4:0] OPC_N     = 5'd8;                      // AND / AND
localparam [4:0] OPC_O     = 5'd9;                      // OR / OR
localparam [4:0] OPC_X     = 5'd10;                     // XOR / XOR
localparam [4:0] OPC_SL    = 5'd11;                     // 左シフト / shift left
localparam [4:0] OPC_SRA   = 5'd12;                     // 算術右シフト / arithmetic shift right
localparam [4:0] OPC_SRL   = 5'd13;                     // 論理右シフト / logical shift right
localparam [4:0] OPC_SETHI = 5'd14;                     // 上位16bitに即値をセット / set the upper 16 bits to the immediate

// 【解説】16 以上 (bit4=1) はバイト/ハーフワード系。5bit の各ビットの意味は
//           bit4 = サブワード,  bit3 = ストア,  bit2 = ハーフワード,
//           bit1..0 = 語の中の位置 (アドレス下位 2bit。110_b_act.vh で埋める)
//         なので, 例えば STH2 = 1_1_1_10 = 30。
//
// [Note] 16 and up (bit4=1) are byte/halfword operations. The 5 bits mean
//          bit4 = sub-word,  bit3 = store,  bit2 = halfword,
//          bit1..0 = position in the word (the low 2 address bits, filled in by 110_b_act.vh)
//        so, for example, STH2 = 1_1_1_10 = 30.
localparam [4:0] OPC_LDB0  = 5'd16;                     // バイトロード, 語の中の0番目(最上位)バイト = 1_0_0_00 / byte load, byte 0 (most significant) = 1_0_0_00
localparam [4:0] OPC_LDB1  = 5'd17;                     // バイトロード, 1番目 = 1_0_0_01 / byte load, byte 1 = 1_0_0_01
localparam [4:0] OPC_LDB2  = 5'd18;                     // バイトロード, 2番目 = 1_0_0_10 / byte load, byte 2 = 1_0_0_10
localparam [4:0] OPC_LDB3  = 5'd19;                     // バイトロード, 3番目(最下位) = 1_0_0_11 / byte load, byte 3 (least significant) = 1_0_0_11
localparam [4:0] OPC_LDH0  = 5'd20;                     // ハーフワードロード, 上位 = 1_0_1_00 / halfword load, upper = 1_0_1_00
localparam [4:0] OPC_LDH2  = 5'd22;                     // ハーフワードロード, 下位 = 1_0_1_10 / halfword load, lower = 1_0_1_10
localparam [4:0] OPC_STB0  = 5'd24;                     // バイトストア, 0番目に埋め込む = 1_1_0_00 / byte store into byte 0 = 1_1_0_00
localparam [4:0] OPC_STB1  = 5'd25;                     // バイトストア, 1番目 = 1_1_0_01 / byte store into byte 1 = 1_1_0_01
localparam [4:0] OPC_STB2  = 5'd26;                     // バイトストア, 2番目 = 1_1_0_10 / byte store into byte 2 = 1_1_0_10
localparam [4:0] OPC_STB3  = 5'd27;                     // バイトストア, 3番目 = 1_1_0_11 / byte store into byte 3 = 1_1_0_11
localparam [4:0] OPC_STH0  = 5'd28;                     // ハーフワードストア, 上位 = 1_1_1_00 / halfword store, upper = 1_1_1_00
localparam [4:0] OPC_STH2  = 5'd30;                     // ハーフワードストア, 下位 = 1_1_1_10 / halfword store, lower = 1_1_1_10

// SU opcode
// 【解説】S ユニット (オペランドキャッシュ) への要求の種類
//         LD = ロード, ST = ストアの最初のアクセス, ST2 = ストアバッファからの実書き込み
// [Note] Kinds of request to the S unit (operand cache)
//        LD = load, ST = first access of a store, ST2 = the actual write from the store buffer
localparam [1:0] SU_OPC_LD  = 2'd1;                     // Sユニット要求: ロード (読み出し) / S-unit request: load (read)
localparam [1:0] SU_OPC_ST  = 2'd2;                     // Sユニット要求: ストアの1回目 (ラインの確保と読み出し) / S-unit request: first store access (claim line, read)
localparam [1:0] SU_OPC_ST2 = 2'd3;                     // Sユニット要求: STBからの実書き込み (割り込みでも取り消さない) / S-unit request: real write from STB (not cancelled by interrupts)

// Privileged operation code
// 【解説】特権命令: RFE = 割り込みからの復帰, RSR/WSR = システムレジスタの読み/書き
// [Note] Privileged instructions: RFE = return from interrupt, RSR/WSR = system register read/write
localparam [1:0] PRIVCODE_RFE = 2'd1;                   // 特権命令: 割り込みからの復帰 / privileged: return from exception
localparam [1:0] PRIVCODE_RSR = 2'd2;                   // 特権命令: システムレジスタ→GR / privileged: system register -> GR
localparam [1:0] PRIVCODE_WSR = 2'd3;                   // 特権命令: GR→システムレジスタ / privileged: GR -> system register

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
localparam [2:0] INTCODE_OP  = 3'd1;                    // 割り込み: 不正命令 (Dで検出) / interrupt: illegal instruction (found in D)
localparam [2:0] INTCODE_CMP = 3'd2;                    // 割り込み: アドレス比較一致 (Bで検出) / interrupt: address compare match (found in B)
localparam [2:0] INTCODE_TLB = 3'd3;                    // 割り込み: TLB (未実装) / Verilog版ではバスエラー / interrupt: TLB (unimplemented) / bus error in the Verilog version
localparam [2:0] INTCODE_OVF = 3'd4;                    // 割り込み: 演算オーバーフロー (EXUで検出) / interrupt: arithmetic overflow (found by the EXU)

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
localparam [3:0] SYSREG_PSW  = 4'd0;                    // SR0: PSW (書くとパイプラインやり直し) / SR0: PSW (writing restarts the pipeline)
localparam [3:0] SYSREG_TBR  = 4'd2;                    // SR2: 割り込みハンドラの番地 / SR2: interrupt handler address
localparam [3:0] SYSREG_CMPR = 4'd3;                    // SR3: アドレス比較レジスタ / SR3: address compare register
localparam [3:0] SYSREG_XPSW = 4'd4;                    // SR4: 割り込み時のPSWの退避先 / SR4: PSW saved on interrupt
localparam [3:0] SYSREG_XPC  = 4'd5;                    // SR5: 割り込み時の戻り番地 / SR5: return address saved on interrupt
localparam [3:0] SYSREG_XLA  = 4'd6;                    // SR6: 例外を起こしたアクセスの番地 / SR6: address of the faulting access
localparam [3:0] SYSREG_SVR0 = 4'd8;                    // SR8: ソフトウェア用の退避レジスタ0 / SR8: scratch register 0 for software
localparam [3:0] SYSREG_SVR1 = 4'd9;                    // SR9: ソフトウェア用の退避レジスタ1 / SR9: scratch register 1 for software
