#include <stdio.h>
#define forr(i,m,n) for (i=m;i<=n;i++)
#define MEMMIN 0x300
#define MEMMAX 0x330

FILE *fpi,*fpo; 
main(argc,argv) int argc; char **argv; {
	int found,start,loop,i,j,cur_adr,head=0; char s[90]; 
	unsigned adrs[200],data[200];
  if (argc<3) { printf("no file\n"); exit(8); }
  fpi = fopen(argv[1],"r");
  fpo = fopen(argv[2],"w");
	/* read object file */
	/* 1st line is start address */
  fgets(s,80,fpi); s[strlen(s)-1] = '\0';
  start = strtol(s,(char **)NULL,16);
	/* 2nd line is loop count    */
  fgets(s,80,fpi); s[strlen(s)-1] = '\0';
  loop  = strtol(s,(char **)NULL,16);

	/* read main part of object file */
  while (fgets(s,80,fpi) != NULL) {
    s[strlen(s)-1] = '\0';
    if (s[strlen(s)-1] == ':') cur_adr = strtol(s,(char **)NULL,16);
    else if (s[0] == '#') continue;
    else {
	adrs[head] = cur_adr;
	data[head++] = strtol(s,(char **)NULL,16);
	cur_adr += 4;
     }
   }

	/* start output */
  fprintf(fpo,"entity MEMORY is port (\n");
  fprintf(fpo," IFADIN,OPADIN,STDT  : in  bit_vector(0 to 31) ;\n");
  fprintf(fpo," WE,INIT,CK      : in  bit ;\n");
  fprintf(fpo," IFDTH,IFDTL,OPDT : out bit_vector(0 to 31)  \n");
  fprintf(fpo,"); end MEMORY;\n");
  fprintf(fpo,"architecture BEHAV of MEMORY is \n");
  fprintf(fpo,"  signal IFAD,OPAD : bit_vector(0 to 31);\n");

  forr(j,0,head-1) if(adrs[j]<MEMMIN||MEMMAX<=adrs[j]) 
    fprintf(fpo,"  signal MEM%03X : reg_vector(0 to 31) register ;\n",adrs[j]);
  for (i=MEMMIN;i<MEMMAX;i+=4) 
    fprintf(fpo,"  signal MEM%03X : reg_vector(0 to 31) register ;\n",i);
  fprintf(fpo,"   begin \n");
  fprintf(fpo,"  IFAD <= IFADIN and X\"FFFFFFF8\"; \n");
  fprintf(fpo,"  OPAD <= OPADIN and X\"FFFFFFFC\"; \n");
  fprintf(fpo,"  b1:block(CK and not CK'stable) begin\n");

	/* output code for writing memory  */
  forr(j,0,head-1) if(adrs[j]<MEMMIN||MEMMAX<=adrs[j]) oneline(adrs[j],data[j]);

  for (i=MEMMIN;i<MEMMAX;i+=4) {
    found = 0;
    forr(j,0,head-1)
      if (adrs[j]==i) { oneline(i,data[j]); found = 1; break; }
    if (!found) oneline(i,0);
   }

	/* output code for reading OP    */
  fprintf(fpo,"with OPAD select OPDT  <=\n");
  forr(j,0,head-1) if(adrs[j]<MEMMIN||MEMMAX<=adrs[j]) 
    fprintf(fpo,"\tMEM%03X when X\"%08X\",\n",adrs[j],adrs[j]);
  for (i=MEMMIN;i<MEMMAX;i+=4) 
    fprintf(fpo,"\tMEM%03X when X\"%08X\",\n",i,i);
  fprintf(fpo,"\tX\"DEAD0D0D\" when others;\n");

	/* output code for reading IFDTH */
  fprintf(fpo,"with IFAD select IFDTH <=\n");
  fprintf(fpo,"\tX\"B00%05X\" when X\"00000000\" ,\n",start);
  forr(j,0,head-1) if((adrs[j]<MEMMIN||MEMMAX<=adrs[j])&&!(adrs[j]&4)) 
    fprintf(fpo,"\tMEM%03X when X\"%08X\",\n",adrs[j],adrs[j]);
  for (i=MEMMIN;i<MEMMAX;i+=8) 
    fprintf(fpo,"\tMEM%03X when X\"%08X\",\n",i,i);
  fprintf(fpo,"\tX\"DEAD1010\" when others;\n");

	/* output code for reading IFDTL */
  fprintf(fpo,"with IFAD select IFDTL <=\n");
  forr(j,0,head-1) if((adrs[j]<MEMMIN||MEMMAX<=adrs[j])&&(adrs[j]&4)) 
    fprintf(fpo,"\tMEM%03X when X\"%08X\",\n",adrs[j],adrs[j]-4);
  for (i=MEMMIN;i<MEMMAX;i+=8) 
    fprintf(fpo,"\tMEM%03X when X\"%08X\",\n",i+4,i);
  fprintf(fpo,"\tX\"DEAD1111\" when others;\n");

  fprintf(fpo,"  end block; \n");
  fprintf(fpo," end BEHAV; \n");
/*--- debug --* 
  forr(j,0,head-1) printf("j=%3x,ad=%3x,da=%8x\n",j,adrs[j],data[j]);
*/
  return(0);
 }

int oneline(ad,dt) int ad; unsigned dt; {
  fprintf(fpo,"MEM%3X <= guarded ",ad);
  if (dt) fprintf(fpo,"X\"%08X\" when INIT else\n",dt);
  fprintf(fpo,"\tSTDT when WE and (OPAD = X\"%08x\") else MEM%3X ;\n",ad,ad);
 }

