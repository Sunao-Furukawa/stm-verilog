# d-dat

A-LS-OPB-IS-GR	:= A-INTLK ? A-LS-OPB-IS-GR  :
	D-FWD ? DD-FIRST-RADB-V | DD-ISSUE-SECOND-INSN & DD-SECOND-RADB-V : 0
A-EX-OP1-IS-GR	:= A-INTLK ? A-EX-OP1-IS-GR  : 
	D-FWD ? DD-FIRST-RAD1-V | DD-ISSUE-SECOND-INSN & DD-SECOND-RAD1-V : 0
A-EX-OP2-IS-GR	:= A-INTLK ? A-EX-OP2-IS-GR  :
	D-FWD ? DD-FIRST-RAD2-V | DD-ISSUE-SECOND-INSN & DD-SECOND-RAD2-V : 0


DD-JB-INSN-AD-PART2P4 = add4_5(DD-JB-INSN-AD-PART2) 	# ... + 4

#if 0
A-LS-OPB-DT	:=   
	( !A-INTLK & (DD-RADB == W-WAD1) 
	 | A-INTLK & (A-LS-RADB == W-WAD1) & A-LS-OPB-IS-GR ) & W-WE1 ? W-WDT1 :
	( !A-INTLK & (DD-RADB == W-WAD2) 
	 | A-INTLK & (A-LS-RADB == W-WAD2) & A-LS-OPB-IS-GR ) & W-WE2 ? W-WDT2 :
	!A-INTLK ? GR-DT-B : A-LS-OPB-DT  

A-EX-OP1-DT	:=   
    ( !A-INTLK & (DD-RAD1 == W-WAD1) 
	 | A-INTLK & (A-EX-RAD1 == W-WAD1) & A-EX-OP1-IS-GR ) & W-WE1 ? W-WDT1 :
    ( !A-INTLK & (DD-RAD1 == W-WAD2) 
	 | A-INTLK & (A-EX-RAD1 == W-WAD2) & A-EX-OP1-IS-GR ) & W-WE2 ? W-WDT2 :
     A-INTLK 		? A-EX-OP1-DT :
    (IJB-V & IJB-LINK)  ? sign_ext_6(DD-JB-INSN-AD-PART2P4) : GR-DT-1 

A-EX-OP2-DT	:=   
    !A-INTLK & (IEX-OP2MODE == EXMOD-RI)     ? sign-ext-16(IEX-IMM16) :
    ( !A-INTLK & (DD-RAD2 == W-WAD1) 
	 | A-INTLK & (A-EX-RAD2 == W-WAD1) & A-EX-OP2-IS-GR ) & W-WE1 ? W-WDT1 :
    ( !A-INTLK & (DD-RAD2 == W-WAD2) 
	 | A-INTLK & (A-EX-RAD2 == W-WAD2) & A-EX-OP2-IS-GR ) & W-WE2 ? W-WDT2 :
     A-INTLK 		? A-EX-OP2-DT :
    (IJB-V & IJB-LINK)  ? DD-JB-INSN-AD-PART1 : GR-DT-2
#else
A-LS-OPB-DT	:=   
	  !A-INTLK & (DD-RADB == A-WAD2) & A-WE2 ? AA-EX-RES :
	  !A-INTLK & (DD-RADB == B-WAD2) & B-WE2 ?  B-EX-RES :
	( !A-INTLK & 
	    (  (DD-RADB == B-WAD1) & B-WE1 
	     | (DD-RADB == E-WAD1) & E-WE1 & (E-LS-OPCODE == 0) & !E-OPCLH-LCH )
	 | A-INTLK & A-LS-OPB-IS-GR &
	    (  (A-LS-RADB == B-WAD1) & B-WE1 
	     | (A-LS-RADB == E-WAD1) & E-WE1 & (E-LS-OPCODE == 0) & !E-OPCLH-LCH
		 & !((A-LS-RADB == B-WAD2) & B-WE2)  		   )
	)					? BB-MEM-DATA :
	( !A-INTLK & (DD-RADB == E-WAD1) & E-WE1
	 | A-INTLK & A-LS-OPB-IS-GR 
	  & (A-LS-RADB == E-WAD1) & ((E-LS-OPCODE !=0) | E-OPCLH-LCH) & E-WE1
	  & !((A-LS-RADB == B-WAD2) & B-WE2) 
	)				         ? EE-ALU-OUTPUT:
	  !A-INTLK & (DD-RADB == E-WAD2) & E-WE2 ?  E-EX-RES :
	  !A-INTLK & (DD-RADB == W-WAD1) & W-WE1 ?  W-WDT1   :
	  !A-INTLK & (DD-RADB == W-WAD2) & W-WE2 ?  W-WDT2   :
	  !A-INTLK ? GR-DT-B : A-LS-OPB-DT  

