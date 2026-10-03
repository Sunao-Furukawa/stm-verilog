# e-act : e-cyc activity

# Bypass STB if address matches (Store-Load Bypass) ## move this part to SU?
EE-MEMOP = E-LS-LD-DT
#if 0
EE-MEMOP = (E-LS-LD-V & STB-V & (E-LS-LOG-AD == STB-AD)) ? STB-DT : E-LS-LD-DT
#endif

# Bypass register if E-reg-num matches W-reg-num. (E-cyc to A-cyc Bypass)
EE-OPS = E-LS-OPS-DT 
#if 0
   (E-LS-OPS-IS-GR & E-WE2 & (E-LS-RADS == E-WAD2) & E-FIRST-IS-EX) ? E-EX-RES :
   (E-LS-OPS-IS-GR & W-WE1 & (E-LS-RADS == W-WAD1))	? W-WDT1  :
   (E-LS-OPS-IS-GR & W-WE2 & (E-LS-RADS == W-WAD2))  	? W-WDT2  : E-LS-OPS-DT
#endif

#ifndef VHDL
exu(E-LS-OPCODE,EE-OPS,EE-MEMOP,&EE-ALU-CC,&EE-ALU-OUTPUT,&EE-ALU-INT);
#endif

# Handling of interruption

EE-LS-INTCODE = (E-LS-INTCODE != 0) ? E-LS-INTCODE : EE-ALU-INT
EE-LS-INT-V   = (EE-LS-INTCODE != 0)
EE-EX-INT-V   = (E-EX-INTCODE != 0)
EE-HIDE-EX = !E-FIRST-IS-EX & EE-LS-INT-V
EE-HIDE-LS =  E-FIRST-IS-EX & EE-EX-INT-V

EE-SET-CC-FROM-LS = E-LS-SETCC & !EE-LS-INT-V & !EE-HIDE-LS
			& !(E-EX-SETCC & !E-FIRST-IS-EX & !EE-EX-INT-V)
EE-SET-CC-FROM-EX = E-EX-SETCC & !EE-EX-INT-V & !EE-HIDE-EX
			& !(E-LS-SETCC &  E-FIRST-IS-EX & !EE-LS-INT-V)
###   Set w-tags
###   These tags can be always copied to W-cyc
  W-WAD1 := E-WAD1
  W-WAD2 := E-WAD2
  W-WDT1 := EE-ALU-OUTPUT
  W-WDT2 := E-EX-RES
  W-TGT    	    := E-TGT
  W-IS-SUPERSCALAR  := E-IS-SUPERSCALAR
  W-LATTER-IS-JB    := E-LATTER-IS-JB  
  W-FIRST-IS-EX     := E-FIRST-IS-EX
  W-CC	:= ( EE-SET-CC-FROM-LS ? EE-ALU-CC : E-EX-CC )

# if (!E-FWD) # In next cycle, E-cyc won't release and W-cyc will be empty 
#	      # except STB, which depends on INTLK.  Clear GR/CC/PC valids.
  W-WE1        := E-FWD ?  E-WE1 & !EE-LS-INT-V & !EE-HIDE-LS   : 0
  W-WE2        := E-FWD ?  E-WE2 & !EE-EX-INT-V & !EE-HIDE-EX   : 0
  W-SETCC      := E-FWD ?  EE-SET-CC-FROM-LS | EE-SET-CC-FROM-EX   : 0
  W-COMPLETE   := E-FWD ?  1   : 0
  W-PRIVCODE   := E-FWD ?  E-PRIVCODE   : 0
  W-EX-INTCODE := E-FWD ?  E-EX-INTCODE   : 0
  W-LS-INTCODE := E-FWD ?  EE-LS-INTCODE	: 0

		# Set W-JB-V iff branch is taken.
		# Usually E-cyc ALU-CC is first latched in G-XXX and then
		# used.  Setting W-JB-V is the only exception, where 
		# ALU-CC is used directly, i.e. in the same cycle.
  W-JB-V     := E-FWD ?  E-JB-V & (!E-JB-IS-BC | E-LS-SOLVING-BC 
		 & cc-match(EE-ALU-CC,G-BC-MASK) | G-BC-JUST-TAKEN) : 0

STB-V      := ( STB-V & !WW-ST-GO ) | E-LS-ST-V & E-FWD & !EE-HIDE-LS

  STB-AD     := E-FWD & E-LS-ST-V ? E-LS-LOG-AD    : STB-AD
  STB-DT     := E-FWD & E-LS-ST-V ? EE-ALU-OUTPUT  : STB-DT
