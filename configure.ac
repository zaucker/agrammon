#  Copyright (C) 2020 Oetiker+Partner AG

AC_INIT([agrammon], m4_esyscmd(jq '.version' < META6.json | tr -d '""' | tr -d '\n'),[fritz.zaucker@oetiker.ch])
AC_PREREQ([2.71])
AC_CONFIG_AUX_DIR(conftools)

MJ_CLASS=Agrammon
MJ_SCRIPT=agrammon
QX_CLASS=agrammon

AC_SUBST(MJ_CLASS)
AC_SUBST(MJ_SCRIPT)
AC_SUBST(QX_CLASS)

# need this to allow long path names
AM_INIT_AUTOMAKE([1.9 tar-ustar foreign])
AM_MAINTAINER_MODE

m4_ifdef([AM_SILENT_RULES], [AM_SILENT_RULES([yes])])

AC_PREFIX_DEFAULT(/opt/$PACKAGE_NAME-$PACKAGE_VERSION)

AC_ARG_VAR(PERL,   [Path to local perl binary])
AC_PATH_PROG(PERL, perl, no)
AC_PATH_PROG(CURL, curl, no)
AC_PATH_PROG(WGET, wget, no)
AC_ARG_VAR(NODE,   [Path to local node binary])
AC_PATH_PROG(NODE, node, no)
AC_PATH_PROG(NPM, npm, npm-not-found)
AC_PATH_PROG(NPX, npx, npx-not-found)
AC_PATH_PROG(XGETTEXT, xgettext, xgettext-not-found)
AC_PATH_PROG(MSGMERGE, msgmerge, msgmerge-not-found)


URL_CAT="neither curl nor wget found"

if test -x "$CURL"; then
    URL_CAT="$CURL --location --insecure"
else
    if test -x "$WGET"; then
        URL_CAT="$WGET -O -"
    fi
fi

AC_SUBST(URL_CAT)

ac_perl_version="5.22.0"

if test -x "$PERL"; then
  AC_MSG_CHECKING(for perl version greater than or equal to $ac_perl_version)
  $PERL -e "use $ac_perl_version;" >/dev/null 2>&1
  if test $? -ne 0; then
    AC_MSG_RESULT(no);
    AC_MSG_ERROR(at least version ${ac_perl_version} is required to run mojolicious)
  else
    AC_MSG_RESULT(ok);
  fi
else
  AC_MSG_ERROR(could not find perl)
fi

ac_node_version="10"

if test -x "$NODE"; then
  AC_MSG_CHECKING(make sure we have at least node ${ac_node_version})
  case `$NODE --version` in
  v10*)
    AC_MSG_RESULT(ok v10)
    ;;
  v11*)
    AC_MSG_RESULT(ok v11)
    ;;
  v12*)
    AC_MSG_RESULT(ok v12)
    ;;
  v13*)
    AC_MSG_RESULT(ok v13)
    ;;
  v22*)
    AC_MSG_RESULT(ok v22)
    ;;
  *)
    AC_MSG_RESULT(no);
    NODE=old-node
  esac
fi

AM_CONDITIONAL(BUILD_QOOXDOO_APP,[test -x $NODE])

AC_PATH_PROG(OPENSSL, openssl, no)
if  test -x "$OPENSSL"; then
:
else
  AC_MSG_ERROR(could not find openssl binary)
fi

AC_MSG_CHECKING(is perl reasonably complete)
if $PERL -MExtUtils::MakeMaker -e '' 2>/dev/null; then
  AC_MSG_RESULT(yes. ExtUtils::MakeMaker is available);
else
  AC_MSG_RESULT(no)
  AC_MSG_ERROR([a complete perl ('perl-core' in the redhat world) installation is required])
fi

AC_MSG_CHECKING([if we require a c compiler to get perl modules compiled])
if $PERL -MIO::Socket::IP -e 'exit($IO::Socket::IP::VERSION >= 0.37)' 2>/dev/null; then
    AC_MSG_RESULT(no)
else
    AC_MSG_RESULT(yes)
    perl_cc=`$PERL -MConfig -e 'print $Config{cc}'`
    AC_PATH_PROG(PERL_CC_PATH, $perl_cc, no)
    AC_MSG_CHECKING(is perls favorite c compiler ($perl_cc) available)
    if test x$PERL_CC_PATH = xno; then
      AC_MSG_RESULT(no)
      AC_MSG_ERROR([perl needs the '$perl_cc' compiler package to build dependencies])
    else
      AC_MSG_RESULT(yes)
    fi
fi


AC_PROG_GREP

AC_ARG_VAR(GMAKE,   [Path to local GNU Make binary])
AC_PATH_PROGS(GMAKE, [gnumake gmake make])

AC_MSG_CHECKING([for gnu make availablility])
if  ( $GMAKE --version 2> /dev/null | $GREP GNU  > /dev/null 2>&1 );  then
    AC_MSG_RESULT([$GMAKE is GNU make])
else
    AC_MSG_ERROR([GNU make not found. Try setting the GMAKE environment variable.])
fi

AC_ARG_ENABLE(pkgonly,
        AS_HELP_STRING([--enable-pkgonly],[Skip all checking]))
AC_SUBST(enable_pkgonly)

actual_prefix=$prefix
if test "$actual_prefix" = "NONE"; then
    actual_prefix=$ac_default_prefix
fi

AC_MSG_CHECKING([Checking Install Prefix])
if test -f "$actual_prefix/configure"; then
    AC_MSG_ERROR([The install prefix must NOT point to the directory where you unpacked the source.])
else
    AC_MSG_RESULT([install Prefix is fine])
fi

AC_ARG_VAR(RAKULIB,   [Colon separated list of raku library directories])
AC_SUBST(RAKULIB)

#    lib/Makefile
#    bin/Makefile
AC_CONFIG_FILES([
    Makefile
    etc/Makefile
    frontend/Makefile
])

AC_SUBST(VERSION)

AC_OUTPUT


if test -x "$NODE"; then
:
else
cat <<NOTES

** WARNING ***********************************************

To run the qooxdoo compiler, at least node v10 is required.
Use nvm to setup your local, up to date copy of node.
Go to https://github.com/nvm-sh/nvm for futher information

NOTES
fi


if test "$mod_ok" = "0"; then
    cat <<NOTES

** SOME PERL MODULES ARE MISSING ******************************

If you know where perl can find the missing modules, set
the RAKULIB environment variable accordingly. Otherwise
just proceed and the missing modules will be installed
automatically.

To force the system to download missing raku modules, you can
do a `zef --debug --/test --deps-only --test-depends --force-install install .` before running `$GMAKE`
NOTES

fi

cat <<NOTES

** CONFIGURE DONE **********************************************

Settings:

  RAKULIB = ${RAKULIB:-"not set"}
  PERL = $PERL

The Makefiles use GNU make functionality.
Continue installation with

  $GMAKE install

NOTES
