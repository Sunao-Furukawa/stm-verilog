// =====================================================================
//  stm_exu.v  <-  hard/exu.h
//  演算器 (EXU)。C 関数 exu(opc,x,y,&cc,&z,&intr) を組合せ回路の
//  モジュールにしたもの。A サイクル (EX パイプ) と E サイクル (LS パイプ)
//  で 1 個ずつ使われる。
//
//  C 版との違い (未定義動作/未初期化の扱いだけ):
//   * C 版で値を設定しないケース (未定義 opcode, バイト系の cc) は 0 を出す。
//   * シフト量 (y & 0x3f) が 32 以上のとき C では未定義動作だったが、
//     ここでは SL/SRL は 0, SRA は符号ビットで埋める (数学的な定義)。
//
//  The execution unit (EXU): the C function exu(opc,x,y,&cc,&z,&intr) made into a
//  combinational module. One is used in the A cycle (EX pipe) and one in the E cycle (LS pipe).
//
//  Differences from the C version (only in how undefined behaviour / uninitialised values are handled):
//   * cases where the C version sets no value (undefined opcode, cc of byte operations) output 0.
//   * a shift amount (y & 0x3f) of 32 or more was undefined behaviour in C;
//     here SL/SRL give 0 and SRA fills with the sign bit (the mathematical definition).
//
// 【解説】条件コード CC (2bit) の意味
//   符号付き演算 A / S / C :  0 = 結果が 0,  1 = 負,  2 = 正,  3 = オーバーフロー
//                            (C は比較なのでオーバーフローでも割り込まない)
//   符号なし演算 AU/SU/CU  :  0 = 結果 0 かつキャリーあり,  1 = キャリーなし,
//                            2 = キャリーあり (結果は 0 以外)
//   論理演算・シフト      :  0 = 結果が 0,  1 = 0 以外
//   条件分岐のマスクは 4bit で, 最上位から cc=0,1,2,3 に対応する
//   (アセンブラでは BE=8, BL=4, BG=2, BNE=6, BLE=12, BGE=10)。
//   A / S でオーバーフローすると INTCODE_OVF (4) の割り込みを出す。
//
// [Note] Meaning of the condition code CC (2 bits)
//   signed A / S / C       :  0 = result is 0,  1 = negative,  2 = positive,  3 = overflow
//                             (C is a compare, so overflow does not interrupt)
//   unsigned AU/SU/CU      :  0 = result 0 with carry,  1 = no carry,
//                             2 = carry (result not 0)
//   logic ops, shifts      :  0 = result is 0,  1 = not 0
//   The mask of a conditional branch is 4 bits; from the top bit they stand for cc=0,1,2,3
//   (in the assembler BE=8, BL=4, BG=2, BNE=6, BLE=12, BGE=10).
//   On overflow, A / S raise the INTCODE_OVF (4) interrupt.
//
// 【ネットリスト解説】
//   ・FF を 1 つも持たない純粋な組合せ回路。always @* の中の case は、
//     各 opcode の結果を計算する回路を全部並べて、opc で選ぶ MUX になる
//     (case の順に評価される「if の連鎖」ではなく、並列に計算して選ぶ)。
//   ・中にある主な部品:
//       32bit 加減算器 1 個 (is_sub で y を反転, cin = is_sub。A/S/C/AU/SU/CU で共用)
//       32bit の AND / OR / XOR, 32bit バレルシフタ 3 種 (SL, SRA, SRL),
//       z == 0 の判定 (32 入力の NOR), サブワードの切り出し・はめ込み (配線と MUX)
//   ・stm_cntl の中に 2 個ある:
//       u_a_exu (120_a_dat.vh) : opc の最上位ビットが常に 0 なので、合成で
//                                サブワード系 (16〜31) の回路が消える。
//       u_e_alu (090_e_act.vh) : 16〜31 も使う。シフトと SETHI は E_LS_OPCODE に
//                                現れ得るので (EX-RM 形式) 両方とも残る。
//     インスタンスは 2 つとも同じモジュールでも、つながる定数が違うので
//     合成後の回路は別の形になる (ネットリストでは stm_cntl の中に展開される)。
//   ・cc / intr は z と同じ case の中で作るので、z == 0 の判定 → cc という経路が
//     加算器の後ろにつながる (加算 → 32 入力の 0 判定 → cc)。
//
// [Netlist notes]
//   - A purely combinational circuit without a single FF. The case inside always @* becomes
//     all the per-opcode result circuits side by side and a mux that picks one by opc
//     (they are computed in parallel and selected, not an "if chain" evaluated in case order).
//   - Main parts inside:
//       one 32-bit adder/subtractor (y inverted by is_sub, cin = is_sub; shared by A/S/C/AU/SU/CU),
//       32-bit AND / OR / XOR, three kinds of 32-bit barrel shifters (SL, SRA, SRL),
//       the z == 0 test (a 32-input NOR), sub-word extract/insert (wires and muxes)
//   - There are 2 in stm_cntl:
//       u_a_exu (120_a_dat.vh) : the top bit of opc is always 0, so synthesis removes the
//                                sub-word logic (16-31).
//       u_e_alu (090_e_act.vh) : also uses 16-31. Shifts and SETHI can appear in E_LS_OPCODE
//                                (EX-RM format), so both stay.
//     Even though both instances are the same module, they are tied to different constants, so
//     after synthesis the circuits have different shapes (in the netlist they are expanded
//     inside stm_cntl).
//   - cc / intr are made in the same case as z, so a path z == 0 test -> cc hangs off the adder
//     (add -> 32-input zero test -> cc).
// =====================================================================
module stm_exu (                                        // 演算器 (組合せ回路のみ, FF無し): Aのu_a_exuとEのu_e_aluの2個がインスタンスされる / execution unit (combinational only, no FFs): instantiated twice, u_a_exu (A) and u_e_alu (E)
  input      [4:0]  opc,                                // 演算の種類 (stm_const.vhのOPC_*) / operation (OPC_* in stm_const.vh)
  input      [31:0] x,                                  // 第1オペランド (レジスタ / ストアデータ) / operand x (register / store data)
  input      [31:0] y,                                  // 第2オペランド (レジスタ / 即値 / メモリの語) / operand y (register / immediate / memory word)
  output reg [1:0]  cc,                                 // 条件コード 0=ゼロ 1=負(未満) 2=正(超) 3=オーバーフロー. regでもalways @*なので組合せ / condition code 0 zero, 1 neg/less, 2 pos/greater, 3 overflow. reg but combinational (always @*)
  output reg [31:0] z,                                  // 結果 (組合せ) / result (combinational)
  output reg [2:0]  intr                                // 割り込みコード (オーバーフローならINTCODE_OVF, 他は0) / interrupt code (INTCODE_OVF on overflow, else 0)
);                                                      // ポート宣言の終わり / end of ports
`include "stm_const.vh"                                 // opcode定数をモジュール内に取り込む (回路は増えない) / pull the opcode constants into the module (adds no logic)

  // 加減算: 下位 31bit と最上位ビットを分けて, bit31 へのキャリー(cry1)と
  //         bit31 からのキャリー(cry0)を求める (exu.h と同じ構成)
  // Add/subtract: the low 31 bits and the top bit are handled separately to get the carry
  //               into bit31 (cry1) and the carry out of bit31 (cry0) (same structure as exu.h)
  wire        is_sub = (opc == OPC_S) || (opc == OPC_SU) || // 減算系 (S/SU/C/CU) か: opcの5bit比較 → LUT5 1個 ... / subtract family (S/SU/C/CU)?: a compare of 5 opc bits -> one LUT5 ...
                       (opc == OPC_C) || (opc == OPC_CU); // ...(C, CUも減算) / ... (C, CU subtract too)
  wire [31:0] yy     = is_sub ? ~y : y;                 // 減算ならyを反転 (2の補数の -y = ~y + 1): XOR 32本, 加算器のLUTに吸収 / invert y for subtraction (-y = ~y + 1): 32 XORs absorbed into the adder LUTs
  wire        cin    = is_sub;                          // 減算なら桁上げ入力1 (+1の部分) → CARRY4のCI / carry-in 1 for subtraction (the +1) -> CI of the CARRY4
  wire [31:0] low    = {1'b0, x[30:0]} + {1'b0, yy[30:0]} + cin; // never overflows  -- 下位31bitの加算: CARRY4連鎖 (8個) が1本, 32bit目がbit31へのキャリー / add of the low 31 bits: one chain of 8 CARRY4s, bit 31 is the carry into bit 31
  wire        cry1   = low[31];                                  // carry-in to bit<0>  -- (CHDLのbit<0>=Verilogのbit31) / (CHDL bit<0> = Verilog bit 31)
  wire        sx     = x[31];                           // xの符号ビット / sign bit of x
  wire        sy     = yy[31];                          // yyの符号ビット / sign bit of yy
  wire        cry0   = (sx & sy) | (sy & cry1) | (cry1 & sx);     // carry-out of bit<0>  -- 多数決 (LUT3): bit31からのキャリー / majority (LUT3): carry out of bit 31
  wire [31:0] sum    = {low[31] ^ sx ^ sy, low[30:0]};  // 和: bit31は3入力XOR (sx^sy^bit31へのキャリー), 下位31bitはlowそのもの / sum: bit 31 is a 3-input XOR, low 31 bits are low itself
  wire        sz     = sum[31];                         // 結果の符号 / sign of the result
  wire        ovf    = cry0 ^ cry1;                     // 符号付きオーバーフロー: bit31へ/からのキャリーが違う (XOR) / signed overflow: carry into and out of bit 31 differ (XOR)

  // 【解説】ovf = bit31 へのキャリーと bit31 からのキャリーが違う = 符号付きの桁あふれ。
  //         符号なし演算 (AU/SU/CU) の cc は cry0 (最上位からのキャリー) で決める。
  // [Note] ovf = the carry into bit31 and the carry out of bit31 differ = signed overflow.
  //        The cc of unsigned operations (AU/SU/CU) is decided by cry0 (carry out of the top).

  // 【解説】シフト量は y の下位 6bit (0〜63)。32 以上は Verilog の定義どおり
  //         SL/SRL で 0, SRA で符号ビットの並びになる。シフタは 6bit 選択の
  //         バレルシフタ (MUX 6 段) になる。
  // [Note] The shift amount is the low 6 bits of y (0-63). From 32 up, as Verilog defines it,
  //        SL/SRL give 0 and SRA gives copies of the sign bit. The shifter becomes a barrel
  //        shifter with 6-bit select (6 levels of MUX).
  wire [5:0]  amt    = y[5:0];                          // シフト量 = yの下位6bit → バレルシフタの選択線 / shift amount = low 6 bits of y -> barrel shifter selects

  always @* begin                                       // 組合せ回路 (ラッチを避けるため先に既定値を代入) / combinational block (defaults first to avoid latches)
    z    = 32'd0;                                       // 既定値: 結果0 (未定義opcodeでもラッチにならない) / default: result 0 (no latch even for undefined opcodes)
    cc   = 2'd0;                                        // 既定値: CC=0 / default: CC = 0
    intr = 3'd0;                                        // 既定値: 割り込み無し / default: no interrupt
    case (opc)                                          // opcで結果を選ぶ: 合成では各演算器の出力を選ぶ大きなMUX (opcが選択線) / select by opc: a big mux over every unit's output (opc is the select)
      OPC_LDW : begin z = y; cc = 2'd0; end             // ロード: yを素通し (MUXの入力の1本) / load: pass y (one mux input)
      OPC_STW : begin z = x; cc = 2'd0; end             // ストア: xを素通し / store: pass x

      OPC_A, OPC_S, OPC_C : begin                       // 符号付き加減算と比較 / signed add, subtract, compare
        z = sum;                                        // 結果は加算器の出力 / result is the adder output
        if (ovf && (opc != OPC_C)) begin cc = 2'd3; intr = INTCODE_OVF; end // オーバーフロー (比較以外): cc=3と割り込み / overflow (not compare): cc=3 and interrupt
        else if (sum == 32'd0)                   cc = 2'd0; // ゼロなら cc=0: 32bitのNOR (LUT6 6個+1段) / zero -> cc=0: a 32-bit NOR (6 LUT6s + one level)
        else if ((!sz && !ovf) || (sz && ovf))   cc = 2'd2; // 真の符号が正なら cc=2 (結果の符号をovfで補正) / true sign positive -> cc=2 (result sign corrected by ovf)
        else                                     cc = 2'd1; // それ以外 (負) は cc=1 / otherwise (negative) cc=1
      end                                               // 加減算の終わり / end of add/sub
      OPC_AU, OPC_SU, OPC_CU : begin                    // 符号なし加減算と比較 (オーバーフロー例外なし) / unsigned add, subtract, compare (no overflow trap)
        z = sum;                                        // 同じ加算器を共有 (加算器は1個だけ) / shares the same adder (only one adder)
        if ((sum == 32'd0) && cry0) cc = 2'd0;          // 等しい (ゼロでbit31から桁上げ) → cc=0 / equal (zero with carry out) -> cc=0
        else if (!cry0)             cc = 2'd1;          // 桁上げ無し = 借りあり = 未満 → cc=1 / no carry = borrow = less -> cc=1
        else                        cc = 2'd2;          // それ以外 (超) → cc=2 / otherwise (greater) -> cc=2
      end                                               // 符号なし演算の終わり / end of unsigned ops

      OPC_N   : begin z = x & y; cc = (z == 0) ? 2'd0 : 2'd1; end // AND: 32本のAND (LUT2), ゼロならcc=0 そうでなければ1 / AND: 32 AND gates (LUT2), cc 0 if zero else 1
      OPC_O   : begin z = x | y; cc = (z == 0) ? 2'd0 : 2'd1; end // OR: 32本のOR / OR: 32 OR gates
      OPC_X   : begin z = x ^ y; cc = (z == 0) ? 2'd0 : 2'd1; end // XOR: 32本のXOR (加算器のXORとは別) / XOR: 32 XOR gates (separate from the adder's)

      OPC_SL  : begin z = x << amt;                    cc = (z == 0) ? 2'd0 : 2'd1; end // 左シフト: 6段のMUXのバレルシフタ (32以上で0) / shift left: 6-level mux barrel shifter (0 for 32+)
      OPC_SRA : begin z = $signed(x) >>> amt;          cc = (z == 0) ? 2'd0 : 2'd1; end // 算術右シフト: 上から符号ビットを詰めるシフタ / arithmetic right: shifter filling with the sign bit
      OPC_SRL : begin z = x >> amt;                    cc = (z == 0) ? 2'd0 : 2'd1; end // 論理右シフト: 上から0を詰める (SRAと回路を共有することが多い) / logical right: fills with 0 (often shared with SRA)
      OPC_SETHI:begin z = {y[15:0], 16'h0000};         cc = (z == 0) ? 2'd0 : 2'd1; end // 上位16bitに即値, 下位はGND (配線だけ) / immediate into the top 16 bits, low bits to GND (wires only)

      // バイト/ハーフワード・ロード (ビッグエンディアン: バイト0 が最上位)
      // byte/halfword loads (big-endian: byte 0 is the most significant)
      OPC_LDB0: z = {24'd0, y[31:24]};                  // バイト0 (最上位) を下位8bitへ, 上位は0: 配線+MUX入力 / byte 0 (MSB) to the low 8 bits, rest 0: wires + mux input
      OPC_LDB1: z = {24'd0, y[23:16]};                  // バイト1を下位へ / byte 1 to the low bits
      OPC_LDB2: z = {24'd0, y[15:8]};                   // バイト2を下位へ / byte 2 to the low bits
      OPC_LDB3: z = {24'd0, y[7:0]};                    // バイト3 (最下位) をそのまま / byte 3 (LSB) as is
      OPC_LDH0: z = {16'd0, y[31:16]};                  // 上位ハーフワードを下位へ / upper halfword to the low bits
      OPC_LDH2: z = {16'd0, y[15:0]};                   // 下位ハーフワード / lower halfword

      // バイト/ハーフワード・ストア (メモリ語 y の一部を x で置き換える)
      // byte/halfword stores (replace part of the memory word y with x)
      OPC_STB0: z = {x[7:0],  y[23:0]};                 // メモリ語のバイト0をxの下位8bitで置換 (書き戻す語を作る) / replace byte 0 of the memory word with x[7:0] (builds the word to write back)
      OPC_STB1: z = {y[31:24], x[7:0], y[15:0]};        // バイト1を置換 / replace byte 1
      OPC_STB2: z = {y[31:16], x[7:0], y[7:0]};         // バイト2を置換 / replace byte 2
      OPC_STB3: z = {y[31:8],  x[7:0]};                 // バイト3を置換 / replace byte 3
      OPC_STH0: z = {x[15:0], y[15:0]};                 // 上位ハーフワードを置換 / replace the upper halfword
      OPC_STH2: z = {y[31:16], x[15:0]};                // 下位ハーフワードを置換 / replace the lower halfword

      default : ;                                       // 未使用のopcode (15,21,23,29,31): 既定値のまま (合成ではdon't careにならず0) / unused opcodes: defaults stay (0, not don't-care)
    endcase                                             // caseの終わり / end of case
  end                                                   // always の終わり / end of always
endmodule                                               // モジュールの終わり / end of module
