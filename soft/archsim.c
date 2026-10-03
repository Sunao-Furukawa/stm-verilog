
#include <stdio.h> 
#include <string.h> 

#include "../hard/const.h"
#include "../hard/defs.h"
#include "../hard/fmt-ls-ex.h"
#include "../hard/fmt-jb.h"
#include "../hard/exu.h"

#define ishex(c) (('0'<=c)&&(c<='9')||('a'<=c)&&(c<='f')||('A'<=c)&&(c<='F'))
#define hexval(c) (('0'<=c)&&(c<='9')?c-'0': \
                     (('a'<=c)&&(c<='f')?c+10-'a':c+10-'A'))
int hex2d(s) char *s; { int x = 0 ;
  while (ishex(*s)) {
    x = x * 16 + hexval(*s) ;
    s++;
   }
  return(x);
 }
#define d2hex(x) ((0<=x)&&(x<=9)?x+'0':x-10+'a')
/* d2hex if used only when 0<=x<=15 */
int mynull() {}

unsigned PC,PSW_CC,PSW_USER,PSW_TYPE,SR[16] ;
unsigned GR[16],Mem[1024],OLD_PC ;

main(argc,argv) int argc; char **argv; {

FILE *fpi;
unsigned mask,*pgr;
unsigned i;
char s[80];
int loopcnt,LOOPMAX,m_adr,ad,branch_taken;

/* Open object file */
if (argc == 1) { fprintf(stderr,"Specify input file.\n"); exit(8); }
fpi = fopen(argv[1],"r");

fgets(s,80,fpi);        /* first line is start-pc */ 
PC =          hex2d(s); /* hex2d does not need chopping-off */
fgets(s,80,fpi);        /* second line is loop count */
s[strlen(s)-1] = '\0' ;  /* chop off CR */
LOOPMAX = atoi(s);

/* Read into memory */
while (fgets(s,80,fpi) != NULL) 
  if(s[strlen(s)-2] == ':') m_adr = hex2d(s) / 4 ;
  else if(s[0] == '#')      continue  ;
  else                      Mem[m_adr++] = hex2d(s);
fclose(fpi) ;

printf("loopcnt  PC      CC  insn\n\n");

/* Execute insns one by one... */
for(loopcnt=1;loopcnt<=LOOPMAX;loopcnt++) {
 i = Mem[PC>>2];
 branch_taken = 0;
 printf("%5d  %8.8x  %d  %8.8x",loopcnt,PC,PSW_CC,i);
 if ((i >>28) == 13) { putchar('\n'); exit(0); }

 if (!is_legal_opc(i,PSW_USER)) {   /* Illegal insn exception */
	do_interrupt(INTCODE_OP);
	continue;
  } 
 else if ((i >> 28) == 8) {   /* L */
   ad = GR[ls_rb(i)] + sign_ext(16,ls_disp16(i)) ;
   if ((ad & ~3) == SR[SYSREG_CMPR]) { /* Address compare exception */
	do_interrupt(INTCODE_CMP);
	continue;
  } 
   pgr = &GR[ls_rd_rs(i)] ;
   switch(ls_leng(i)) {
	case 0 : /* word */
	  *pgr = Mem[ad>>2] ;
	  break ;
	case 1 : /* byte */
	  *pgr = ( Mem[ad>>2] >> (24-8*(ad&3)) ) & 0xff ;
	  break ;
	case 2 : /* halfword */
	  *pgr = ( Mem[ad>>2] >> (16-8*(ad&2)) ) & 0xffff ;
	  break ;
	default : printf("bad format\n"); exit(8);
    }
   printf("   GR %2d = %8.8x\n",ls_rd_rs(i),*pgr);
  }
 else if ((i >> 28) == 9) {   /* ST */
   ad = GR[ls_rb(i)] + sign_ext(16,ls_disp16(i)) ;
   if ((ad & ~3) == SR[SYSREG_CMPR]) { /* Address compare exception */
	do_interrupt(INTCODE_CMP);
	continue;
  } 
   pgr = &GR[ls_rd_rs(i)] ;
   switch(ls_leng(i)) {
	case 0 : /* word */
	  Mem[ad>>2] = *pgr ;
	  break ;
	case 1 : /* byte */
	  mask = ((unsigned)0xff000000) >> ((ad & 3) * 8) ;
	  Mem[ad>>2] = ~mask & Mem[ad>>2] | mask & ( *pgr << (24-8*(ad&3)) ) ;
	  break ;
	case 2 : /* halfword */
	  mask = ((unsigned)0xffff0000) >> ((ad & 2) * 8) ;
	  Mem[ad>>2] = ~mask & Mem[ad>>2] | mask & ( *pgr << (16-8*(ad&2)) ) ;
	  break ;
	default : printf("bad format\n"); exit(8);
    }
   printf("Mem %8.8x = %8.8x\n",ad,Mem[ad>>2]);
  }
 else if ((i >> 31) == 0) {   /* EX */ unsigned opc,op1,op2,cc,res,intr ;
   opc = ex_exu_opc(i) ;
   if (opc >= 15) { printf("bad opcode\n"); exit(8); }
   if (ex_op2mode(i) == 1) { /* rr */
	op1 = GR[ex_rb1(i)];
	op2 = GR[ex_rs2(i)];
    } else if (ex_op2mode(i) == 3) { /* ri */
	op1 = GR[ex_rb1(i)];
	op2 = sign_ext(16,ex_imm16(i));
    } else if (ex_op2mode(i) == 2) { /* rm */
	op1 = GR[ex_rs2(i)];
	op2 = Mem[(GR[ex_rb1(i)] + sign_ext(12,ex_disp12(i))) >> 2] ;
    }
   exu(opc,op1,op2,&cc,&res,&intr);
   if (intr)	{ 		/* Overflow exception */
	do_interrupt(INTCODE_OVF);
	continue;
   } 
   if (ex_setcc(i)) { PSW_CC = cc ; printf("   CC = %d",PSW_CC); }
   if ((opc != OPC_C) && (opc != OPC_CU))  {
	GR[ex_rd(i)] = res ;
	printf("   GR %2d = %8.8x",ex_rd(i),res);
    }
   putchar('\n');
 }
 else if ((i >> 28) == 11) {   /* JB */ unsigned opc,op1,op2,cc,res ;
   if (!(  jb_cond(i) && (((8>>PSW_CC) & jb_rd_mask(i)) == 0)  )) {
	OLD_PC = PC ;
	PC = jb_reg(i) ? GR[jb_rb1(i)] + sign_ext(16,jb_imm16(i)) : 
			PC           + sign_ext(20,jb_imm20(i))   ;
	branch_taken = 1 ;
	if (jb_link(i)) { 
		GR[jb_rd_mask(i)] = OLD_PC + 4 ;
		printf("   GR %2d = %8.8x",jb_rd_mask(i),OLD_PC + 4);
    	 }
	printf("  taken\n");
    }
   else printf("  not taken\n");
  }
 else if ((i >> 28) == 12)     /* PRIV */
   switch ((i >> 24) & 15) { 
	case PRIVCODE_RFE :
		PC 	  = SR[SYSREG_XPC] ;
		PSW_CC    = pickup_cc(SR[SYSREG_XPSW]) ;
		PSW_USER  = pickup_user(SR[SYSREG_XPSW]) ;
		PSW_TYPE  = pickup_type(SR[SYSREG_XPSW]) ;
		branch_taken = 1 ;
		printf("   return to %s\n", (PSW_USER ? "user" : "kernel"));
		break ;
	case PRIVCODE_RSR :
		GR[ex_rd(i)]  = ((ex_rs2(i)!=SYSREG_PSW) ? SR[ex_rs2(i)] :
					build_psw(PSW_CC,PSW_USER,PSW_TYPE)) ;
		printf("   GR %2d = %8.8x\n", ex_rd(i), GR[ex_rd(i)]) ;
		break ;
	case PRIVCODE_WSR :
	        if (ex_rd(i)!=SYSREG_PSW) 
		  SR[ex_rd(i)]  =  GR[ex_rs2(i)] ;
	        else {
		  PSW_CC    = pickup_cc(GR[ex_rs2(i)]) ;
                  PSW_USER  = pickup_user(GR[ex_rs2(i)]) ;
                  PSW_TYPE  = pickup_type(GR[ex_rs2(i)]) ;
 		}
		printf("   SR %2d = %8.8x\n", ex_rd(i), GR[ex_rs2(i)]) ;
		break ;
    }

 if (! branch_taken) PC += 4 ;

 mynull();
 } /* end loop */
} /* end main */

int  do_interrupt(type) unsigned type ; {
 SR[SYSREG_XPC]    = PC ;
 SR[SYSREG_XPSW]   = build_psw(PSW_CC,PSW_USER,PSW_TYPE);
 PC		   = SR[SYSREG_TBR] ;
 PSW_CC    = 0 ;
 PSW_USER  = 0 ;
 PSW_TYPE  = type ;
 printf("   Interruption type = %d\n",type);
}
