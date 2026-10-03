/* head.c begin */

#include <stdio.h> 
#include <string.h> 

mynull() {}

/* for I in M to N */
#define forr(i,m,n) for(i=m;i<=n;i++)

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

#define MAXMEM (256) 
#define MAXID  (500) 
#define MAXFORM (100) 

main(argc,argv) int argc; char **argv; {
FILE *fpi,*fpo;
char c,s[90],buf[200];
int i,loopcnt,m_adr,LOOPMAX,j,k,len,lastform,random_clh;
/* unsigned IWQ[6],IWQ_A[6],IWQ_B[6],GR[16],Mem[1024]; */
unsigned GR[16],Mem[1024];
unsigned EE_ALU_CC,EE_ALU_OUTPUT,EE_ALU_INT,AA_EXU_CC,AA_EXU_OUTPUT,AA_EXU_INT;

struct {
 unsigned *loc;
 char      name[36];
 } ids[MAXID] ;

struct {
 unsigned  suf;
 unsigned  len;
 } form[MAXFORM] ;

/* head.c end */
