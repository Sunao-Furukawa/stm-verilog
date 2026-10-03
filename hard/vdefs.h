#ifdef VHDL
/* cc matches condition-mask */
#define cc_match(cc,mask) 	(!cc[0] & !cc[1] & mask[0]  | \
				 !cc[0] &  cc[1] & mask[1]  | \
				  cc[0] & !cc[1] & mask[2]  | \
				  cc[0] &  cc[1] & mask[3] )

/* means that insn with this EX_opcode will write GR */
#define we_on(opc)  ( ! ( !opc[0] & (	!opc[1] & !opc[2] & !opc[3] | \
					!opc[1] &  opc[2] &  opc[3] | \
					 opc[1] &  opc[2] & !opc[3]  )  ))
/* Extract N bits out of I, 
   starting at the S-th bit from the left (MSB is 0-th) */
#define bit_ext(i,s,n) i[s : n]

/* sign-extend rightmost 12 bits of X to 16 bits */
#define sign_ext_12(x) (x[0] . x[0] . x[0] . x[0] . x[0 : 12])

/* sign-extend rightmost 16/6 bits of X to 32 bits */
#define sign_ext_16(x) (x[0].x[0].x[0].x[0].x[0].x[0].x[0].x[0].\
			x[0].x[0].x[0].x[0].x[0].x[0].x[0].x[0].x[0 : 16])
#define sign_ext_6(x) (x[0].x[0].x[0].x[0].x[0].x[0].x[0].x[0].\
			x[0].x[0].x[0].x[0].x[0].x[0].x[0].x[0].x[0].x[0].\
			x[0].x[0].x[0].x[0].x[0].x[0].x[0].x[0].x[0 : 6])

/* Function to zero-extend D by 5 bits. Used in converting INTCODE to TYPE.*/
#define zero_ext_5(d)  ( B"00000" . d ) 

/* Function to pick up  CC, USER and INTTYPE from PSW */
#define pickup_cc(psw)   bit_ext(psw,2,2)
#define pickup_user(psw) bit_ext(psw,7,1)
#define pickup_type(psw) bit_ext(psw,8,8)

/* Function to build PSW from CC, USER and INTTYPE */
#define build_psw(cc,user,type)  \
	(B"00" . cc . B"000" . user .  type . X"0000")

/* Function to add 3 bits and 2 bits.  Used in computing NIP) */
#define add_3_2(x,y)	 ( x[0]^(x[1]&y[0]|(x[1]|y[0])&x[2]&y[1]) . \
			   x[1]^y[0]^(x[2]&y[1]) . x[2]^y[1] )
/* Function to add '4' and 5 bits.  Used in JB-INSN-AD for EX-OP2-DT.   */
#define add4_5(x) (x[0]^x[1]&x[2]&x[3] .x[1]^(x[2]&x[3]) .x[2]^x[3].!x[3].B"00")

/* Function to add 4, 5 and 3 bits with coefficients.  Used in JB-INSN-AD.   */
#define add_4_5_3(x,y,z) ( !((y[1]&!x|(y[1]|!x)&y[2]&!z)|y[0]) . \
			   !((y[1]&!x|(y[1]|!x)&y[2]&!z)^y[0]) . \
			   y[1]^!x^(y[2]&!z) . y[2]^!z . B"00" )

#else

/* Function to add 32 bits and 16 bits , the latter sign-extended. */
/* Used in EAG.							   */
#define add_32_16(x,y)	 (x + sign_ext(16,y))

/* Function to add 32 bits and 4 bits.  Used in PC-increment of W-cycle    */
/* and in IF-REQ-AD.							   */
#define add_32_4(x,y)	 (x + y)

/* Function to add 32, 5 and 20 bits with coefficients.  Used in DD-TGT.   */
#define add_32_5_20(x,y,z) (x + y + sign_ext(20,z))

#endif
