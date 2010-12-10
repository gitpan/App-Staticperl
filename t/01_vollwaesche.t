BEGIN { $| = 1; print "1..8\n"; }

#TODO: actually ask before doing this

$PFX="/tmp/staticperltest$$";
mkdir $PFX, 0700
   or die "$PFX: $!";

END {
   system "rm -rf $PFX";
}

{
   open my $fh, ">", "$PFX/staticperlrc"
      or die "$PFX/staticperlrc: $!";
   print $fh <<EOF;
PERL_VERSION=5.8.9
STATICPERL=$PFX
PERL_OPTIMIZE="\$PERL_OPTIMIZE -O0 -g0"
EOF
}

$ENV{STATICPERLRC} = "$PFX/staticperlrc";

$DEVNULL=" >/dev/null 2>&1 </dev/null";

print qx<sh bin/staticperl version> =~ /staticperl version / ? "" : "not ", "ok 1\n";

print system ("sh bin/staticperl install $DEVNULL") ? "not " : "", "ok 2\n";
print system ("sh bin/staticperl instcpan Games::Go::SimpleBoard $DEVNULL") ? "not " : "", "ok 3\n";
print system ("sh bin/staticperl mkapp $PFX/perl.bin -MGames::Go::SimpleBoard $DEVNULL") ? "not " : "", "ok 4\n";
print system ("$PFX/perl.bin -e0 $DEVNULL") ? "not " : "", "ok 4\n";
print system ("$PFX/perl.bin -MGames::Go::SimpleBoard -e0 $DEVNULL") ? "not " : "", "ok 5\n";
print system ("sh bin/staticperl mkapp $PFX/perl.bin -MGames::Go::SimpleBoard -MPOSIX $DEVNULL") ? "not " : "", "ok 6\n";
print system ("$PFX/perl.bin -e0 $DEVNULL") ? "not " : "", "ok 7\n";
print system ("$PFX/perl.bin -MPOSIX -e0 $DEVNULL") ? "not " : "", "ok 8\n";


