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
//
//  Macros shared by the source, replaced by Verilog-2001 functions.
//  `include this inside a module body.
//
//  Note on bit numbers:
//    The CHDL/VHDL versions use "MSB is bit 0" (big-endian numbering), but
//    this Verilog version always uses the usual [N-1:0] (LSB is bit 0).
//    bit_ext(i,s,n) of defs.h (n bits starting at bit s from the left) is
//    i[31-s -: n] in Verilog.
//
// 【ネットリスト解説】function は「呼んだ場所にその式を展開する」だけで、
//   それ自身は回路の部品 (インスタンス) にならない。合成結果の中に
//   sign_ext_16 という名前のセルは無く、呼び出し側のネットの一部になる
//   (Vivado では add_32_5_20_return のように「関数名_return」というネット名で
//   残ることがある)。中身で分けると:
//     ・sign_ext_* / zero_ext_5 / build_psw / pickup_*  : 配線だけ (LUT 0 個)。
//         符号拡張は最上位ビットのネットを複数のビットへ分岐させるだけ。
//     ・cc_match                                       : 4:1 マルチプレクサ 1 個 (LUT 1 個)。
//     ・we_on                                          : 4bit 入力の比較 (LUT 1 個)。
//     ・add_*                                          : 加算器。FPGA では CARRY4 の連鎖
//         (4bit ごと) + 各ビットの LUT になる。add_3_2 / add4_5 のように短いものは
//         LUT だけで済むこともある。
//
// [Netlist notes] A function only expands its expression where it is called; it does not
//   become a part (instance) of the circuit by itself. There is no cell called sign_ext_16 in
//   the synthesis result; it becomes part of the caller's nets (Vivado sometimes keeps a net
//   name like add_32_5_20_return, "function name_return"). By content:
//     - sign_ext_* / zero_ext_5 / build_psw / pickup_*  : wiring only (0 LUTs).
//         Sign extension just fans the top bit's net out to several bits.
//     - cc_match                                       : one 4:1 multiplexer (1 LUT).
//     - we_on                                          : a compare of a 4-bit input (1 LUT).
//     - add_*                                          : adders. On an FPGA they become chained
//         CARRY4s (4 bits each) plus a LUT per bit. Short ones such as add_3_2 / add4_5
//         may be done with LUTs only.
// =====================================================================

// ---------------------------------------------------------------------
// sign-extend rightmost 12 bits of X to 16 bits
function [15:0] sign_ext_12(input [11:0] x);            // 12bit→16bitの符号拡張 (EX-RMの変位用) / 12 -> 16-bit sign extension (for the EX-RM displacement)
  sign_ext_12 = {{4{x[11]}}, x};                        // 上位4bitはx[11]の配線を4本に分岐するだけ (ゲート0) / top 4 bits are just x[11] wired 4 times (no gate)
endfunction                                             // 関数の終わり / end of function

// sign-extend rightmost 16/6 bits of X to 32 bits
function [31:0] sign_ext_16(input [15:0] x);            // 16bit→32bitの符号拡張 (変位/即値用) / 16 -> 32-bit sign extension (displacement / immediate)
  sign_ext_16 = {{16{x[15]}}, x};                       // x[15]を16本に複製する配線 (ファンアウト16) / x[15] fanned out to 16 wires
endfunction                                             // 関数の終わり / end of function

function [31:0] sign_ext_6(input [5:0] x);              // 6bit→32bitの符号拡張 (リンク番地の下位部分) / 6 -> 32-bit sign extension (low part of the link address)
  sign_ext_6 = {{26{x[5]}}, x};                         // x[5]を26本に複製する配線 / x[5] fanned out to 26 wires
endfunction                                             // 関数の終わり / end of function

