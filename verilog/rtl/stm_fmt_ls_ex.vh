// =====================================================================
//  stm_fmt_ls_ex.vh  <-  hard/fmt-ls-ex.h
//  LS (ロード/ストア) 形式・EX (演算) 形式のフィールド抽出関数と
//  命令の合法性チェック is_legal_opc
//  Field extraction functions for the LS (load/store) and EX (arithmetic) formats,
//  and the instruction legality check is_legal_opc
//
// 【ネットリスト解説】フィールド抽出の function は stm_fmt_jb.vh と同じく配線だけ。
//   回路 (LUT) になるのは is_legal_opc だけで、入力は命令語の上位 8bit と
//   PSW_USER の 9 本、出力 1 本の組合せ回路 (LUT 2〜3 個程度)。
//   I0 用と I1 用に 015_d_i01.vh で 2 回呼ばれるので 2 組できる。
//
// [Netlist notes] As in stm_fmt_jb.vh, the field functions are wiring only.
//   Only is_legal_opc becomes logic (LUTs): a combinational circuit with 9 inputs (the top
//   8 bits of the instruction word and PSW_USER) and 1 output (about 2-3 LUTs).
//   It is called twice in 015_d_i01.vh, for I0 and I1, so there are 2 copies.
// =====================================================================
/*LS :
# +--------+----+----+-----------------+
# | OPCODE |RD/S| RB |    DISP16       |
# +--------+----+----+-----------------+

#    OPCODE =  1   0   0   L/ST   0   0    HFW BYT
#  No signed byte/halfword load ... they are usually char's
*/
// 【解説】LENG = 0 は語, それ以外はサブワード (bit1 (=2) が立てばハーフワード,
//         そうでなければバイト)。150_d_act.vh で E サイクルの opcode に変換される。
// [Note] LENG = 0 is a word, anything else a sub-word (halfword if bit1 (=2) is set,
//        otherwise byte). 150_d_act.vh turns it into the E-cycle opcode.
function [2:0]  ls_opc_h  (input [31:0] i); ls_opc_h   = i[31:29]; endfunction // bit_ext(i,0,3)  -- i[31:29] の配線だけ (ゲート0): LS形式の判定用 (100ならLS) / wires only (no gate): for the LS-format check (100 = LS)
function        ls_store  (input [31:0] i); ls_store   = i[28];    endfunction // bit_ext(i,3,1)  -- i[28] の配線だけ (ゲート0): ストアか / wires only (no gate): store?
function [3:0]  ls_leng   (input [31:0] i); ls_leng    = i[27:24]; endfunction // bit_ext(i,4,4)  -- i[27:24] の配線だけ (ゲート0): アクセス長 (0=語) / wires only (no gate): access length (0 = word)
function [3:0]  ls_rd_rs  (input [31:0] i); ls_rd_rs   = i[23:20]; endfunction // bit_ext(i,8,4)  -- i[23:20] の配線だけ (ゲート0): ロード先/ストア元GR / wires only (no gate): load dest
function [3:0]  ls_rb     (input [31:0] i); ls_rb      = i[19:16]; endfunction // bit_ext(i,12,4)  -- i[19:16] の配線だけ (ゲート0): ベースGR / wires only (no gate): base GR
function [15:0] ls_disp16 (input [31:0] i); ls_disp16  = i[15:0];  endfunction // bit_ext(i,16,16)  -- i[15:0] の配線だけ (ゲート0): 16bit変位 / wires only (no gate): 16-bit displacement

