#! sh

# helper to apply patches after installation

patch() {
   path="$PERL_PREFIX/lib/$1"
   cache="$STATICPERL/patched/$2"
   sed="$3"

   if "$PERL_PREFIX/bin/perl" -e 'exit ((stat shift)[9] <= (stat shift)[9])' "$path" "$cache"; then
      echo "patching $path for a better tomorrrow"

      if ! sed -e "$sed" <"$path" > "$cache~"; then
         echo
         echo "*** FATAL: error while patching $path"
         echo
      else
         rm -f "$cache"
         mv "$cache~" "$cache"
         rm -f "$path"
         cp "$cache" "$path"
      fi
   fi
}

# patch CPAN::HandleConfig.pm to always include _our_ MyConfig.pm,
# not the one in the users homedirectory, to avoid clobbering his.
patch CPAN/HandleConfig.pm cpan_handleconfig_pm '
1i\
use CPAN::MyConfig; # patched by staticperl
'

# patch ExtUtils::MM_Unix to always search blib for modules
# when building a perl - this works around Pango/Gtk2 being misdetected
# as not being an XS module.
patch ExtUtils/MM_Unix.pm mm_unix_pm '
/^sub staticmake/,/^}/ s/if (@{$self->{C}}) {/if (@{$self->{C}} or $self->{NAME} =~ m%^(Pango|Gtk2)$%) { # patched by staticperl/
'

