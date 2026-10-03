
/* mid.c begin */

/* miscellaneous initializations */

/* START_TRIGGER = 1; */
/* NIP_A = NIP_A_NEW  = 6; */
random_clh = ((argc > 1) && !strcmp(argv[1],"-r") ? 1 : 0) ;

/* reading memory file */
/* format of file "mem.dat" : 

    start insn adrs (in hex)
    loop count      (in dec)
    adr:            (in hex)
    data/insn       (in hex)

like
   
10c0
100
10c0:
7a45f03b
00001000
# This is a comment. 
1458:
349c8f4d
  :

*/

fpi = fopen("mem.dat","r");
fgets(s,80,fpi);	/* first line is start-pc */
PC = PC_NEW = hex2d(s);	/* hex2d does not need chopping-off */
fgets(s,80,fpi);        /* second line is loop count */
s[strlen(s)-1] = '\0' ;  /* chop off CR */
LOOPMAX = atoi(s);
while (fgets(s,80,fpi) != NULL) 
  if(s[strlen(s)-2] == ':') m_adr = hex2d(s) / 4 ;
  else if(s[0] == '#')      continue  ;
  else                      Mem[m_adr++] = hex2d(s);
fclose(fpi) ;

/* reading siml format file */

/*  format of this file is :

E_REL,1
#   This is a comment
*
AA_ALU_OUTPUT,8
  :
*/
/*

	loc	name                      suf	len
     +------+-----------+              +------+------+
     | *uns | char[28]  |        +-----|- *   | 0..8 |
     +------+-----------+        |     +------+------+
     |      |           | <------+     |      |      |
     +------+-----------+              +------+------+
     |      |           |              |      |      |
     +------+-----------+              +------+------+
*/

fpi = fopen("form.dat","r");
i = 0 ;
while (fgets(s,80,fpi) != NULL) 
 if (s[0]=='*') form[i++].len = 0 ;
 else if (s[0]=='#') continue;
 else {
   form[i].len = s[strlen(s)-2] - '0' ;
   s[strlen(s)-3] = '\0' ;
   forr(j,0,MAXID-1) 
     if (strcmp(ids[j].name,s) == 0) { form[i++].suf = j; break; }
   if (j == MAXID) { printf("net name #%s# not found\n",s); exit(8); }
  }
lastform = i - 1 ;

/* output net names to result file */
fpo = fopen("siml.res","w");

forr(j,0,15) { int k,m;
  k = 0;
  forr(i,0,lastform) {
   c=ids[form[i].suf].name[j] ;
   if (form[i].len == 0) buf[k++]=' ';
   else {
     buf[k++] = ( (isalnum(c)||(c=='_')) ? c : ' ' ); 
     if (form[i].len >= 2) forr(m,2,form[i].len) buf[k++] =  ' ' ; 
    }
  }
  buf[k] = '\n';
  buf[k+1] = '\0';  /* ???? Do we need this? */
  fputs(buf,fpo);
 }

/* start main loop of simulation */

forr(loopcnt,1,LOOPMAX) {

/* mid.c end */
