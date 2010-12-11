#!/bin/sh

#############################################################################
# configuration to fill in

STATICPERL=~/.staticperl
CPAN=http://mirror.netcologne.de/cpan # which mirror to use
EMAIL="read the documentation <rtfm@example.org>"

# perl build variables
PERL_VERSION=5.12.2 # 5.8.9 is also a good choice
PERL_CONFIGURE="" # additional Configure arguments
PERL_CPPFLAGS="-DPERL_DISABLE_PMC -DPERL_ARENA_SIZE=65536 -D_GNU_SOURCE -DNDEBUG -USITELIB_EXP -USITEARCHEXP -UARCHLIB_EXP"
PERL_OPTIMIZE="-Os -ffunction-sections -fdata-sections -finline-limit=8 -ffast-math"

ARCH="$(uname -m)"

case "$ARCH" in
   i*86 | x86_64 | amd64 )
      PERL_OPTIMIZE="$PERL_OPTIMIZE -mpush-args -mno-inline-stringops-dynamically -mno-align-stringops -mno-ieee-fp" # x86/amd64
      case "$ARCH" in
         i*86 )
            PERL_OPTIMIZE="$PERL_OPTIMIZE -fomit-frame-pointer -march=pentium3 -mtune=i386" # x86 only
            ;;
      esac
      ;;
esac

# -Wl,--gc-sections makes it impossible to check for undefined references
# for some reason so we need to patch away the "-no" after Configure and before make :/
# --allow-multiple-definition exists to work around uclibc's pthread static linking bug
PERL_LDFLAGS="-Wl,--no-gc-sections -Wl,--allow-multiple-definition"
PERL_LIBS="-lm -lcrypt" # perl loves to add lotsa crap itself

# some configuration options for modules
export PERL_MM_USE_DEFAULT=1
#export CORO_INTERFACE=p # needed without nptl on x86, due to bugs in linuxthreads - very slow
export EV_EXTRA_DEFS='-DEV_FEATURES=4+8+16+64 -DEV_USE_SELECT=0 -DEV_USE_POLL=1 -DEV_USE_EPOLL=1 -DEV_NO_LOOPS -DEV_COMPAT3=0'

# which extra modules to install by default from CPAN that are
# required by mkbundle
STATICPERL_MODULES="common::sense Pod::Strip PPI::XS Pod::Usage"

# which extra modules you might want to install
EXTRA_MODULES=""

# overridable functions
preconfigure()  { : ; }
postconfigure() { : ; }
postbuild()     { : ; }
postinstall()   { : ; }

# now source user config, if any
if [ "$STATICPERLRC" ]; then
   . "$STATICPERLRC"
else
   [ -r /etc/staticperlrc ] && . /etc/staticperlrc
   [ -r ~/.staticperlrc   ] && . ~/.staticperlrc
   [ -r "$STATICPERL/rc"  ] && . "$STATICPERL/rc"
fi

#############################################################################
# support

MKBUNDLE="${MKBUNDLE:=$STATICPERL/mkbundle}"
PERL_PREFIX="${PERL_PREFIX:=$STATICPERL/perl}" # where the perl gets installed

unset PERL5OPT PERL5LIB PERLLIB PERL_UNICODE PERLIO_DEBUG 
export LC_ALL=C # just to be on the safe side

# set version in a way that Makefile.PL can extract
VERSION=VERSION; eval \
$VERSION=0.911

BZ2=bz2
BZIP2=bzip2

fatal() {
   printf -- "\nFATAL: %s\n\n" "$*" >&2
   exit 1
}

verbose() {
   printf -- "%s\n" "$*"
}

verblock() {
   verbose
   verbose "***"
   while read line; do
      verbose "*** $line"
   done
   verbose "***"
   verbose
}

rcd() {
   cd "$1" || fatal "$1: cannot enter"
}

trace() {
   prefix="$1"; shift
#   "$@" 2>&1 | while read line; do
#      echo "$prefix: $line"
#   done
   "$@"
}

trap wait 0

#############################################################################
# clean

distclean() {
   verblock <<EOF
   deleting everything installed by this script (rm -rf $STATICPERL)
EOF

   rm -rf "$STATICPERL"
}

#############################################################################
# download/configure/compile/install perl

clean() {
   rm -rf "$STATICPERL/src/perl-$PERL_VERSION"
}

fetch() {
   rcd "$STATICPERL"

   mkdir -p src
   rcd src

   if ! [ -d "perl-$PERL_VERSION" ]; then
      if ! [ -e "perl-$PERL_VERSION.tar.$BZ2" ]; then

         URL="$CPAN/src/5.0/perl-$PERL_VERSION.tar.$BZ2"

         verblock <<EOF
downloading perl
to manually download perl yourself, place
perl-$PERL_VERSION.tar.$BZ2 in $STATICPERL
trying $URL
EOF

         rm -f perl-$PERL_VERSION.tar.$BZ2~ # just to be on the safe side
         wget -O perl-$PERL_VERSION.tar.$BZ2~ "$URL" \
            || curl >perl-$PERL_VERSION.tar.$BZ2~ "$URL" \
            || fatal "$URL: unable to download"
         mv perl-$PERL_VERSION.tar.$BZ2~ perl-$PERL_VERSION.tar.$BZ2
      fi

      verblock <<EOF
unpacking perl
EOF

      mkdir -p unpack
      $BZIP2 -d <perl-$PERL_VERSION.tar.bz2 | tar xfC - unpack \
         || fatal "perl-$PERL_VERSION.tar.bz2: error during unpacking"
      chmod -R u+w unpack/perl-$PERL_VERSION
      mv unpack/perl-$PERL_VERSION perl-$PERL_VERSION
      rmdir -p unpack
   fi
}

