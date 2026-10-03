#! /usr/local/bin/perl
@ARGV_0 = @ARGV ;
$L_NOCOLON	= 1 ;	$L_PROPAG 	= 2 ; $L_ASSIGN 	= 3 ;
$L_IF_PROPAG 	= 4 ; $L_IF_ASSIGN 	= 5 ; $L_CONT      	= 6 ;

$TMP    = "/tmp"   ;        $D_EXEC = "$TMP/exec_mid" ;
$D_PROP = "$TMP/prop_mid" ; $D_ASSI = "$TMP/assi_mid" ;

sub mk_prop_assi { local($x) = @_ ;

$D_PROP2 = "$TMP/net.$x" ; $D_ASSI2 = "$TMP/FF.$x" ;
open(F_PROP,"> $D_PROP"); open(F_ASSI,"> $D_ASSI"); open(F_EXEC,"> $D_EXEC");
open(F_IN  ,"< $x");

$prev 	= "" ; $line_kind_prev	= $L_NOCOLON ;

while (<F_IN>) {
					# Handle comment ('#') but not cpp-lines
 s/^#$// ;
 s+#([^di].*)$+/*$1*/+ ;		# "** # XXXX\n" -> "** /* XXXX */\n"
 s/-/_/g ;				# Change hyphens to underbars
 s/\selif\s/ else if /g ;		# Change elif    to else if
 s/^elif\s/else if /g ;	
 $cur = $_ ;

if ( /^#/ || /^\s*$/ || /^\s*\/\*.*\*\/\s*$/ ||	   
    ( /^if\s/ || /\sif\s/ || /^else\s/ || /\selse\s/ || /}/ ) && !/\s:?=\s/) {
	# cpp, null, comment lines , or  if/else statement without '=' or ':=' 
	  $line_kind = $L_NOCOLON; 

} elsif (/(.*{.*\s=\s.*)(}.*$)/) {	# { XX = YY }
					# declare XX as net (in file F_PROP)
	  $cur = $1.";".$2."\n" ;
	  $line_kind = $L_IF_PROPAG; 
	  if (/\s(\w+)\s*=\s/) { print F_PROP $1."\n" ; }

} elsif (/(.*{.*\s:=\s.*)(}.*$)/) {	# { XX := YY }
					# declare XX as FF (in file F_ASSI)
	  $cur = $1.";".$2."\n" ;
	  $line_kind = $L_IF_ASSIGN; 
	  if (/\s(\w+)\s*:=\s/) { print F_ASSI $1."\n" ; }
	  if (!($cur =~ /\]\s*:=/)) { $cur =~ s/(\w+)\s+:=\s/$1_NEW = / ; }
	  else 			    { $cur =~ s/:=/=/ ; } # GR, Mem etc.

} elsif (/\s=\s/) {			# XX = YY
					# declare XX as net
	  $line_kind = $L_PROPAG; 
	  $save = $_ ;
	  while (/\s*(\w+)\s*=\s(.*)/) {
		print F_PROP $1."\n" ;
		$_ = $2 ;
	   }
	  $_ = $save ;

} elsif (/\s:=\s/) {			# XX := YY
					# declare XX as FF 
	  $line_kind = $L_ASSIGN; 
	  $save = $_ ;
	  while (/\s*(\w+)\s*:=\s(.*)/) {
		print F_ASSI $1."\n" ;
		$_ = $2 ;
	   }
	  $_ = $save ;
	  if (!($cur =~ /\]\s*:=/)) { $cur =~ s/(\w+)\s+:=\s/$1_NEW = /g ; }
	  else			    { $cur =~ s/:=/=/ ; } # GR, Mem etc.

} else             { 			# probably a continuation of
					# propagation or assignment statement
	  $line_kind = $L_CONT     ; 
}

if (($line_kind_prev == $L_NOCOLON) || 
    ($line_kind_prev == $L_IF_PROPAG) || 
    ($line_kind_prev == $L_IF_ASSIGN) || 
    ($line_kind      == $L_CONT   )     ) { print F_EXEC $prev ; }
else {  # prev == L_PROPAG, L_ASSIGN, or L_CONT ; cur != L_CONT
  $_ = $prev ; s/$/;/    ; $prev = $_ ;
  print F_EXEC $prev ;
}

$prev = $cur ; $line_kind_prev = $line_kind ;
} # end while
close(F_IN);

$cur = "" ;
$line_kind      = $L_NOCOLON ;

if (($line_kind_prev == $L_NOCOLON) || 
    ($line_kind_prev == $L_IF_PROPAG) || 
    ($line_kind_prev == $L_IF_ASSIGN) || 
    ($line_kind      == $L_CONT   )     ) { print F_EXEC $prev ; }
else {  # prev == L_PROPAG, L_ASSIGN, or L_CONT ; cur != L_CONT
  $_ = $prev ; s/$/;/    ; $prev = $_ ; print F_EXEC $prev ;
}
close(F_PROP) ; close(F_ASSI) ; close(F_EXEC) ;
system( "sort -u $D_PROP > $D_PROP2 " ) ; # sort and make net names unique
system( "sort -u $D_ASSI > $D_ASSI2 " ) ; # sort and make FF  names unique
}
foreach $maker (@ARGV_0) {
  open(F_XR,"> $TMP/xr.$maker");
  print F_XR "----------------------------- source file = $maker --------\n" ;
  &mk_prop_assi($maker);

  foreach $net_or_ff ("net","FF") {
    print F_XR "================================ begin $net_or_ff === \n" ;
    open (F_SIGNALS,"< $TMP/$net_or_ff.$maker");
    while (<F_SIGNALS>) {
      chop ; $signal = $_ ; $signal_found = 0 ;
      $before = 1 ;
      foreach $user (@ARGV_0) {
        if ($maker ne $user)  {
          open (F_USER,"< $user");    $user_found = 0 ;
          while (<F_USER>) {
		s/-/_/g; 
		if (/$signal/) { 
		   $user_found = $signal_found = 1 ; print F_XR $_ ; 
		   if (($before == 1) && ($net_or_ff eq "net")) 
			{ print F_XR "!!!!!!!!! SEQUENCE ERROR !!!!!!!!!\n" ; }
		 }
	   }
          close(F_USER);
          if ($user_found == 1) { print F_XR "  --- y = $user \n"; }
         } else { $before = 0 ; }
       }  # foreach user
      if ($signal_found == 1) { print F_XR "signal = $signal \n" ; }
     }  # while 
    close(F_SIGNALS);
   }  # foreach net_or_ff
  close(F_XR);
 }  # foreach maker
