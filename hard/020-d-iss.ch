
# d-iss : deciding insn issue 


# Note: LS/EX of format and of pipe have different meaning; 
#	EX-RM is 'EX' in format but 'LS' in pipe!

DD-I0-LS-FMT	= (I0-LS-OPC-H == 4)	 	
DD-I0-EX-FMT	= (I0-EX-OPC-H == 0) & (I0-EX-OP2MODE != 0)
DD-I0-JB-FMT	= (I0-INSN-OPC == 11)         
DD-I1-LS-FMT	= (I1-LS-OPC-H == 4)	 	
DD-I1-EX-FMT	= (I1-EX-OPC-H == 0) & (I1-EX-OP2MODE != 0)
DD-I1-JB-FMT	= (I1-INSN-OPC == 11)         

# decide whether the first/second insn is LS, EX, JB, or privileged op.

DD-FIRST-IS-LS	= DD-I0-LS-FMT | DD-I0-EX-FMT & (I0-EX-OP2MODE == EXMOD-RM) 
DD-SECOND-IS-LS	= DD-I1-LS-FMT | DD-I1-EX-FMT & (I1-EX-OP2MODE == EXMOD-RM) 

DD-FIRST-IS-EX	= DD-I0-EX-FMT & (I0-EX-OP2MODE != EXMOD-RM) 
DD-SECOND-IS-EX	= DD-I1-EX-FMT & (I1-EX-OP2MODE != EXMOD-RM) 

DD-FIRST-IS-JB	= DD-I0-JB-FMT
DD-SECOND-IS-JB	= DD-I1-JB-FMT

DD-PRIVCODE 	= ((I0-INSN-OPC == 12) ? I0-PRIV-OPC : 0)
DD-SECOND-PRIV-V = (I1-INSN-OPC == 12)

# and if they use GR or set CC
#
#  sets   CC  <-->  EX & SETCC
#  writes RD  <-->  LD | EX & !(C/CU) | JB & LINK
#  reads  RB  <-->  LS | EX & RM      | JB & REG    
#  reads  R1  <-->  EX & (RR|RI)      | JB & cmp
#  reads  R2  <-->  EX &  RR          | JB & cmp
#  reading CC or RS is never an obstacle for  second insn issue

DD-FIRST-SETCC 	= DD-I0-EX-FMT & I0-EX-SETCC
DD-FIRST-WAD  	= I0-EX-RD
DD-FIRST-WAD-V	= DD-I0-LS-FMT & !I0-LS-STORE 
	        | DD-I0-EX-FMT & we-on(I0-EX-EXU-OPC)
	        | DD-I0-JB-FMT & I0-JB-LINK
DD-FIRST-RADB-V = DD-FIRST-IS-LS | DD-I0-JB-FMT & I0-JB-REG
DD-FIRST-RAD2-V = DD-I0-EX-FMT & (I0-EX-OP2MODE == EXMOD-RR)
                | DD-I0-JB-FMT & I0-JB-CMP | (DD-PRIVCODE == PRIVCODE-WSR)
DD-FIRST-RAD1-V = DD-I0-EX-FMT & (I0-EX-OP2MODE == EXMOD-RI) | DD-FIRST-RAD2-V
DD-FIRST-RADB1  = I0-EX-RB1 
DD-FIRST-RAD2   = I0-EX-RS2 

DD-SECOND-SETCC	  = DD-I1-EX-FMT & I1-EX-SETCC
DD-SECOND-WAD  	  = I1-EX-RD
DD-SECOND-WAD-V	  = DD-I1-LS-FMT & !I1-LS-STORE 
		  | DD-I1-EX-FMT & we-on(I1-EX-EXU-OPC)
	          | DD-I1-JB-FMT & I1-JB-LINK
DD-SECOND-RADB-V = DD-SECOND-IS-LS | DD-I1-JB-FMT & I1-JB-REG
DD-SECOND-RAD2-V  = DD-I1-EX-FMT & (I1-EX-OP2MODE == EXMOD-RR)
		  | DD-I1-JB-FMT & I1-JB-CMP
DD-SECOND-RAD1-V = DD-I1-EX-FMT & (I1-EX-OP2MODE == EXMOD-RI) | DD-SECOND-RAD2-V
DD-SECOND-RADB1   = I1-EX-RB1 
DD-SECOND-RAD2    = I1-EX-RS2 

