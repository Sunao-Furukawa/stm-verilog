
#include "sym.dcl"
#include "y.tab.c"

#define K_FF 1
#define K_NET 2
#define K_IN 8
#define K_OUT 9
#define forr(i,m,n) for (i=m;i<=n;i++)
char triad_str[40];

main(argc,argv) int argc; char **argv; { int i,j;
	int flag = 0; struct sym *sp; char tmpstr[30],tmpstr2[30];
  printf("entity STMCNTL is port (\n  CK : in bit;\n");
  forr(j,0,MAXSYM-1) {
    sp = &symtab[j];
    if (sp->io == K_IN && sp->kind == K_FF) printf("ERROR : INVALID DECL\n");
    if (sp->io == K_IN || sp->io == K_OUT) {
      if (sp->leng > 1) sprintf(tmpstr,"_vector(0 to %d)",sp->leng - 1);
       else strcpy(tmpstr,"");
      if (flag == 0) flag++; else putchar(';');
      putchar('\n');
      printf("  %s%s : %s bit%s",(sp->io==K_OUT ? "OUT_" : ""),sp->name,
				   (sp->io==K_OUT ? "out" : "in"),tmpstr);
     }
   }
  printf("\n); end STMCNTL;\narchitecture dataflow of STMCNTL is\n");
  forr(j,0,MAXSYM-1) {
    sp = &symtab[j];
    if (sp->leng > 1) {
	sprintf(tmpstr,"_vector(0 to %d)",sp->leng - 1);
        strcpy(tmpstr2,tmpstr);
     } else {
	strcpy(tmpstr,"");
        strcpy(tmpstr2,"_bit");
     }
    if ((sp->io == K_OUT || sp->io == 0) && sp->kind == K_NET) 
      printf("  signal %s : bit%s;\n",sp->name,tmpstr);
    else if (sp->kind == K_FF) 
      printf("  signal %s : reg%s register;\n",sp->name,tmpstr2);
  }
/* FIXME: siml ends when OP-INT */
  printf("\n  begin \n"); 
  printf("d:assert (WW_INTCODE /= B\"001\") report \"OPEX\" severity ERROR;\n");
  printf("stm:  block((CK='1') and not CK'stable) begin \n");
  forr(j,0,MAXSYM-1) {
    sp = &symtab[j];
    if (sp->io == K_OUT) 
      printf("OUT_%s <= %s;\n",sp->name,sp->name);
  }
  printf("-------------- VHDL declaration ends here -------------\n");

  if (yyparse() != 0) { printf( "yyparse failed\n"); exit(222); }

  forr(j,0,MAXSYM-1) {
	strcpy(triad_str,symtab[j].name);
	triadleng(symtab[j].src,symtab[j].leng);
   }
  printf("-------------- VHDL source starts here ----------------\n");

  if (argc > 2 && !strcmp(argv[1],"-d")) 
         forr(j,0,MAXSYM-1) 
		if (!strcmp(symtab[j].name,argv[2])) {
			printf("dumping symtab[%d]:%s\n",j,symtab[j].name);
			mydump(symtab[j].src);
			exit(0);
	   	} /**/

  forr(i,0,MAXSYM-1) {
    j = stats[i];
    if (symtab[j].src == -1) {
	 printf(" -- This signal not defined\n");
	 continue;
     }
    else {
      printf("%s <= %s ",symtab[j].name,
		symtab[j].kind == K_FF ? "guarded" : "" );
      print_triad(symtab[j].src); 
      printf(";\n");
     }
   }
  printf(" end block;\nend;\n");
  return(0);
}

int print_triad(n) int n; { struct list *p;
  p = &lists[n] ;
  if (p->kind != TRIAD) print_bool(n);
  else {
		/* <OP2> when <OP1> else <OP3> */
    print_bool(lists[n].op2);
    printf(" when ");
    print_bool(lists[n].op1);
    printf(" else ");
    if (lists[p->op3].kind != TRIAD) print_bool(p->op3);
    else {
	printf("\n\t");
	print_triad(p->op3);
    }
  }
}

int print_bool(n) int n; { struct list *p,*p1,*p2;
			   struct sym *s1,*s2; int j,k;
  p = &lists[n] ;
  switch(p->kind) {
    case EQ :
    case NE :
	p1 = &lists[p->op1];
	p2 = &lists[p->op2];
	s1 = &symtab[p1->op1] ;
	if (p2->kind != CONST) {
	  /*------ sym-sym compare -------*/
	  /*if (p->kind == EQ) printf("not");
	  putchar('(');*/
	  if (p1->leng != p2->leng) { 
		printf("INVALID LENGTH ASSIGN\n");
		printf("p1.kind=%d,p1.op1=%s\n",p1->kind,symtab[p1->op1].name);
		printf("p2.kind=%d,p2.op1=%d\n",p2->kind,p2->op1);
		exit(8);
	   }
	  s2 = &symtab[p2->op1] ;
	 /* forr(j,0,p1->leng - 1) {
	    if (j!=0) printf("or");
	    printf(" %s(%d) xor %s(%d) ",s1->name,j,s2->name,j);
	    if (j%4 == 3) printf("\n\t\t");
	   }*/
	  printf(" %s %c= %s  ",s1->name,(p->kind==EQ ? ' ' : '/'),s2->name);
	} else {
	  /*------ sym-const compare -------*/
	  /*if (p->kind == NE) printf("not");
	  putchar('(');
	  forr(j,0,p1->leng - 1) {
	    if (j!=0) printf("and");
	    k = ((p2->op1) >> (p1->leng - 1 - j)) & 1 ;  /* bit J of const *
	    printf(" %s %s(%d) ",(k ? "" : "not"),s1->name,j);
	    if (j%4 == 3) printf("\n\t\t");
	   }*/
	  printf(" %s %c= ",s1->name,(p->kind==EQ ? ' ' : '/'));
	  print_atom(p->op2);
	}
	/*putchar(')');*/
        break;
    default :
	print_expr(n);
   }
}