# similar to GNU-sed -i or perl -pi
sedreplace() {
   sed -e "$1" <"$2" > "$2~" || fatal "error while running sed"
   mv "$2~" "$2"
}

configure() {
   fetch

   rcd "$STATICPERL/src/perl-$PERL_VERSION"

   [ -e staticstamp.configure ] && return

   verblock <<EOF
configuring $STATICPERL/src/perl-$PERL_VERSION
EOF

   rm -f "$PERL_PREFIX/staticstamp.install"

   make distclean >/dev/null 2>&1

   # I hate them
   grep -q -- -fstack-protector Configure && \
      sedreplace 's/-fstack-protector/-fno-stack-protector/g' Configure

   preconfigure

#   trace configure \
   sh Configure -Duselargefiles \
                -Uuse64bitint \
                -Dusemymalloc=n \
                -Uusedl \
                -Uusethreads \
                -Uuseithreads \
                -Uusemultiplicity \
                -Duseperlio \
                -Uusesfio \
                -Uuseshrplib \
                -Dcppflags="$PERL_CPPFLAGS" \
                -Dccflags="-g2 -fno-strict-aliasing" \
                -Doptimize="$PERL_OPTIMIZE" \
                -Dldflags="$PERL_LDFLAGS" \
                -Dlibs="$PERL_LIBS" \
                -Dprefix="$PERL_PREFIX" \
                -Dbin="$PERL_PREFIX/bin" \
                -Dprivlib="$PERL_PREFIX/lib" \
                -Darchlib="$PERL_PREFIX/lib" \
                -Uusevendorprefix \
                -Dsitelib="$PERL_PREFIX/lib" \
                -Dsitearch="$PERL_PREFIX/lib" \
                -Usitelibexp \
                -Uman1dir \
                -Uman3dir \
                -Usiteman1dir \
                -Usiteman3dir \
                -Dpager=/usr/bin/less \
                -Demail="$EMAIL" \
                -Dcf_email="$EMAIL" \
                -Dcf_by="$EMAIL" \
                $PERL_CONFIGURE \
                -dE || fatal "Configure failed"

   sedreplace '
      s/-Wl,--no-gc-sections/-Wl,--gc-sections/g
      s/ *-fno-stack-protector */ /g
   ' config.sh

   sh Configure -S || fatal "Configure -S failed"

   postconfigure || fatal "postconfigure hook failed"

   touch staticstamp.configure
}

build() {
   configure

   rcd "$STATICPERL/src/perl-$PERL_VERSION"

   verblock <<EOF
building $STATICPERL/src/perl-$PERL_VERSION
EOF

   rm -f "$PERL_PREFIX/staticstamp.install"

   make || fatal "make: error while building perl"

   postbuild || fatal "postbuild hook failed"
}

install() {
   if ! [ -e "$PERL_PREFIX/staticstamp.install" ]; then
      build

      verblock <<EOF
installing $STATICPERL/src/perl-$PERL_VERSION
to $PERL_PREFIX
EOF

      ln -sf "perl/bin/" "$STATICPERL/bin"
      ln -sf "perl/lib/" "$STATICPERL/lib"

      ln -sf "$PERL_PREFIX" "$STATICPERL/perl" # might get overwritten
      rm -rf "$PERL_PREFIX"                    # by this rm -rf

      make install || fatal "make install: error while installing"

      rcd "$PERL_PREFIX"

      # create a "make install" replacement for CPAN
      cat >"$PERL_PREFIX"/bin/cpan-make-install <<EOF
make || exit

if find blib/arch/auto -type f | grep -q -v .exists; then
   echo Probably an XS module, rebuilding perl
   if make perl; then
      mv perl "$PERL_PREFIX"/bin/perl
      make -f Makefile.aperl map_clean
   else
      make -f Makefile.aperl map_clean
      exit 1
   fi
fi

make install UNINST=1
EOF
      chmod 755 "$PERL_PREFIX"/bin/cpan-make-install

      # trick CPAN into avoiding ~/.cpan completely
      echo 1 >"$PERL_PREFIX/lib/CPAN/MyConfig.pm"

      "$PERL_PREFIX"/bin/perl -MCPAN -e '
         CPAN::Shell->o (conf => urllist => push => "'"$CPAN"'");
         CPAN::Shell->o (conf => q<cpan_home>, "'"$STATICPERL"'/cpan");
         CPAN::Shell->o (conf => q<init>);
         CPAN::Shell->o (conf => q<cpan_home>, "'"$STATICPERL"'/cpan");
         CPAN::Shell->o (conf => q<build_dir>, "'"$STATICPERL"'/cpan/build");
         CPAN::Shell->o (conf => q<prefs_dir>, "'"$STATICPERL"'/cpan/prefs");
         CPAN::Shell->o (conf => q<histfile> , "'"$STATICPERL"'/cpan/histfile");
         CPAN::Shell->o (conf => q<keep_source_where>, "'"$STATICPERL"'/cpan/sources");
         CPAN::Shell->o (conf => q<make_install_make_command>, "'"$PERL_PREFIX"'/bin/cpan-make-install");
         CPAN::Shell->o (conf => q<prerequisites_policy>, q<follow>);
         CPAN::Shell->o (conf => q<build_requires_install_policy>, q<no>);
         CPAN::Shell->o (conf => q<commit>);
      ' || fatal "error while initialising CPAN"

      touch "$PERL_PREFIX/staticstamp.install"
   fi

   if ! [ -e "$PERL_PREFIX/staticstamp.postinstall" ]; then
      NOCHECK_INSTALL=+
      instcpan $STATICPERL_MODULES
      [ $EXTRA_MODULES ] && instcpan $EXTRA_MODULES

      postinstall || fatal "postinstall hook failed"

      touch "$PERL_PREFIX/staticstamp.postinstall"
   fi
}