/*EX :
#  Two concurrent executions are not allowed
#	-> no byte/halfword operations.
#  Immediate is always sign-extended
#
#    8        4    4    4      12
# +--------+----+----+-----------------+
# | OPC    | RD | R1 |     IMM16       |		R1 op I  -> RD
# +--------+----+----+----+------------+
# | OPC    | RD | R1 | R2 |   ----     | 		R1 op R2 -> RD
# +--------+----+----+----+------------+
# | OPC    | RD | RB | RS |  DISP12    |		RS op M  -> RD
# +--------+----+----+----+------------+
#
# bit<0>   = 0
# bit<1:2> = operand 2 mode (3=imm/1=reg/2=mem)
# bit<3>   = setting cc
# bit<4:7> = opcode
#   1  2  3      5  6  7  8  9  A  B   C   D    E
#   A  S  C      AU SU CU N  O  X  SL SRA SRL  SETHI
*/
// 【解説】EX 形式では RD / R1(RB) / R2(RS) が LS 形式の RD/RS / RB と同じ位置にある。
//         そのため 030_d_sec.vh のレジスタ読み出し番号 (DD_RADB/RAD1/RAD2) は、
//         形式を問わず同じビット ([19:16], [15:12]) から取れる。
// [Note] In the EX format RD / R1(RB) / R2(RS) are at the same places as RD/RS / RB of the LS format.
//        So the register read numbers of 030_d_sec.vh (DD_RADB/RAD1/RAD2) can be taken from
//        the same bits ([19:16], [15:12]) whatever the format.
function        ex_opc_h   (input [31:0] i); ex_opc_h    = i[31];    endfunction // bit_ext(i,0,1)  -- i[31] の配線だけ (ゲート0): 0ならEX形式の候補 / wires only (no gate): 0 = EX-format candidate
function [1:0]  ex_op2mode (input [31:0] i); ex_op2mode  = i[30:29]; endfunction // bit_ext(i,1,2)  -- i[30:29] の配線だけ (ゲート0): 第2オペランドの種類 / wires only (no gate): operand-2 mode
function        ex_setcc   (input [31:0] i); ex_setcc    = i[28];    endfunction // bit_ext(i,3,1)  -- i[28] の配線だけ (ゲート0): CCを更新するか / wires only (no gate): set CC?
function [3:0]  ex_exu_opc (input [31:0] i); ex_exu_opc  = i[27:24]; endfunction // bit_ext(i,4,4)  -- i[27:24] の配線だけ (ゲート0): 演算の種類 / wires only (no gate): operation
function [3:0]  ex_rd      (input [31:0] i); ex_rd       = i[23:20]; endfunction // bit_ext(i,8,4)  -- i[23:20] の配線だけ (ゲート0): 書き込み先GR / wires only (no gate): destination GR
function [3:0]  ex_rb1     (input [31:0] i); ex_rb1      = i[19:16]; endfunction // bit_ext(i,12,4)  -- i[19:16] の配線だけ (ゲート0): 第1オペランド/ベースGR / wires only (no gate): operand-1
function [3:0]  ex_rs2     (input [31:0] i); ex_rs2      = i[15:12]; endfunction // bit_ext(i,16,4)  -- i[15:12] の配線だけ (ゲート0): 第2オペランドGR / wires only (no gate): operand-2 GR
function [11:0] ex_disp12  (input [31:0] i); ex_disp12   = i[11:0];  endfunction // bit_ext(i,20,12)  -- i[11:0] の配線だけ (ゲート0): メモリオペランドの12bit変位 / wires only (no gate): 12-bit mem-operand displacement

function [15:0] ex_imm16   (input [31:0] i); ex_imm16    = i[15:0];  endfunction // bit_ext(i,16,16)  -- i[15:0] の配線だけ (ゲート0): 16bit即値 / wires only (no gate): 16-bit immediate

function [3:0]  insn_opc   (input [31:0] i); insn_opc    = i[31:28]; endfunction // bit_ext(i,0,4)  -- i[31:28] の配線だけ (ゲート0): 上位4bit (JB=1011, 特権=1100) / wires only (no gate): top 4 bits (JB 1011, priv 1100)

// 命令が合法かどうか (C シミュレータ版 is_legal_opc をそのまま移植)
//   i0 = 先頭 4bit, i1 = 次の 4bit
//      LS   : i0 = 8..9  かつ i1 = 0..3
//      EX   : i0 = 2..7  かつ i1 = 1..14
//      JB   : i0 = 11
//      PRIV : i0 = 12    かつ i1 = 1..3 かつ ユーザーモードでない
//   注) 元の #ifdef VHDL 版の論理式は user を見ない・範囲も少し異なる
//       簡略版だったため、動作確認に使われていた C 版に合わせている。
// Is the instruction legal (a straight port of is_legal_opc of the C simulator)
//   i0 = top 4 bits, i1 = next 4 bits
//      LS   : i0 = 8..9  and i1 = 0..3
//      EX   : i0 = 2..7  and i1 = 1..14
//      JB   : i0 = 11
//      PRIV : i0 = 12    and i1 = 1..3 and not in user mode
//   Note) the logic of the original #ifdef VHDL version ignores user and its ranges differ
//         slightly; it was a simplified version, so this follows the C version used for testing.
function is_legal_opc(input [31:0] i, input user);      // 命令語の上位8bitとユーザーモードから正当性を判定 / legality from the top 8 bits and user mode
  reg [3:0] i0, i1;                                     // 関数内の作業変数: 合成では単なるネット名 (FFにならない) / work variables: just net names in synthesis (no FFs)
  begin                                                 // 関数本体 / function body
    i0 = i[31:28];                                      // 上位4bit (配線) / top 4 bits (wires)
    i1 = i[27:24];                                      // 次の4bit (配線) / next 4 bits (wires)
    is_legal_opc =                                      // 下の4条件のOR: 9入力の真理値表 → LUT6 2~3個 / OR of the 4 terms below: a 9-input truth table -> 2-3 LUT6s
         (i0 >=  8 && i0 <=  9 && i1 <= 3)              // LS  -- i0=8,9 & i1<=3: ロード/ストア / loads and stores
      || (i0 >=  2 && i0 <=  7 && i1 >= 1 && i1 <= 14)  // EX  -- i0=2..7 & i1=1..14: 演算 / arithmetic
      || (i0 == 11)                                     // JB  -- i0=1011: 分岐 / branches
      || (i0 == 12 && i1 >= 1 && i1 <= 3 && !user);     // PRIV  -- i0=1100 & i1=1..3 & 特権モード: RFE/RSR/WSR / i0=1100, i1=1..3, supervisor: RFE/RSR/WSR
  end                                                   // 関数本体の終わり / end of body
endfunction                                             // 関数の終わり / end of function