int print_expr(n) int n; { struct list *p;
  p = &lists[n] ;
  if (p->kind != OR && p->kind != XOR && p->kind != AND && p->kind != CAT) 
	print_elem(n);
  else { putchar('('); /********** for debug *********/
    print_expr(p->op1);
    printf(" %s ", p->kind == OR  ? "or"  : p->kind == XOR ? "xor" : 
		   p->kind == AND ? "and" : "&");
    print_expr(p->op2);
         putchar(')'); /********** for debug *********/
  }
}

int print_elem(n) int n; { struct list *p;
  p = &lists[n] ;
  if (p->kind != NOT) print_atom(n);
  else {
    printf("not ");
    print_expr(p->op1);
  }
}

#define d2hex(x) ((0<=x)&&(x<=9)?x+'0':x-10+'a')

int print_atom(n) int n; { struct list *p,*p2; int m;
  p = &lists[n] ;
  switch(p->kind) {
   case SYM :
	printf("%s",symtab[p->op1].name);
	break;
   case CONST :
	if (p->leng % 4 == 0) { /* hex output */
	  printf("X\"");
	  m = p->leng / 4 - 1 ;
	  while (m>=0) printf("%x",(p->op1 >> 4*m--) & 15);
	  putchar('"');
	}
	else if ((0 < p->leng) && (p->leng < 32)) { 
	  printf("B\"");
	  m = p->leng  - 1 ;
	  while (m>=0) printf("%x",(p->op1 >> m--) & 1);
	  putchar('"');
	}
	else printf("BAD LENGTH CONSTANT\n");
	break;
   case MAC :
	printf("--- some macro ---");
	break;
   case BITFIELD :
	p2 = &lists[p->op2] ;
	if (p2->kind == ONEBIT)
	  printf("%s(%d)",symtab[p->op1].name,p2->op1);
	else if (p2->kind == BITRANGE) {
	  if (p2->op2 > 1) 
	    printf("%s(%d to %d)",symtab[p->op1].name,
		  p2->op1,p2->op1 + p2->op2 - 1);
	  else printf("%s(%d)",symtab[p->op1].name,p2->op1);
	 }
	else printf("INVALID BITFIELD\n");
	break;
   case BITRANGE :
	break;
   case PAR :
	putchar('(');
	print_bool(p->op1);
	putchar(')');
        break;
   default :
	printf("Weird thing happened!\n");
	exit(333);
  }
}

int mydump(n) int n; { struct list *p;
	int k;
 p = &lists[n];
 printf("%4d:leng=%2d,",n,p->leng);
 switch(k = p->kind) {
  case BITFIELD : 
	     printf("BIT,op1=%d,symtab[op1]=%s,op2=%d\n",
			p->op1,symtab[p->op1].name,p->op2);
		mydump(p->op2);
		break;
  case ONEBIT : 
	     printf("ONE,op1=%d\n",p->op1);
		break;
  case BITRANGE : 
	     printf("RNG,op1=%d,op2=%d\n",p->op1,p->op2);
		break;
  case SYM : printf("SYM,op1=%d,symtab[op1]=%s\n",p->op1,symtab[p->op1].name);
		break;
  case MAC :
  case CONST : printf("%s,op1=%d\n",(k==MAC ? "MAC" : "CON"),p->op1);
		break;
  case PAR :
  case NOT   : printf("%s,op1=%d\n",(k==NOT ? "NOT" : "PAR"),p->op1);
		mydump(p->op1);
		break;
  case CAT :
  case AND :
  case OR  :
  case XOR :
  case EQ  :
  case NE    : printf("%s,op1=%d,op2=%d\n",
		(k==AND ? "AND" : k==XOR ? "XOR" : k==OR  ? "OR " : 
		 k==EQ  ? "EQ " : k==NE  ? "NE " : "CAT"),p->op1,p->op2);
		mydump(p->op1);
		mydump(p->op2);
		break;
  case TRIAD : printf("TRI,op1=%d,op2=%d,op3=%d\n",p->op1,p->op2,p->op3);
		mydump(p->op1);
		mydump(p->op2);
		mydump(p->op3);
		break;
  default : printf("BAD KIND : %d\n",k);
 }
}

int triadleng(n,l) int n,l; { struct list *p;
 p = &lists[n];
 if (p->leng != -1 && p->leng != l) { 
	printf("ERROR : BAD TRIAD LENGTH in %s !\n",triad_str);
     /*	mydump(n); */
  }
 else { /* now leng is -1 or L ; if -1 , kind is CONST or TRIAD */
   p->leng = l ;
   if (p->kind == TRIAD) {
	triadleng(p->op2,l);
	triadleng(p->op3,l);
    }
  }
}
 
