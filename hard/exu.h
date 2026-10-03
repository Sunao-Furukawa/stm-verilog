
int exu(opc,x,y,pcc,pz,pintr) unsigned opc,x,y,*pcc,*pz,*pintr; {
unsigned cin=0,cc,cry0,cry1,z,sx,sy,sz,fx,fy,fz,ovf,intr=0;

switch(opc) {
 case OPC_LDW  : z = y ; cc = 0 ; break ;
 case OPC_STW  : z = x ; cc = 0 ; break ;
 case OPC_CU :
 case OPC_SU : 
 case OPC_C :
 case OPC_S : y  = ~y ; cin = 1   ;
 case OPC_AU :
 case OPC_A : 
	   fx = x & 0x7fffffff ;
	   sx = x & 0x80000000 ;
	   fy = y & 0x7fffffff ;
	   sy = y & 0x80000000 ;
	   z = fx + fy + cin ;		/* never overflows here */
	   cry1 = z & 0x80000000 ;      /* carry-in to bit<1>   */
	   cry0 = sx & sy | sy & cry1 | cry1 & sx ; /*  " <0>   */
	   z = z ^ sx ^ sy  ;
	   sz = z & 0x80000000 ;
	   ovf = cry0 ^ cry1 ;
/* printf("%8.8x,%8.8x,%8.8x\n",cry0,cry1,z); */
	   if ((opc==OPC_A)||(opc==OPC_S)||(opc==OPC_C)) {
	     if ((ovf != 0) && (opc != OPC_C)) { cc = 3 ; intr = INTCODE_OVF ; }
	       else if (  z == 0 ) cc = 0 ;
	       else if ( (sz == 0) && !ovf || (sz != 0) && ovf ) cc = 2 ;
	       else                  cc = 1 ;
	    } else { /* AU,SU,CU */
	       if ( (z == 0) && (cry0 != 0) ) cc = 0 ;
	       else if (  (cry0 == 0) ) cc = 1 ;
	       else  /* cry0 == 0x80000000 */ cc = 2 ;
	    }
	   break ;

 case OPC_N  : z = x & y ; cc = ( z == 0 ? 0 : 1 ) ; break ;
 case OPC_O  : z = x | y ; cc = ( z == 0 ? 0 : 1 ) ; break ;
 case OPC_X  : z = x ^ y ; cc = ( z == 0 ? 0 : 1 ) ; break ;

 case OPC_SL  : z = x << ( y & 0x3f ) ; cc = ( z == 0 ? 0 : 1 ) ; break ;
 case OPC_SRA  : z = ((int)x) >> ( y & 0x3f ); cc = ( z == 0 ? 0 : 1 ); break ;
 case OPC_SRL  : z = x >> ( y & 0x3f )       ; cc = ( z == 0 ? 0 : 1 ) ; break ;
 case OPC_SETHI  : z = y << 16 ;               cc = ( z == 0 ? 0 : 1 ) ; break ;

 case OPC_LDB0 : z = (y >> 24) & 0xff ; break ;
 case OPC_LDB1 : z = (y >> 16) & 0xff ; break ;
 case OPC_LDB2 : z = (y >>  8) & 0xff ; break ;
 case OPC_LDB3 : z = (y      ) & 0xff ; break ;
 case OPC_LDH0 : z = (y >> 16) & 0xffff ; break ;
 case OPC_LDH2 : z = (y      ) & 0xffff ; break ;

 case OPC_STB0 : z = ((x & 0xff) << 24) | (y & 0x00ffffff) ; break ;
 case OPC_STB1 : z = ((x & 0xff) << 16) | (y & 0xff00ffff) ; break ;
 case OPC_STB2 : z = ((x & 0xff) <<  8) | (y & 0xffff00ff) ; break ;
 case OPC_STB3 : z = ((x & 0xff)      ) | (y & 0xffffff00) ; break ;
 case OPC_STH0 : z = ((x & 0xffff) << 16) | (y & 0x0000ffff) ; break ;
 case OPC_STH2 : z = ((x & 0xffff)      ) | (y & 0xffff0000) ; break ;

} /* end switch */ 
*pz  = z ;
*pcc = cc ;
*pintr = intr ;
} /* end exu */ 
