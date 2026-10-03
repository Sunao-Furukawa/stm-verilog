# b-act 
# Three cases are possible : 
#
#  1.INTLK) E interlocks(E-INTLK).  Handles only BC decision and data bypass.
#  2.CLEAR) E is (or becomes) empty(!E-INTLK & !B-FWD).  Clears valid flags.
#  3.SLIDE) B enters E (B-FWD).  B slides into E.
#
#  valids ---   data: NOW-FWD and (set-data) ,  CE  : !NXT-INTLK
#  others ---   data: (set-data itself)      ,  CE  : !NXT-INTLK

# E-STB-INTLK and B-LMD-INTLK never occur at the same time; if B-cyc is  
# load or store (, maybe sending OPCLH,) and E-cyc is store  , W-cyc 
# store request by STB-V is always accepted by SU and E-STB-INTLK never 
# occurs.  OPCLH is never made to wait by E-STB-INTLK.

   E-V 			:= B-FWD   ? 1 : E-INTLK ? E-V : 0

   # JB-related tags need special handling; may be modified even when interlock
   E-JB-IS-BC           := B-FWD   ? B-JB-IS-BC & !G-BC-JUST-SOLVED :
			   E-INTLK ? E-JB-IS-BC & !G-BC-JUST-SOLVED : 0
   E-JB-SUBJECT-TO-BC   := B-FWD   ? B-JB-SUBJECT-TO-BC & !G-BC-JUST-SOLVED :
			   E-INTLK ? E-JB-SUBJECT-TO-BC & !G-BC-JUST-SOLVED : 0
   E-JB-V     		:= 
      B-FWD   ? B-JB-V & !(B-JB-IS-BC & G-BC-JUST-SOLVED & !G-BC-JUST-TAKEN) :
      E-INTLK ? E-JB-V & !(E-JB-IS-BC & G-BC-JUST-SOLVED & !G-BC-JUST-TAKEN) : 0
   E-LS-SOLVING-BC 	:= 
	B-FWD   ? B-LS-SOLVING-BC | DD-ISSUEING-UNSOLVED-BC-ON-B-LS & D-FWD :
	E-INTLK ? E-LS-SOLVING-BC | DD-ISSUEING-UNSOLVED-BC-ON-E-LS & D-FWD : 0

   # These tags are just copied unmodified:
   E-LS-LD-V 		:= B-FWD ? B-LS-LD-V  	: E-INTLK ? E-LS-LD-V    : 0
   E-LS-ST-V 		:= B-FWD ?  B-LS-ST-V 	: E-INTLK ? E-LS-ST-V    : 0
   E-WE1     		:= B-FWD ?  B-WE1 	: E-INTLK ? E-WE1        : 0
   E-WE2     		:= B-FWD ?  B-WE2 	: E-INTLK ? E-WE2        : 0
   E-LS-SETCC 		:= B-FWD ?  B-LS-SETCC  : E-INTLK ? E-LS-SETCC   : 0
   E-EX-SETCC 		:= B-FWD ?  B-EX-SETCC  : E-INTLK ? E-EX-SETCC   : 0
   E-EX-INTCODE		:= B-FWD ?  B-INTCODE   : E-INTLK ? E-EX-INTCODE : 0
   E-PRIVCODE		:= B-FWD ?  B-PRIVCODE  : E-INTLK ? E-PRIVCODE   : 0

   # Tags that are not 'valid' tags can be copied with CE = !E-INTLK.
   E-LS-LOG-AD 		:= !E-INTLK ?  B-LS-LOG-AD  	: E-LS-LOG-AD
   E-WAD1   		:= !E-INTLK ?  B-WAD1    	: E-WAD1
   E-WAD2   		:= !E-INTLK ?  B-WAD2    	: E-WAD2
   E-LS-OPS-IS-GR	:= !E-INTLK ?  B-LS-OPS-IS-GR 	: E-LS-OPS-IS-GR
   E-LS-RADS   		:= !E-INTLK ?  B-LS-RADS   	: E-LS-RADS
   E-EX-RES             := !E-INTLK ?  B-EX-RES 	: E-EX-RES
   E-EX-CC       	:= !E-INTLK ?  B-EX-CC  	: E-EX-CC
   E-TGT	       	:= !E-INTLK ?  B-TGT 		: E-TGT
   E-IS-SUPERSCALAR    	:= !E-INTLK ?  B-IS-SUPERSCALAR : E-IS-SUPERSCALAR
   E-LATTER-IS-JB      	:= !E-INTLK ?  B-LATTER-IS-JB   : E-LATTER-IS-JB
   E-FIRST-IS-EX       	:= !E-INTLK ?  B-FIRST-IS-EX    : E-FIRST-IS-EX 

# Change OPCODE depending on address when L/ST-byte/hfw
#ifndef VHDL
   E-LS-OPCODE 	  := !E-INTLK ? 
		(  B-LS-OPCODE 
               	    | ((B-LS-OPCODE & 16) ? (B-LS-LOG-AD & 2) : 0)
		    | (((B-LS-OPCODE & 16) && (!(B-LS-OPCODE & 4))) ? 
				(B-LS-LOG-AD & 1) : 0)	)
		: E-LS-OPCODE
#else
E-LS-OPCODE    := !E-INTLK ? B-LS-OPCODE[0:3] . 
		  B-LS-OPCODE[0] & B-LS-LOG-AD[30] . 
		  B-LS-OPCODE[0] & !B-LS-OPCODE[2] & B-LS-LOG-AD[31]  
		: E-LS-OPCODE
#endif
