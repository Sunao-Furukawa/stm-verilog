#  d-act
      # With A-INTLK, BC is never issued in D-cyc, hence not set SOLVING-BC

A-V 			:= D-FWD | A-INTLK

A-JB-IS-BC           := D-FWD   ? DD-ISSUEING-UNSOLVED-BC :
			   A-INTLK ? A-JB-IS-BC & !G-BC-JUST-SOLVED : 0
A-JB-SUBJECT-TO-BC   := D-FWD   ? G-BC-PENDING :
			   A-INTLK ? A-JB-SUBJECT-TO-BC & !G-BC-JUST-SOLVED : 0
A-JB-V  		:= D-FWD   ? IJB-V & !DD-ISSUEING-UNTAKEN-BC :
     A-INTLK ? A-JB-V & !(A-JB-IS-BC & G-BC-JUST-SOLVED & !G-BC-JUST-TAKEN) : 0

A-LS-SOLVING-BC      := A-INTLK ? A-LS-SOLVING-BC :
			D-FWD   ? DD-ISSUEING-UNSOLVED-BC-ON-D-LS : 0
A-EX-SOLVING-BC      := A-INTLK ? A-EX-SOLVING-BC      : 
			D-FWD ?  DD-ISSUEING-UNSOLVED-BC-ON-D-EX : 0
A-INTCODE	:= A-INTLK ? A-INTCODE	: D-FWD ?  DD-INTCODE : 0
A-PRIVCODE	:= A-INTLK ? A-PRIVCODE	: D-FWD ?  DD-PRIVCODE : 0

# Subword store loads data
A-LS-LD-V	:= A-INTLK ? A-LS-LD-V	: 
	D-FWD ? ILS-LS-FMT & !(ILS-STORE & (ILS-LENG == 0)) | ILS-EXRM-FMT : 0
A-WE1  	   	:= A-INTLK ? A-WE1  	   	: 
		D-FWD ? ILS-LS-FMT & !ILS-STORE 
		  | ILS-EXRM-FMT & we-on(ILS-EXU-OPC) : 0
A-LS-ST-V	:= A-INTLK ? A-LS-ST-V	: D-FWD ?  ILS-LS-FMT &  ILS-STORE : 0

A-LS-OPS-IS-GR	:= A-INTLK ? A-LS-OPS-IS-GR	: 
		D-FWD ?  ILS-LS-FMT &  ILS-STORE |  ILS-EXRM-FMT : 0
A-LS-SETCC	:= A-INTLK ? A-LS-SETCC	: D-FWD ?  ILS-EXRM-FMT &  ILS-SETCC : 0

A-EX-SETCC	:= A-INTLK ? A-EX-SETCC	: D-FWD ?  IEX-SETCC : 0
A-WE2	  	:= A-INTLK ? A-WE2	  	: 
		D-FWD ?  we-on(IEX-EXU-OPC) | IJB-V & IJB-LINK 
			| (DD-PRIVCODE == PRIVCODE-RSR) : 0


   # Tags that are not 'valid' tags can be written with CE = !A-INTLK.
A-WAD1		:= A-INTLK ? A-WAD1	:  ILS-RD-RS 
A-LS-RADS	:= A-INTLK ? A-LS-RADS	:  (ILS-LS-FMT ?  ILS-RD-RS : ILS-RS2)
A-WAD2    	:= A-INTLK ? A-WAD2    :  
		IEX-V ? IEX-RD : ((DD-PRIVCODE != 0) ? I0-EX-RD : IJB-RD-MASK)

# For byte/halfword load/store, opcode is
#    1  STORE HALFWORD(!BYTE) * * 
# where ** are the last bits of address.
# In EXRM case, opcode is extended from 4 to 5 bits.
#ifndef VHDL
A-LS-OPCODE := A-INTLK ? 	A-LS-OPCODE :  
		ILS-EXRM-FMT ? ILS-EXU-OPC  :
		ILS-LS-FMT & (ILS-LENG!=0)  ? 
		    16 | (ILS-STORE ? 8 : 0)|((ILS-LENG & 2) ? 4 : 0) :
		(ILS-STORE ? OPC-STW : OPC-LDW)
#else
A-LS-OPCODE := A-INTLK ? 	A-LS-OPCODE :  
		ILS-EXRM-FMT ? B"0" . ILS-EXU-OPC  :
		ILS-LS-FMT & (ILS-LENG!=0)  ? 
		    B"1" . ILS-STORE . ILS-LENG[2] . B"00" :
		(ILS-STORE ? OPC-STW : OPC-LDW)
#endif

A-IS-SUPERSCALAR := A-INTLK ? A-IS-SUPERSCALAR :  DD-ISSUE-SECOND-INSN
A-FIRST-IS-EX    := A-INTLK ? A-FIRST-IS-EX    :  DD-FIRST-IS-EX
A-LATTER-IS-JB   := A-INTLK ? A-LATTER-IS-JB   :  DD-SECOND-IS-JB
A-TGT 		 := A-INTLK ? A-TGT 		 :  DD-TGT

	# If there's nothing else, OPC-EX is AU for LINK 
A-EX-OPCODE := A-INTLK ? A-EX-OPCODE :   
		IEX-V  ? IEX-EXU-OPC : 
		IJB-V & IJB-CMP 	? OPC-C : 
		(DD-PRIVCODE == PRIVCODE-WSR) ? OPC-LDW : OPC-AU
A-SET-EAG-TO-TGT := A-INTLK ? A-SET-EAG-TO-TGT :  IJB-REG
