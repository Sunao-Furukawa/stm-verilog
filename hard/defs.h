
#ifndef VHDL

/* Extract N bits out of I, 
   starting at the S-th bit from the left (MSB is 0-th) */
#define bit_ext(i,s,n) ( (i >> (32 - s - n)) & ((1 << n) - 1) )

/* sign-extend rightmost N bits of X to 32 bits */
#define sign_ext(n,x) (   x | ( (x >> (n-1)) ? ~0 << n : 0 )   )

/* sign-extend rightmost 12 bits of X to 16 bits */
#define sign_ext_12(x) (sign_ext(12,x) & 0xffff)

/* sign-extend rightmost 16/6 bits of X to 32 bits */
#define sign_ext_16(x) sign_ext(16,x)
#define sign_ext_6(x) sign_ext(6,x)

/* Function to zero-extend D by 5/26 bits. 
   Used in converting INTCODE to TYPE / JB-INSN-AD for addition.*/
#define zero_ext_5(d)  d 

/* cc matches condition-mask */
#define cc_match(cc,mask) ((((8 >> cc) & mask) == 0) ? 0 : 1)

/* means that insn with this EX_opcode will write GR */
#define we_on(opc)  (((opc == OPC_C)||(opc == OPC_CU)||(opc == 0)) ? 0 : 1)


/* Format of PSW :
         0  2  4   7 8        16
	+--+--+---+-+--------+----------------+
        |  |cc|   |u| inttype|                |  u: user
	+--+--+---+-+--------+----------------+
*/

/* Function to build PSW from CC, USER and INTTYPE */
#define build_psw(cc,user,type) (( cc << 28) | ( user << 24) | ( type << 16))

/* Function to pick up  CC, USER and INTTYPE from PSW */
#define pickup_cc(psw)   bit_ext(psw,2,2)
#define pickup_user(psw) bit_ext(psw,7,1)
#define pickup_type(psw) bit_ext(psw,8,8)

/* Function to add 3 bits and 2 bits.  Used in computing NIP) */
#define add_3_2(x,y)	 (x + y)

/* Function to add 32 bits and 16 bits , the latter sign-extended. */
/* Used in EAG.							   */
#define add_32_16(x,y)	 (x + sign_ext(16,y))

/* Function to add 32 bits and 4 bits.  Used in PC-increment of W-cycle    */
/* and in IF-REQ-AD.							   */
#define add_32_4(x,y)	 (x + y)

/* Function to add 4, 5 and 3 bits with coefficients.  Used in JB-INSN-AD.   */
#define add_4_5_3(x,y,z) ((-1)*(x ? 16 : 8) + 4 * y + (z ? 0 : 4))

/* Function to add 32, 5 and 20 bits with coefficients.  Used in DD-TGT.   */
#define add_32_5_20(x,y,z) (x + y + sign_ext(20,z))

/* Function to add '4' and 5 bits.  Used in JB-INSN-AD for EX-OP2-DT.   */
#define add4_5(x) (x + 4)

#endif

