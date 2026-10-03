# w-act : w-cycle activity 

#  Modify GR,SR  -- not depend on intr (WE* or PRIVCODE is enough)

TBR  := (WW-WSR & (W-WAD2 == SYSREG-TBR)) ? W-WDT2 		: TBR
CMPR := (WW-WSR & (W-WAD2 == SYSREG-CMPR)) ? W-WDT2 		: CMPR
SVR0 := (WW-WSR & (W-WAD2 == SYSREG-SVR0)) ? W-WDT2 		: SVR0
SVR1 := (WW-WSR & (W-WAD2 == SYSREG-SVR1)) ? W-WDT2 		: SVR1

#  Compute new PC
PC-INCR-AMOUNT  = ( W-IS-SUPERSCALAR & !W-JB-V & !WW-INTERRUPTION) ? 8 : 
	       (  WW-LS-INT-V & (!W-IS-SUPERSCALAR | !W-FIRST-IS-EX)
	       |  WW-EX-INT-V & (!W-IS-SUPERSCALAR |  W-FIRST-IS-EX) ) ? 0 : 4

#ifndef VHDL
INCREMENTED-PC  = add_32_4(PC,PC-INCR-AMOUNT)
#endif

MODIFIED-PC  = ( W-JB-V & !WW-INTERRUPTION )  ? W-TGT : INCREMENTED-PC

#  Compute new CC
MODIFIED-CC  = W-SETCC ? W-CC : PSW-CC

#  Modify PC,PSW-CC/USER/TYPE

WW-HIDE-LS  = W-FIRST-IS-EX & WW-EX-INT-V
WW-INTCODE  = (WW-LS-INT-V & !WW-HIDE-LS) ? W-LS-INTCODE : W-EX-INTCODE

PSW-CC	   := 	WW-INTERRUPTION 		? 0 :
		WW-RFE          		? pickup_cc(XPSW) :
		WW-WSR & (W-WAD2 == SYSREG-PSW) ? pickup_cc(W-WDT2) :
						  MODIFIED-CC

PSW-USER   :=   WW-INTERRUPTION 		? 0 :
		WW-RFE          		? pickup_user(XPSW) :
		WW-WSR & (W-WAD2 == SYSREG-PSW) ? pickup_user(W-WDT2) :
						  PSW-USER

PSW-TYPE   :=   WW-INTERRUPTION 		? zero_ext_5(WW-INTCODE) :
		WW-RFE          		? pickup_type(XPSW) :
		WW-WSR & (W-WAD2 == SYSREG-PSW) ? pickup_type(W-WDT2) :
						  PSW-TYPE

PC         :=   WW-INTERRUPTION 		? TBR :
		WW-RFE          		? XPC :
		W-COMPLETE          		? MODIFIED-PC : 
						  PC
XPSW	   :=   WW-INTERRUPTION ? build_psw(MODIFIED-CC,PSW-USER,PSW-TYPE) :
		WW-WSR & (W-WAD2 == SYSREG-XPSW) ? W-WDT2 :
						   XPSW

XPC 	   :=   WW-INTERRUPTION 		? MODIFIED-PC :
		WW-WSR & (W-WAD2 == SYSREG-XPC) ? W-WDT2 :
						  XPC

XLA 	   :=   WW-INTERRUPTION & (W-LS-INTCODE == INTCODE-TLB) & !WW-HIDE-LS
	 		? W-WDT1 :
		WW-WSR & (W-WAD2 == SYSREG-XLA) ? W-WDT2 :
						  XLA


START-TRIGGER-BAR := !( WW-INTERRUPTION | WW-RFE | WW-STATECHANGE )
START-TRIGGER	= !START-TRIGGER-BAR

