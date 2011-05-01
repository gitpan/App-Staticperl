#! sh

"$MAKE" || exit

"$PERL_PREFIX"/bin/SP-patch-postinstall

if find blib/arch/auto -type f | grep -q -v .exists; then
   echo Probably an XS module, rebuilding perl
   if "$MAKE" all perl; then
      mv perl "$PERL_PREFIX"/bin/perl~ \
         && rm -f "$PERL_PREFIX"/bin/perl \
         && mv "$PERL_PREFIX"/bin/perl~ "$PERL_PREFIX"/bin/perl
      "$MAKE" -f Makefile.aperl map_clean
   else
      "$MAKE" -f Makefile.aperl map_clean
      exit 1
   fi
fi

"$MAKE" install UNINST=1

