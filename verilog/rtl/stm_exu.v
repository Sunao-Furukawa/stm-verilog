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
module stm_exu (
  input      [4:0]  opc,
  input      [31:0] x,
  input      [31:0] y,
  output reg [1:0]  cc,
  output reg [31:0] z,
  output reg [2:0]  intr
);
`include "stm_const.vh"

  // 加減算: 下位 31bit と最上位ビットを分けて, bit31 へのキャリー(cry1)と
  //         bit31 からのキャリー(cry0)を求める (exu.h と同じ構成)
  // Add/subtract: the low 31 bits and the top bit are handled separately to get the carry
  //               into bit31 (cry1) and the carry out of bit31 (cry0) (same structure as exu.h)
  wire        is_sub = (opc == OPC_S) || (opc == OPC_SU) ||
                       (opc == OPC_C) || (opc == OPC_CU);
  wire [31:0] yy     = is_sub ? ~y : y;
  wire        cin    = is_sub;
  wire [31:0] low    = {1'b0, x[30:0]} + {1'b0, yy[30:0]} + cin; // never overflows
  wire        cry1   = low[31];                                  // carry-in to bit<0>
  wire        sx     = x[31];
  wire        sy     = yy[31];
  wire        cry0   = (sx & sy) | (sy & cry1) | (cry1 & sx);     // carry-out of bit<0>
  wire [31:0] sum    = {low[31] ^ sx ^ sy, low[30:0]};
  wire        sz     = sum[31];
  wire        ovf    = cry0 ^ cry1;

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
  wire [5:0]  amt    = y[5:0];

  always @* begin
    z    = 32'd0;
    cc   = 2'd0;
    intr = 3'd0;
    case (opc)
      OPC_LDW : begin z = y; cc = 2'd0; end
      OPC_STW : begin z = x; cc = 2'd0; end

      OPC_A, OPC_S, OPC_C : begin
        z = sum;
        if (ovf && (opc != OPC_C)) begin cc = 2'd3; intr = INTCODE_OVF; end
        else if (sum == 32'd0)                   cc = 2'd0;
        else if ((!sz && !ovf) || (sz && ovf))   cc = 2'd2;
        else                                     cc = 2'd1;
      end
      OPC_AU, OPC_SU, OPC_CU : begin
        z = sum;
        if ((sum == 32'd0) && cry0) cc = 2'd0;
        else if (!cry0)             cc = 2'd1;
        else                        cc = 2'd2;
      end

      OPC_N   : begin z = x & y; cc = (z == 0) ? 2'd0 : 2'd1; end
      OPC_O   : begin z = x | y; cc = (z == 0) ? 2'd0 : 2'd1; end
      OPC_X   : begin z = x ^ y; cc = (z == 0) ? 2'd0 : 2'd1; end

      OPC_SL  : begin z = x << amt;                    cc = (z == 0) ? 2'd0 : 2'd1; end
      OPC_SRA : begin z = $signed(x) >>> amt;          cc = (z == 0) ? 2'd0 : 2'd1; end
      OPC_SRL : begin z = x >> amt;                    cc = (z == 0) ? 2'd0 : 2'd1; end
      OPC_SETHI:begin z = {y[15:0], 16'h0000};         cc = (z == 0) ? 2'd0 : 2'd1; end

      // バイト/ハーフワード・ロード (ビッグエンディアン: バイト0 が最上位)
      // byte/halfword loads (big-endian: byte 0 is the most significant)
      OPC_LDB0: z = {24'd0, y[31:24]};
      OPC_LDB1: z = {24'd0, y[23:16]};
      OPC_LDB2: z = {24'd0, y[15:8]};
      OPC_LDB3: z = {24'd0, y[7:0]};
      OPC_LDH0: z = {16'd0, y[31:16]};
      OPC_LDH2: z = {16'd0, y[15:0]};

      // バイト/ハーフワード・ストア (メモリ語 y の一部を x で置き換える)
      // byte/halfword stores (replace part of the memory word y with x)
      OPC_STB0: z = {x[7:0],  y[23:0]};
      OPC_STB1: z = {y[31:24], x[7:0], y[15:0]};
      OPC_STB2: z = {y[31:16], x[7:0], y[7:0]};
      OPC_STB3: z = {y[31:8],  x[7:0]};
      OPC_STH0: z = {x[15:0], y[15:0]};
      OPC_STH2: z = {y[31:16], x[15:0]};

      default : ;
    endcase
  end
endmodule
