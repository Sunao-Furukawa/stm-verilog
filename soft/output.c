
/* output.c begin */

k = 0 ;
forr(j,0,lastform) 
 if ((len=form[j].len)==0) buf[k++] = ' ';
 else { unsigned val; int m;
   val = *(ids[form[j].suf].loc) ;
   /* for (m=len-1;m--;m>=0) buf[k++] = d2hex(((val >> (4*m)) & 15)) ; */
   m=len-1;
   while (m>=0) {
     buf[k++] = d2hex(((val >> (4*m)) & 15)) ;
     m--;
   }
 }
buf[k] = '\n';
fputs(buf,fpo);

/* Here is just before updating FF */
/* With dbx, you can use "stop at mynull" */
mynull();

/* If diag-insn detected, end simulation */
if ((Mem[PC>>2] >> 28) == 13) exit(0);

/* output.c end   */

