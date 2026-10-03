# a-act

B-V 			:= A-FWD | B-INTLK 

B-JB-IS-BC           := A-FWD   ? A-JB-IS-BC & !G-BC-JUST-SOLVED :
			B-INTLK ? B-JB-IS-BC & !G-BC-JUST-SOLVED : 0
B-JB-SUBJECT-TO-BC   := A-FWD   ? A-JB-SUBJECT-TO-BC & !G-BC-JUST-SOLVED :
			B-INTLK ? B-JB-SUBJECT-TO-BC & !G-BC-JUST-SOLVED : 0
B-JB-V 		     := 
    A-FWD   ? A-JB-V & !(A-JB-IS-BC & G-BC-JUST-SOLVED & !G-BC-JUST-TAKEN) :
    B-INTLK ? B-JB-V & !(B-JB-IS-BC & G-BC-JUST-SOLVED & !G-BC-JUST-TAKEN) : 0
B-LS-SOLVING-BC := 
    A-FWD   ? A-LS-SOLVING-BC | DD-ISSUEING-UNSOLVED-BC-ON-A-LS & D-FWD :
    B-INTLK ? B-LS-SOLVING-BC | DD-ISSUEING-UNSOLVED-BC-ON-B-LS & D-FWD : 0

B-INTCODE	:= B-INTLK ? B-INTCODE : !A-FWD ? 0 : 
		   (A-INTCODE != 0) ? A-INTCODE : AA-EXU-INT

   	# These tags are just copied unmodified:
B-PRIVCODE	:= A-FWD ?  A-PRIVCODE  : B-INTLK ? B-PRIVCODE  : 0
B-LS-LD-V	:= A-FWD ?  A-LS-LD-V   : B-INTLK ? B-LS-LD-V   : 0
B-LS-ST-V	:= A-FWD ?  A-LS-ST-V	: B-INTLK ? B-LS-ST-V   : 0
B-WE1    	:= A-FWD ?  A-WE1  	: B-INTLK ? B-WE1       : 0
B-WE2    	:= A-FWD ?  A-WE2 	: B-INTLK ? B-WE2       : 0
B-LS-SETCC	:= A-FWD ?  A-LS-SETCC  : B-INTLK ? B-LS-SETCC  : 0
B-EX-SETCC	:= A-FWD ?  A-EX-SETCC  : B-INTLK ? B-EX-SETCC  : 0


   # Tags that are not 'valid' tags can be copied with CE = !B-INTLK.
B-LS-LOG-AD	:= !B-INTLK ? AA-EAG-OUTPUT : B-LS-LOG-AD

B-WAD1  	:= !B-INTLK ?  A-WAD1   	: B-WAD1  
B-WAD2  	:= !B-INTLK ?  A-WAD2   	: B-WAD2
B-LS-OPS-IS-GR  := !B-INTLK ?  A-LS-OPS-IS-GR   : B-LS-OPS-IS-GR
B-LS-RADS  	:= !B-INTLK ?  A-LS-RADS   	: B-LS-RADS 
B-LS-OPCODE  	:= !B-INTLK ?  A-LS-OPCODE   	: B-LS-OPCODE 
B-IS-SUPERSCALAR := !B-INTLK ? A-IS-SUPERSCALAR : B-IS-SUPERSCALAR
B-LATTER-IS-JB  := !B-INTLK ?  A-LATTER-IS-JB   : B-LATTER-IS-JB
B-FIRST-IS-EX	:= !B-INTLK ?  A-FIRST-IS-EX   	: B-FIRST-IS-EX
B-EX-RAD2	:= !B-INTLK ?  A-EX-RAD2  	: B-EX-RAD2

   # In branch using reg+base, TGT adrs is generated at EAG in A-cyc.
B-TGT     := B-INTLK ? B-TGT    : (A-SET-EAG-TO-TGT ? AA-EAG-OUTPUT : A-TGT )

B-EX-RES  := B-INTLK ? B-EX-RES : AA-EX-RES
B-EX-CC   := !B-INTLK ?  AA-EXU-CC : B-EX-CC

