%%
[0-9]+			{ 
			  now_sym = 0 ;
			  yylval = strtol(yytext,(char **)NULL,10); 
			  constleng = -1 ;
			  return(CONST);
			}
(0x|0X)[0-9A-Fa-f]+	{ 
			  now_sym = 0 ;
			  yylval = strtol(yytext,(char **)NULL,16); 
			  constleng = -1 ;
			  return(CONST);
			}
B\"[01]*\"		{ 
			  now_sym = 0 ;
			  constleng = yyleng - 3 ;
			  strncpy(tmpstr,yytext+2,constleng);
			  yylval = strtol(tmpstr,(char **)NULL,2); 
			  return(CONST);
			}
X\"[0-9A-Fa-f]*\"	{ 
			  now_sym = 0 ;
			  constleng = 4 * (yyleng - 3) ;
			  strncpy(tmpstr,yytext+2,yyleng-3);
			  yylval = strtol(tmpstr,(char **)NULL,16); 
			  return(CONST);
			}
[A-Za-z][A-Za-z0-9_]*	{ 
			  now_sym = 1 ;
			  prev_sym = now_sym ;
			  prev_lval = yylval  ;
			  if ((yylval = symsearch(yytext)) > MAXSYM) {
			    printf("ERROR : symbol not defined : %s\n",yytext);
			   }
			  return(SYM);
			}
:=	 	{ now_sym = 0 ; return(ASSI); }
==	 	{ now_sym = 0 ; return(EQ); }
!=		{ now_sym = 0 ; return(NE); }
[!&|()?:=,^\[\]\.]	{ now_sym = 0 ; return((int)yytext[0]); }
%%
#include <stdio.h>

int symsearch(s) char *s; { int i;
  for (i=0;i<MAXSYM;i++) 
    if (!strcmp(s,symtab[i].name)) return(i);
  return(MAXSYM+1);
}
