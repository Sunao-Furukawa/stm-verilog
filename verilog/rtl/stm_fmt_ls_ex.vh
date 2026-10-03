// =====================================================================
//  stm_fmt_ls_ex.vh  <-  hard/fmt-ls-ex.h
//  LS (ロード/ストア) 形式・EX (演算) 形式のフィールド抽出関数と
//  命令の合法性チェック is_legal_opc
// =====================================================================
/*LS :
# +--------+----+----+-----------------+
# | OPCODE |RD/S| RB |    DISP16       |
# +--------+----+----+-----------------+

#    OPCODE =  1   0   0   L/ST   0   0    HFW BYT
#  No signed byte/halfword load ... they are usually char's
*/
function [2:0]  ls_opc_h  (input [31:0] i); ls_opc_h   = i[31:29]; endfunction // bit_ext(i,0,3)
function        ls_store  (input [31:0] i); ls_store   = i[28];    endfunction // bit_ext(i,3,1)
function [3:0]  ls_leng   (input [31:0] i); ls_leng    = i[27:24]; endfunction // bit_ext(i,4,4)
function [3:0]  ls_rd_rs  (input [31:0] i); ls_rd_rs   = i[23:20]; endfunction // bit_ext(i,8,4)
function [3:0]  ls_rb     (input [31:0] i); ls_rb      = i[19:16]; endfunction // bit_ext(i,12,4)
function [15:0] ls_disp16 (input [31:0] i); ls_disp16  = i[15:0];  endfunction // bit_ext(i,16,16)

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
function        ex_opc_h   (input [31:0] i); ex_opc_h    = i[31];    endfunction // bit_ext(i,0,1)
function [1:0]  ex_op2mode (input [31:0] i); ex_op2mode  = i[30:29]; endfunction // bit_ext(i,1,2)
function        ex_setcc   (input [31:0] i); ex_setcc    = i[28];    endfunction // bit_ext(i,3,1)
function [3:0]  ex_exu_opc (input [31:0] i); ex_exu_opc  = i[27:24]; endfunction // bit_ext(i,4,4)
function [3:0]  ex_rd      (input [31:0] i); ex_rd       = i[23:20]; endfunction // bit_ext(i,8,4)
function [3:0]  ex_rb1     (input [31:0] i); ex_rb1      = i[19:16]; endfunction // bit_ext(i,12,4)
function [3:0]  ex_rs2     (input [31:0] i); ex_rs2      = i[15:12]; endfunction // bit_ext(i,16,4)
function [11:0] ex_disp12  (input [31:0] i); ex_disp12   = i[11:0];  endfunction // bit_ext(i,20,12)

function [15:0] ex_imm16   (input [31:0] i); ex_imm16    = i[15:0];  endfunction // bit_ext(i,16,16)

function [3:0]  insn_opc   (input [31:0] i); insn_opc    = i[31:28]; endfunction // bit_ext(i,0,4)

// 命令が合法かどうか (C シミュレータ版 is_legal_opc をそのまま移植)
//   i0 = 先頭 4bit, i1 = 次の 4bit
//      LS   : i0 = 8..9  かつ i1 = 0..3
//      EX   : i0 = 2..7  かつ i1 = 1..14
//      JB   : i0 = 11
//      PRIV : i0 = 12    かつ i1 = 1..3 かつ ユーザーモードでない
//   注) 元の #ifdef VHDL 版の論理式は user を見ない・範囲も少し異なる
//       簡略版だったため、動作確認に使われていた C 版に合わせている。
function is_legal_opc(input [31:0] i, input user);
  reg [3:0] i0, i1;
  begin
    i0 = i[31:28];
    i1 = i[27:24];
    is_legal_opc =
         (i0 >=  8 && i0 <=  9 && i1 <= 3)              // LS
      || (i0 >=  2 && i0 <=  7 && i1 >= 1 && i1 <= 14)  // EX
      || (i0 == 11)                                     // JB
      || (i0 == 12 && i1 >= 1 && i1 <= 3 && !user);     // PRIV
  end
endfunction