// Function to zero-extend D by 5 bits. (INTCODE(3bit) -> PSW TYPE(8bit))
function [7:0] zero_ext_5(input [2:0] d);               // 3bit→8bitの0拡張 (名前はCHDLのまま) / 3 -> 8-bit zero extension (name kept from CHDL)
  zero_ext_5 = {5'b00000, d};                           // 上位5bitはGND (定数0)につながる / top 5 bits are tied to GND
endfunction                                             // 関数の終わり / end of function

// ---------------------------------------------------------------------
// cc matches condition-mask
//   C 版: ((8 >> cc) & mask) != 0
//   MASK の最上位ビット(8)が cc=0, 最下位ビット(1)が cc=3 に対応する。
//   (C version: ((8 >> cc) & mask) != 0
//    The top bit of MASK (8) is cc=0, the bottom bit (1) is cc=3.)
//   【解説】回路としては「cc を選択信号, mask の 4 本をデータとする 4:1 MUX」。
//         例: BNE (mask=6=0110) は cc=1 (負) と cc=2 (正) で成立する。
//   [Note] As a circuit this is "a 4:1 MUX with cc as the select and the 4 bits of mask as data".
//          e.g. BNE (mask=6=0110) holds for cc=1 (negative) and cc=2 (positive).
function cc_match(input [1:0] cc, input [3:0] mask);    // 分岐条件の判定: CCがmaskの成立条件に入るか / branch condition: is CC in the mask
  cc_match = mask[3 - cc];                              // ccで4本から1本を選ぶ4:1 MUX (LUT6 1個: 入力6本) / 4:1 mux picking 1 of 4 by cc (one LUT6: 6 inputs)
endfunction                                             // 関数の終わり / end of function

// means that insn with this EX_opcode will write GR
//   C / CU (比較) と 0 (LDW 扱い) は GR に書かない。
//   (C / CU (compares) and 0 (treated as LDW) do not write GR.)
function we_on(input [3:0] opc);                        // そのEX opcodeがGRに書くか / does this EX opcode write a GR
  we_on = !((opc == OPC_C) || (opc == OPC_CU) || (opc == 4'd0)); // 4bit入力の真理値表 (0,3,7で0) → LUT4 1個 / truth table of 4 inputs (0 for 0,3,7) -> one LUT4
endfunction                                             // 関数の終わり / end of function

// ---------------------------------------------------------------------
// Format of PSW :
//         0  2  4   7 8        16            (CHDL のビット番号: MSB=0)
//	+--+--+---+-+--------+----------------+
//      |  |cc|   |u| inttype|                |  u: user
//	+--+--+---+-+--------+----------------+
//   Verilog の番号では cc=[29:28], user=[24], inttype=[23:16]
//   (bit numbers in the figure are CHDL ones: MSB=0)
//   In Verilog numbering cc=[29:28], user=[24], inttype=[23:16]

// Function to build PSW from CC, USER and INTTYPE
//   【解説】PSW は 1 本の 32bit レジスタとしては存在しない。実体は stm_cntl の
//         PSW_CC (2bit), PSW_USER (1bit), PSW_TYPE (8bit) の 3 つの FF で、RSR で読む
//         ときや XPSW に退避するときだけ build_psw で 32bit に並べる (配線のみ)。
//         残りのビットは常に 0 (グランドにつながる)。
//
//   [Note] PSW does not exist as one 32-bit register. It really is the 3 FFs PSW_CC (2 bits),
//          PSW_USER (1 bit) and PSW_TYPE (8 bits) of stm_cntl, lined up into 32 bits by
//          build_psw (wiring only) only when RSR reads it or it is saved to XPSW.
//          The other bits are always 0 (tied to ground).
function [31:0] build_psw(input [1:0] cc, input user, input [7:0] type_); // PSWの3つのFFから32bitの語を組み立てる / build the 32-bit PSW word from its 3 FF groups
  build_psw = {2'b00, cc, 3'b000, user, type_, 16'h0000}; // cc=[29:28], user=[24], type=[23:16], 他は0: 全部配線とGND (LUT 0個) / cc=[29:28], user=[24], type=[23:16], rest 0: wires and GND only (no LUT)
endfunction                                             // 関数の終わり / end of function

// Function to pick up  CC, USER and INTTYPE from PSW
function [1:0] pickup_cc(input [31:0] psw);             // 32bitのPSW値からCCを取り出す / take CC out of a 32-bit PSW value
  pickup_cc = psw[29:28];                               // bit[29:28]の配線 / wires of bits [29:28]
endfunction                                             // 関数の終わり / end of function
function pickup_user(input [31:0] psw);                 // PSW値からユーザービットを取り出す / take the user bit out of a PSW value
  pickup_user = psw[24];                                // bit[24]の配線 / wire of bit 24
endfunction                                             // 関数の終わり / end of function
function [7:0] pickup_type(input [31:0] psw);           // PSW値から割り込み種別を取り出す / take the interrupt type out of a PSW value
  pickup_type = psw[23:16];                             // bit[23:16]の配線 / wires of bits [23:16]
endfunction                                             // 関数の終わり / end of function

// ---------------------------------------------------------------------
// 加算器類 (C 版では単なる '+', VHDL 版では個別の加算器エンティティ)
// Adders (just '+' in the C version, separate adder entities in the VHDL version)

// Function to add 3 bits and 2 bits.  Used in computing NIP)
function [2:0] add_3_2(input [2:0] x, input [1:0] y);   // NIP (3bit) + 発行数 (2bit): 190で使用 / NIP (3 bits) + issue count (2 bits): used in 190
  add_3_2 = x + y;                                      // 3bitの結果 (桁あふれは捨てる): 5入力なのでLUT3本, CARRY4は出ない / 3-bit result (carry dropped): 5 inputs, so 3 LUTs, no CARRY4
endfunction                                             // 関数の終わり / end of function

// Function to add 32 bits and 16 bits , the latter sign-extended.
// Used in EAG.
function [31:0] add_32_16(input [31:0] x, input [15:0] y); // EAG: ベース + 符号拡張16bit変位 / EAG: base + sign-extended 16-bit displacement
  add_32_16 = x + sign_ext_16(y);                       // 32bit加算器: LUT (XOR) 32個 + CARRY4 8個の桁上げ連鎖 / 32-bit adder: 32 LUTs (XOR) + a chain of 8 CARRY4s
endfunction                                             // 関数の終わり / end of function

// Function to add 32 bits and 4 bits.  Used in PC-increment of W-cycle
// and in IF-REQ-AD.  (y は 0/4/8 なので 5 bit)
//   (y is 0/4/8, so 5 bits)
function [31:0] add_32_4(input [31:0] x, input [4:0] y); // PC/フェッチ番地 + 0/4/8 / PC or fetch address + 0/4/8
  add_32_4 = x + {27'd0, y};                            // 下位2bitは素通し (yの下位2bitは常に0なので合成で消える), 残りが加算器 / low 2 bits pass (y's low bits are always 0), the rest is an adder
endfunction                                             // 関数の終わり / end of function

// Function to add 4, 5 and 3 bits with coefficients.  Used in JB-INSN-AD.
//   C 版: (-1)*(x ? 16 : 8) + 4 * y + (z ? 0 : 4)
//   結果は -16 .. +24 の範囲なので 6 bit の 2 の補数で表す。
//   C version: (-1)*(x ? 16 : 8) + 4 * y + (z ? 0 : 4)
//   The result is in -16 .. +24, so it is a 6-bit two's complement number.
//   【解説】入力は 1+3+1 = 5bit しか無いので、合成ツールはこれを加算器ではなく
//         5 入力の真理値表 (出力 6bit それぞれ LUT5 1 個) にしてしまえる。
//         例: x=1 (V45), y=4 (NIP), z=1 (1 命令目が分岐)  →  -16 + 16 + 0 = 0。
//         つまり「4,5 番が埋まっていて NIP=4 なら、分岐命令は最後に入れた
//         8 バイトの先頭 (D_IF_AD) にある」。
//
//   [Note] There are only 1+3+1 = 5 input bits, so synthesis can make this a 5-input truth table
//          (one LUT5 for each of the 6 output bits) instead of an adder.
//          e.g. x=1 (V45), y=4 (NIP), z=1 (first instruction is the branch)  ->  -16 + 16 + 0 = 0.
//          That is, "with entries 4,5 filled and NIP=4, the branch is at the start of the last
//          8 bytes put in (D_IF_AD)".
function [5:0] add_4_5_3(input x, input [2:0] y, input z); // 分岐命令の相対位置 (6bit 2の補数) / relative position of a branch insn (6-bit two's complement)
  add_4_5_3 = (x ? 6'd48 : 6'd56)          // -16 / -8 (6bit 2の補数)
                                           // -16 / -8 (6-bit two's complement)
            + {1'b0, y, 2'b00}              // 4 * y  -- NIPの4倍 = 2bit左シフト (配線だけ) / NIP times 4 = shift left by 2 (wires only)
            + (z ? 6'd0 : 6'd4);                        // +4 (分岐が2命令目なら)… 全体で5入力→6出力の真理値表 (LUT5 x6) / +4 (branch is the second insn)... a 5-in/6-out truth table overall (6 LUT5s)
endfunction                                             // 関数の終わり / end of function

// Function to add 32, 5 and 20 bits with coefficients.  Used in DD-TGT.
//   x + (6bit 符号付き y) + sign_ext(20, z)
//   x + (6-bit signed y) + sign_ext(20, z)
//   【解説】3 入力の加算 (x + y + z)。合成ではキャリー連鎖 (CARRY4) を使った加算器に
//         なる (Vivado の合成結果では A_TGT_reg[..]_i_1 という名前の CARRY4 が並び、
//         その出力ネットが add_32_5_20_return[..])。
//         D サイクルの中で IWQ → NIP → PART2 → この加算 → A_TGT の FF と続くので、
//         長い経路の 1 つ。
//
//   [Note] A 3-input add (x + y + z). Synthesis makes an adder with carry chains (CARRY4)
//          (in the Vivado result there is a row of CARRY4s named A_TGT_reg[..]_i_1, whose output
//          nets are add_32_5_20_return[..]).
//          Within the D cycle it goes IWQ -> NIP -> PART2 -> this add -> the A_TGT FFs,
//          so it is one of the long paths.
function [31:0] add_32_5_20(input [31:0] x, input [5:0] y, input [19:0] z); // DD_TGT: 32bit + 6bit符号付き + 20bit符号付き / DD_TGT: 32-bit + signed 6-bit + signed 20-bit
  add_32_5_20 = x + {{26{y[5]}}, y} + {{12{z[19]}}, z}; // 3入力の32bit加算: 合成ではLUTで3:2圧縮(またはx+y)してからCARRY4連鎖1本 / 3-input 32-bit add: LUT 3:2 compression (or x+y first) then one CARRY4 chain
endfunction                                             // 関数の終わり / end of function

// Function to add '4' and 5 bits.  Used in JB-INSN-AD for EX-OP2-DT.
function [5:0] add4_5(input [5:0] x);                   // 6bit + 4 (リンク番地の下位部分) / 6-bit + 4 (low part of the link address)
  add4_5 = x + 6'd4;                                    // 下位2bitは素通し, 上位4bitの+1 → LUT4本 / low 2 bits pass, +1 on the top 4 bits -> 4 LUTs
endfunction                                             // 関数の終わり / end of function
