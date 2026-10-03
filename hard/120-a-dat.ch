# a-dat
# Bypass register if A-reg-num matches X-reg-num. (Execute-Execute Bypass)
#
# Note :
# o The order of 'else-if' is important here because LATEST one should be used.
#   For example, if B- and E-cycs write same GR, B-cyc data should be used.
#
# o Two insns which write same GR are never issued concurrently.  Therefore
#   we don't have to worry about that possibility here. (ex. W-WAD1 != W-WAD2)
#

#   MEMOP is itself a bypassed data.  May be critical path!  

#if 0
AA-OPB = 
 (A-LS-OPB-IS-GR & B-WE2 & (A-LS-RADB == B-WAD2)) ? B-EX-RES  :
 (A-LS-OPB-IS-GR & E-WE1 & (A-LS-RADB == E-WAD1) & (E-LS-OPCODE==0))? EE-MEMOP :
 (A-LS-OPB-IS-GR & E-WE2 & (A-LS-RADB == E-WAD2)) ? E-EX-RES  :
 (A-LS-OPB-IS-GR & W-WE1 & (A-LS-RADB == W-WAD1)) ? W-WDT1 :
 (A-LS-OPB-IS-GR & W-WE2 & (A-LS-RADB == W-WAD2)) ? W-WDT2 :  A-LS-OPB-DT 

AA-OP1 = 
 (A-EX-OP1-IS-GR & B-WE2 & (A-EX-RAD1 == B-WAD2)) ? B-EX-RES  :
 (A-EX-OP1-IS-GR & E-WE1 & (A-EX-RAD1 == E-WAD1) & (E-LS-OPCODE==0))? EE-MEMOP :
 (A-EX-OP1-IS-GR & E-WE2 & (A-EX-RAD1 == E-WAD2)) ? E-EX-RES  :
 (A-EX-OP1-IS-GR & W-WE1 & (A-EX-RAD1 == W-WAD1)) ? W-WDT1 :
 (A-EX-OP1-IS-GR & W-WE2 & (A-EX-RAD1 == W-WAD2)) ? W-WDT2 : A-EX-OP1-DT

AA-OP2 = 
 (A-EX-OP2-IS-GR & B-WE2 & (A-EX-RAD2 == B-WAD2)) ? B-EX-RES  :
 (A-EX-OP2-IS-GR & E-WE1 & (A-EX-RAD2 == E-WAD1) & (E-LS-OPCODE==0))? EE-MEMOP :
 (A-EX-OP2-IS-GR & E-WE2 & (A-EX-RAD2 == E-WAD2)) ? E-EX-RES  :
 (A-EX-OP2-IS-GR & W-WE1 & (A-EX-RAD2 == W-WAD1)) ? W-WDT1 :
 (A-EX-OP2-IS-GR & W-WE2 & (A-EX-RAD2 == W-WAD2)) ? W-WDT2 : A-EX-OP2-DT
#else
AA-OPB = A-LS-OPB-DT
AA-OP1 = A-EX-OP1-DT
AA-OP2 = A-EX-OP2-DT
#endif


#ifndef VHDL
exu(A-EX-OPCODE,AA-OP1,AA-OP2,&AA-EXU-CC,&AA-EXU-OUTPUT,&AA-EXU-INT)

AA-EAG-OUTPUT = add_32_16(AA-OPB,A-DISP)
#endif

# Read SR data

A-SR-READ-DATA = 
        (A-EX-RAD2 == SYSREG-PSW)   ? build_psw(PSW-CC,PSW-USER,PSW-TYPE) :
        (A-EX-RAD2 == SYSREG-TBR)   ? TBR :
        (A-EX-RAD2 == SYSREG-CMPR)  ? CMPR :
        (A-EX-RAD2 == SYSREG-XPSW)  ? XPSW :
        (A-EX-RAD2 == SYSREG-XPC)   ? XPC :
        (A-EX-RAD2 == SYSREG-XLA)   ? XLA :
        (A-EX-RAD2 == SYSREG-SVR0)  ? SVR0 :
        (A-EX-RAD2 == SYSREG-SVR1)  ? SVR1 : 0

AA-EX-RES = (A-PRIVCODE==PRIVCODE-RSR) ? A-SR-READ-DATA : AA-EXU-OUTPUT

