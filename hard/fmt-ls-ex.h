
/*LS :
# +--------+----+----+-----------------+
# | OPCODE |RD/S| RB |    DISP16       |
# +--------+----+----+-----------------+

#    OPCODE =  1   0   0   L/ST   0   0    HFW BYT 
#  No signed byte/halfword load ... they are usually char's 
*/
#define ls_opc_h(i) 	bit_ext(i,0,3)
#define ls_store(i) 	bit_ext(i,3,1)
#define ls_leng(i) 	bit_ext(i,4,4)
#define ls_rd_rs(i) 	bit_ext(i,8,4)
#define ls_rb(i) 	bit_ext(i,12,4)
#define ls_disp16(i) 	bit_ext(i,16,16)

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
#define ex_opc_h(i) 	bit_ext(i,0,1)
#define ex_op2mode(i) 	bit_ext(i,1,2)
#define ex_setcc(i) 	bit_ext(i,3,1)
#define ex_exu_opc(i) 	bit_ext(i,4,4)
#define ex_rd(i) 	bit_ext(i,8,4)
#define ex_rb1(i) 	bit_ext(i,12,4)
#define ex_rs2(i) 	bit_ext(i,16,4)
#define ex_disp12(i) 	bit_ext(i,20,12)

#define ex_imm16(i) 	bit_ext(i,16,16)

#define in_range(m,i,n)  ((m<=i)&&(i<=n)) 	/* m <= i <= n */

#ifndef VHDL
unsigned is_legal_opc(i,user) unsigned i,user ; { unsigned i0, i1 ;
  i0 = i >> 28 ; i1 = (i >> 24) & 15 ; 		/* first and second digits */
  return(    in_range( 8,i0, 9) && in_range( 0,i1, 3)  		/* LS   */
          || in_range( 2,i0, 7) && in_range( 1,i1,14)   	/* EX   */
          || in_range(11,i0,11) 				/* JB 	*/
          || in_range(12,i0,12) && in_range( 1,i1, 3) && !user ); /*PRIV*/
}
#else
#define is_legal_opc(i,user) ( i[0]&!i[1]&!i[2]    &!i[4]&!i[5]&!(i[6]&i[7]) \
  | !i[0] & !(!i[4]&!i[5]&!i[6]&!i[7]) & !(i[4]&i[5]&i[6]&i[7])	\
  |  i[0]&!i[1]&i[2]&i[3]  |  i[0]&i[1]&!i[2]&!i[3] & !i[4]&!i[5]&(i[6]|i[7]) )

#endif
/* #define is_legal_opc(i,user) ( (i[0:3]=B"100") | (i[0]=B"0")|(i[0:4]=B"1011") ) */

#define insn_opc(i) 	bit_ext(i,0,4)