#############################################################################
# install a module from CPAN

instcpan() {
   [ $NOCHECK_INSTALL ] || install

   verblock <<EOF
installing modules from CPAN
$@
EOF

   for mod in "$@"; do
      "$PERL_PREFIX"/bin/perl -MCPAN -e 'notest install => "'"$mod"'"' \
         || fatal "$mod: unable to install from CPAN"
   done
   rm -rf "$STATICPERL/build"
}

#############################################################################
# install a module from unpacked sources

instsrc() {
   [ $NOCHECK_INSTALL ] || install

   verblock <<EOF
installing modules from source
$@
EOF

   for mod in "$@"; do
      echo
      echo $mod
      (
         rcd $mod
         make -f Makefile.aperl map_clean >/dev/null 2>&1
         make distclean >/dev/null 2>&1
         "$PERL_PREFIX"/bin/perl Makefile.PL || fatal "$mod: error running Makefile.PL"
         make || fatal "$mod: error building module"
         "$PERL_PREFIX"/bin/cpan-make-install || fatal "$mod: error installing module"
         make distclean >/dev/null 2>&1
         exit 0
      ) || exit $?
   done
}

#############################################################################
# main

podusage() {
   echo
   if [ -e "$PERL_PREFIX/bin/perl" ]; then
      "$PERL_PREFIX/bin/perl" -MPod::Usage -e \
         'pod2usage -input => *STDIN, -output => *STDOUT, -verbose => '$1', -exitval => 0, -noperldoc => 1' <"$0" \
         2>/dev/null && exit
   fi
   # try whatever perl we can find
   perl -MPod::Usage -e \
      'pod2usage -input => *STDIN, -output => *STDOUT, -verbose => '$1', -exitval => 0, -noperldoc => 1' <"$0" \
      2>/dev/null && exit

   fatal "displaying documentation requires a working perl - try '$0 install' first"
}

usage() {
   podusage 0
}

catmkbundle() {
   {
      read dummy
      echo "#!$PERL_PREFIX/bin/perl"
      cat
   } <<'MKBUNDLE'
#CAT mkbundle
MKBUNDLE
}

bundle() {
   catmkbundle >"$MKBUNDLE~" || fatal "$MKBUNDLE~: cannot create"
   chmod 755 "$MKBUNDLE~" && mv "$MKBUNDLE~" "$MKBUNDLE"
   CACHE="$STATICPERL/cache"
   mkdir -p "$CACHE"
   "$PERL_PREFIX/bin/perl" -- "$MKBUNDLE" --cache "$CACHE" "$@"
}

if [ $# -gt 0 ]; then
   while [ $# -gt 0 ]; do
      mkdir -p "$STATICPERL" || fatal "$STATICPERL: cannot create"
      mkdir -p "$PERL_PREFIX" || fatal "$PERL_PREFIX: cannot create"

      command="${1#--}"; shift
      case "$command" in
         version )
            echo "staticperl version $VERSION"
            ;;
         fetch | configure | build | install | clean | distclean)
            ( "$command" )
            ;;
         instsrc )
            ( instsrc "$@" )
            exit
            ;;
         instcpan )
            ( instcpan "$@" )
            exit
            ;;
         cpan )
            ( install )
            "$PERL_PREFIX/bin/cpan" "$@"
            exit
            ;;
         mkbundle )
            ( install )
            bundle "$@"
            exit
            ;;
         mkperl )
            ( install )
            bundle --perl "$@"
            exit
            ;;
         mkapp )
            ( install )
            bundle --app "$@"
            exit
            ;;
         help )
            podusage 2
            ;;
         * )
            exec 1>&2
            echo
            echo "Unknown command: $command"
            podusage 0
            ;;
      esac
   done
else
   usage
fi

exit 0

#CAT staticperl.pod

