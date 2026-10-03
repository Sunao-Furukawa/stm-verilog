// =====================================================================
//  stm_defs.vh  <-  hard/defs.h + hard/vdefs.h
//  共通マクロを Verilog-2001 の function に置き換えたもの。
//  モジュール本体の中で `include して使う。
//
//  ビット番号の注意:
//    CHDL/VHDL 版は「MSB が 0 番」(big-endian 番号付け) だが、
//    この Verilog 版はすべて一般的な [N-1:0] (LSB が 0 番) で書いている。
//    defs.h の bit_ext(i,s,n) (左から s ビット目から n ビット) は
//    Verilog では  i[31-s -: n]  に相当する。
// =====================================================================

// ---------------------------------------------------------------------
// sign-extend rightmost 12 bits of X to 16 bits
function [15:0] sign_ext_12(input [11:0] x);
  sign_ext_12 = {{4{x[11]}}, x};
endfunction

// sign-extend rightmost 16/6 bits of X to 32 bits
function [31:0] sign_ext_16(input [15:0] x);
  sign_ext_16 = {{16{x[15]}}, x};
endfunction

function [31:0] sign_ext_6(input [5:0] x);
  sign_ext_6 = {{26{x[5]}}, x};
endfunction

// Function to zero-extend D by 5 bits. (INTCODE(3bit) -> PSW TYPE(8bit))
function [7:0] zero_ext_5(input [2:0] d);
  zero_ext_5 = {5'b00000, d};
endfunction

// ---------------------------------------------------------------------
// cc matches condition-mask
//   C 版: ((8 >> cc) & mask) != 0
//   MASK の最上位ビット(8)が cc=0, 最下位ビット(1)が cc=3 に対応する。
function cc_match(input [1:0] cc, input [3:0] mask);
  cc_match = mask[3 - cc];
endfunction

// means that insn with this EX_opcode will write GR
//   C / CU (比較) と 0 (LDW 扱い) は GR に書かない。
function we_on(input [3:0] opc);
  we_on = !((opc == OPC_C) || (opc == OPC_CU) || (opc == 4'd0));
endfunction

// ---------------------------------------------------------------------
// Format of PSW :
//         0  2  4   7 8        16            (CHDL のビット番号: MSB=0)
//	+--+--+---+-+--------+----------------+
//      |  |cc|   |u| inttype|                |  u: user
//	+--+--+---+-+--------+----------------+
//   Verilog の番号では cc=[29:28], user=[24], inttype=[23:16]

// Function to build PSW from CC, USER and INTTYPE
function [31:0] build_psw(input [1:0] cc, input user, input [7:0] type_);
  build_psw = {2'b00, cc, 3'b000, user, type_, 16'h0000};
endfunction

// Function to pick up  CC, USER and INTTYPE from PSW
function [1:0] pickup_cc(input [31:0] psw);
  pickup_cc = psw[29:28];
endfunction
function pickup_user(input [31:0] psw);
  pickup_user = psw[24];
endfunction
function [7:0] pickup_type(input [31:0] psw);
  pickup_type = psw[23:16];
endfunction

// ---------------------------------------------------------------------
// 加算器類 (C 版では単なる '+', VHDL 版では個別の加算器エンティティ)

// Function to add 3 bits and 2 bits.  Used in computing NIP)
function [2:0] add_3_2(input [2:0] x, input [1:0] y);
  add_3_2 = x + y;
endfunction

// Function to add 32 bits and 16 bits , the latter sign-extended.
// Used in EAG.
function [31:0] add_32_16(input [31:0] x, input [15:0] y);
  add_32_16 = x + sign_ext_16(y);
endfunction

// Function to add 32 bits and 4 bits.  Used in PC-increment of W-cycle
// and in IF-REQ-AD.  (y は 0/4/8 なので 5 bit)
function [31:0] add_32_4(input [31:0] x, input [4:0] y);
  add_32_4 = x + {27'd0, y};
endfunction

// Function to add 4, 5 and 3 bits with coefficients.  Used in JB-INSN-AD.
//   C 版: (-1)*(x ? 16 : 8) + 4 * y + (z ? 0 : 4)
//   結果は -16 .. +24 の範囲なので 6 bit の 2 の補数で表す。
function [5:0] add_4_5_3(input x, input [2:0] y, input z);
  add_4_5_3 = (x ? 6'd48 : 6'd56)          // -16 / -8 (6bit 2の補数)
            + {1'b0, y, 2'b00}              // 4 * y
            + (z ? 6'd0 : 6'd4);
endfunction

// Function to add 32, 5 and 20 bits with coefficients.  Used in DD-TGT.
//   x + (6bit 符号付き y) + sign_ext(20, z)
function [31:0] add_32_5_20(input [31:0] x, input [5:0] y, input [19:0] z);
  add_32_5_20 = x + {{26{y[5]}}, y} + {{12{z[19]}}, z};
endfunction

// Function to add '4' and 5 bits.  Used in JB-INSN-AD for EX-OP2-DT.
function [5:0] add4_5(input [5:0] x);
  add4_5 = x + 6'd4;
endfunction