A-EX-OP1-DT	:=   
	  !A-INTLK & (IJB-V & IJB-LINK)  ? sign_ext_6(DD-JB-INSN-AD-PART2P4) :
	  !A-INTLK & (DD-RAD1 == A-WAD2) & A-WE2 ? AA-EX-RES :
	  !A-INTLK & (DD-RAD1 == B-WAD2) & B-WE2 ?  B-EX-RES :
	( !A-INTLK & 
	    (  (DD-RAD1 == B-WAD1) & B-WE1 
	     | (DD-RAD1 == E-WAD1) & E-WE1 & (E-LS-OPCODE == 0) & !E-OPCLH-LCH )
	 | A-INTLK & A-EX-OP1-IS-GR &
	    (  (A-EX-RAD1 == B-WAD1) & B-WE1 
	     | (A-EX-RAD1 == E-WAD1) & E-WE1 & (E-LS-OPCODE == 0) & !E-OPCLH-LCH
		 & !((A-EX-RAD1 == B-WAD2) & B-WE2)  		   )
	)					? BB-MEM-DATA :
	( !A-INTLK & (DD-RAD1 == E-WAD1) & E-WE1
	 | A-INTLK & A-EX-OP1-IS-GR 
	  & (A-EX-RAD1 == E-WAD1) & ((E-LS-OPCODE !=0) | E-OPCLH-LCH) & E-WE1
	  & !((A-EX-RAD1 == B-WAD2) & B-WE2)
	)				         ? EE-ALU-OUTPUT:
	  !A-INTLK & (DD-RAD1 == E-WAD2) & E-WE2 ?  E-EX-RES :
	  !A-INTLK & (DD-RAD1 == W-WAD1) & W-WE1 ?  W-WDT1   :
	  !A-INTLK & (DD-RAD1 == W-WAD2) & W-WE2 ?  W-WDT2   :
	  !A-INTLK ? GR-DT-1 : A-EX-OP1-DT  

A-EX-OP2-DT	:=   
	  !A-INTLK & (IEX-OP2MODE == EXMOD-RI)     ? sign-ext-16(IEX-IMM16) :
	  !A-INTLK & (IJB-V & IJB-LINK)  ? DD-JB-INSN-AD-PART1 :
	  !A-INTLK & (DD-RAD2 == A-WAD2) & A-WE2 ? AA-EX-RES :
	  !A-INTLK & (DD-RAD2 == B-WAD2) & B-WE2 ?  B-EX-RES :
	( !A-INTLK & 
	    (  (DD-RAD2 == B-WAD1) & B-WE1 
	     | (DD-RAD2 == E-WAD1) & E-WE1 & (E-LS-OPCODE == 0) & !E-OPCLH-LCH )
	 | A-INTLK & A-EX-OP2-IS-GR &
	    (  (A-EX-RAD2 == B-WAD1) & B-WE1 
	     | (A-EX-RAD2 == E-WAD1) & E-WE1 & (E-LS-OPCODE == 0) & !E-OPCLH-LCH
		 & !((A-EX-RAD2 == B-WAD2) & B-WE2)  		   )
	)					? BB-MEM-DATA :
	( !A-INTLK & (DD-RAD2 == E-WAD1) & E-WE1
	 | A-INTLK & A-EX-OP2-IS-GR 
	  & (A-EX-RAD2 == E-WAD1) & ((E-LS-OPCODE !=0) | E-OPCLH-LCH) & E-WE1
	  & !((A-EX-RAD2 == B-WAD2) & B-WE2)
	)				         ? EE-ALU-OUTPUT:
	  !A-INTLK & (DD-RAD2 == E-WAD2) & E-WE2 ?  E-EX-RES :
	  !A-INTLK & (DD-RAD2 == W-WAD1) & W-WE1 ?  W-WDT1   :
	  !A-INTLK & (DD-RAD2 == W-WAD2) & W-WE2 ?  W-WDT2   :
	  !A-INTLK ? GR-DT-2 : A-EX-OP2-DT  
#endif


A-LS-RADB	:= A-INTLK ? A-LS-RADB : DD-RADB

A-EX-RAD1	:= A-INTLK ? A-EX-RAD1 : DD-RAD1

A-EX-RAD2	:= A-INTLK ? A-EX-RAD2 : DD-RAD2

A-DISP		:= A-INTLK ? A-DISP    : DD-DISP

