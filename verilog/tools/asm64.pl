#!/usr/bin/perl
# soft/asm.pl のコピー。64bit perl では ~(0xffffffff << n) が 32bit を超えて
# 負の変位が壊れるため、$mask2 の計算だけ (1 << n) - 1 に修正してある。
sub mytrunc    { local($leng,$val) = @_ ;
  		 local($mask,$mask2)   = ( 0 , 0 ) ;
 $mask = 0xffffffff << (4 * $leng - 1) ;
 $mask2 = (1 << (4 * $leng)) - 1 ;
 if ($val<0) {if (($val & $mask)!=$mask) {print "label not resolved\n";exit 8;}}
   else      {if (($val & $mask)!=  0  ) {print "label not resolved\n";exit 8;}}
 $val & $mask2 ;
}
sub signed_hex { local($leng,$str) = @_ ;
  		 local($retval,$mask,$mask2)   = ( 0 , 0 , 0 ) ;
 $mask = 0xffffffff << (4 * $leng - 1) ;
 $mask2 = (1 << (4 * $leng)) - 1 ;
 if (substr($str,0,1) eq "-") {
  $retval = hex(substr($str,1)) * (-1) ;
  if (($retval & $mask) != $mask) { print "Value of $str is bad\n"; exit 8; }
 } else {
  $retval = hex($str) ;
  if (($retval & $mask) !=   0  ) { print "Value of $str is bad\n"; exit 8; }
 }
 $retval & $mask2 ;
}

