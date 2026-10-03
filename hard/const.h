
/* Operand type of EX_insn : 2nd operand is immediate/register/memory */

#define EXMOD_RI  3   /* B'11' */
#define EXMOD_RR  1   /* B'01' */
#define EXMOD_RM  2   /* B'10' */

/* EXU opcode */
#define OPC_LDW  0
#define OPC_STW  4
#define OPC_A  1        /* opcode for ADD */ 
#define OPC_S  2
#define OPC_C  3 
#define OPC_AU 5 
#define OPC_SU 6 
#define OPC_CU 7
#define OPC_N  8 
#define OPC_O  9 
#define OPC_X  10 
#define OPC_SL 11
#define OPC_SRA 12 
#define OPC_SRL 13
#define OPC_SETHI 14

#define OPC_LDB0 16
#define OPC_LDB1 17
#define OPC_LDB2 18
#define OPC_LDB3 19
#define OPC_LDH0 20
#define OPC_LDH2 22
#define OPC_STB0 24
#define OPC_STB1 25
#define OPC_STB2 26
#define OPC_STB3 27
#define OPC_STH0 28
#define OPC_STH2 30

/* SU opcode */
#define SU_OPC_LD  1
#define SU_OPC_ST  2
#define SU_OPC_ST2 3

/* Privileged operation code */
#define PRIVCODE_RFE  1
#define PRIVCODE_RSR  2
#define PRIVCODE_WSR  3

/* Interruption code */
#define INTCODE_OP  1
#define INTCODE_CMP 2
#define INTCODE_TLB 3
#define INTCODE_OVF 4

/* System Register Number */
#define SYSREG_PSW	0
#define SYSREG_TBR	2
#define SYSREG_CMPR	3
#define SYSREG_XPSW	4
#define SYSREG_XPC	5
#define SYSREG_XLA	6
#define SYSREG_SVR0	8
#define SYSREG_SVR1	9

