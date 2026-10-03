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
// 【解説】条件コード CC (2bit) の意味
//   符号付き演算 A / S / C :  0 = 結果が 0,  1 = 負,  2 = 正,  3 = オーバーフロー
//                            (C は比較なのでオーバーフローでも割り込まない)
//   符号なし演算 AU/SU/CU  :  0 = 結果 0 かつキャリーあり,  1 = キャリーなし,
//                            2 = キャリーあり (結果は 0 以外)
//   論理演算・シフト      :  0 = 結果が 0,  1 = 0 以外
//   条件分岐のマスクは 4bit で, 最上位から cc=0,1,2,3 に対応する
//   (アセンブラでは BE=8, BL=4, BG=2, BNE=6, BLE=12, BGE=10)。
//   A / S でオーバーフローすると INTCODE_OVF (4) の割り込みを出す。
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
      OPC_LDB0: z = {24'd0, y[31:24]};
      OPC_LDB1: z = {24'd0, y[23:16]};
      OPC_LDB2: z = {24'd0, y[15:8]};
      OPC_LDB3: z = {24'd0, y[7:0]};
      OPC_LDH0: z = {16'd0, y[31:16]};
      OPC_LDH2: z = {16'd0, y[15:0]};

      // バイト/ハーフワード・ストア (メモリ語 y の一部を x で置き換える)
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