$asm = $ARGV[0] ;
%labels = () ;
$ad = 0 ; $MAIN = 0 ; $CYCLES = (($#ARGV == 1) ? $ARGV[1] : 100) ;
%OPC_ARY = ( "A",1 ,"S",2 ,"C",3,"AU",5 ,"SU",6 ,"CU",7,"N",8 ,"O",9 ,"X",10 ,
             "SL",11 ,"SRA",12 ,"SRL",13  ) ;
%MASK_ARY = ( "E",8 ,"L",4 ,"G",2,"LE",12 ,"GE",10 ,"NE",6 ) ;

open(ASM , "< $asm") || die "cannot open $asm" ;
while (<ASM>) {
 s/#.*// ;
 if    (/EQU\s+([0-9A-Fa-f]+)/) { $ad = hex($1) ; }		# EQU
 elsif (/(\w+):/) {$labels{$1} = $ad;  if ($1 eq "main") {$MAIN = $ad;}}# label
 elsif (
/^(([ASC]U?|[NOX]|S[RL][AL]?)(.c)?|(L|ST)(.[bh])?|B(|AL|GE?|E|LE?|NE)|JA?L?)\s/
  )	{ $ad += 4 ; }	# insn
 elsif (/USING/) 	      {}				# USING
 elsif (/^([0-9A-Fa-f]+$)/   ) { 				# data
	$ad += length($1)/2 ;
	if (length($1)%8 != 0) { print "data not multiple of 4B\n"; exit 8; }
  }
} # end while-1
close(ASM);

printf "%x\n%d\n", $MAIN , $CYCLES ;
foreach ( keys %labels ) { printf "# %5s=%6x\n",$_,$labels{$_};}

open(ASM , "< $asm") || die "cannot open $asm" ;
while (<ASM>) {
s/#.*// ;
$is_insn = 1 ;
	# comment : do nothing
if (/^#/) {	$is_insn = 0 ; }

	# Privileged insn
elsif ( /([RW])SR\s+(\d+)\s*,\s*(\d+)/ ) {  # RSR 3,14 -> C230E000
 if ($1 eq "R") { print "C2"; } else { print "C3"; }
 printf "%x0%x000\n" , $2 , $3 ;
}
elsif (/RFE/) { print "C1000000\n" ; }

	# LS-insn 
elsif  (/^(L|ST)(\.[bh])?\s+(\d+)\s*,\s*(.*)/) {
 print (($1 eq "L") ? '8' : '9' );				# OPCODE
 print (($2 eq ".b") ? '1' : ( ($2 eq ".h") ? '2' : '0' )) ;	# LENG
 printf "%x",$3 ;						# RD
 $MEMOP = $4 ;
 if ($MEMOP =~ /(\d+)\((-?[0-9A-Za-f]+)\)/) { # w/o label, like "L 3,6(840)"
    	printf "%x%4.4x\n", $1 , &signed_hex(4,$2)  ; 		# RB,DISP
 } elsif ($MEMOP =~ /(\w+)/ ) {            # w/  label , like  "ST.b  3,LBL1"
 	printf "%x%4.4x\n", $BASEREG , &mytrunc(4,$labels{$1} - $BASEVAL)  ;
 }
}
	# EX-insn
elsif ( /([ASC]U?|[NOX]|S[RL][AL]?)(\.c)?\s+((\d+)\s*,)?\s*(\d+)\s*,\s*(.*)/ ) {
         #-----------OPC---------- SETCC      RD            RS1         OP2
   # like "A.c 3,9,<op2>"
 $SETCC =    ((($2 eq ".c")||($1 eq "C")|| ($1 eq "CU")) ? 1 : 0 ) ;
 $OPCODE =  $OPC_ARY{$1} ;
 if ((($1 eq "C")|| ($1 eq "CU"))&&($3 ne "")) { print "bad format\n"; exit 8;}
 $RD =  ((($1 eq "C")|| ($1 eq "CU")) ? 0 : $4 ) ;
 $RS1 = $5 ; $RB_ETC = $6 ;

 if      ($RB_ETC =~ /%(-?[0-9A-Fa-f]+)/) {		# ri-mode (OP2MODE = 3)
   printf("%x%x%x", 6 + $SETCC , $OPCODE , $RD); 	# S.c 3,9,%ec47
   printf "%x%4.4x\n", $RS1 , &signed_hex(4,$1); 	#R1,IMM

 } elsif ($RB_ETC =~ /(\d+)\((-?[0-9A-Fa-f]+)\)/) {	# rm-mode (OP2MODE = 2)
   printf("%x%x%x", 4 + $SETCC , $OPCODE , $RD); 	# S.c 3,9,10(d31)
   printf "%x%x%3.3x\n", $1 , $RS1 , &signed_hex(3,$2); # RB , RS ,DISP12

 } elsif ($RB_ETC =~ /^(\d+)\s*$/) {			# rr-mode (OP2MODE = 1)
   printf("%x%x%x", 2 + $SETCC , $OPCODE , $RD); 	# S.c 3,9,14
   printf "%x%x000\n", $RS1 ,     $1   ;		# R1 , R2

 } elsif ($RB_ETC =~ /(\w+)/) 	   {		# rm-mode (OP2MODE = 2) w/label
   printf("%x%x%x", 4 + $SETCC , $OPCODE , $RD); 	# S.c 3,9,10(d31)
   printf("%x%x%3.3x\n",$BASEREG,$RS1,&mytrunc(3,$labels{$1}-$BASEVAL)); 
							# RB,RS,DISP12
 }
}
elsif  (/SETHI\s+(\d+)\s*,\s*%(-?[0-9A-Fa-f]+)/) {	# SETHI
   printf "6E%x0%4.4x\n", $1 , &signed_hex(4,$2); 	#RD,IMM
}
	# JB-insn
elsif ( /B(AL|E|L|G|[LGN]E)?\s+((\d+)\s*,\s*)?(.*)/)  {	   	# branch
 if    ($1 eq "")   { print  "B00" ;     }		# "B     %4e4"
 elsif ($1 eq "AL") { printf "B2%x",$3 ; }		# "BAL   L1   "
 else               { printf "B8%x",$MASK_ARY{$1}; } # E|L|G|LE|GE|NE  "BNE L2"
 $tgt = $4 ;
 if ($tgt =~ /%(-?[0-9A-Fa-f]+)/) {printf "%5.5x\n",&signed_hex(5,$1);} # %-b34
 elsif ($tgt =~ /(\w+)/) {printf("%5.5x\n",&mytrunc(5,$labels{$1} - $ad));} #L1
}
elsif ( /J(A?L?)\s+((\d+)\s*,\s*)?(.*)/)  { # jump like "J  L1","JAL  3,9(54)"
 if ($1 eq "AL") { printf "B6%x",$3 ; }
 else		{ print  "B40" ;     }
 $tgt = $4 ;
 if ($tgt =~ /(\d+)\((-?[0-9A-Fa-f]+)\)/)  	# 15(b34)
	{ printf("%x%4.4x\n",$1,&signed_hex(4,$2)) ; }
 elsif ($tgt =~ /(\w+)/)  			# L1
	{ printf("%x%4.4x\n",$IBASEREG, &mytrunc(4,$labels{$1} - $IBASEVAL)) ;}
}
elsif (/USING_I\s+(\d+)\s*,\s*(\w+)/) {		# USING_I 14,3a8
 $is_insn = 0 ; $IBASEREG = $1 ; $IBASEVAL = hex($2);
} 
elsif (/USING\s+(\d+)\s*,\s*(\w+)/) {		# USING 14,3a8
 $is_insn = 0 ; $BASEREG = $1 ; $BASEVAL = hex($2);
}
elsif (/EQU\s+(\w+)/)  { 			# EQU 3ac
 $is_insn = 0 ; $ad      = hex($1) ; print $1,":\n"; 
}
elsif (/^[0-9A-Fa-f]+\s*(#.*)?$/)  { 			# data
 $is_insn = 0 ; $ad      = length($1)/2 ; print ; 
} 
else { $is_insn = 0 ; } 		# label, null, ..

if ($is_insn == 1) { $ad += 4 ;}
} # end while-2
close(ASM);
