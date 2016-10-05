#!/usr/bin/env bash

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# bleat on references to undefined shell variables
set -u

TOP="$(dirname "$0")"

PROJECT=libxml2
LICENSE=Copyright
SOURCE_DIR="$PROJECT"

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

stage="$(pwd)"
[ -f "$stage"/packages/include/zlib/zlib.h ] || \
{ echo "You haven't installed packages yet." 1>&2; exit 1; }

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# Different upstream versions seem to check in different snapshots in time of
# the configure script.
for confile in configure.in configure configure.ac
do configure="${TOP}/${PROJECT}/${confile}"
   [ -r "$configure" ] && break
fi
# If none of the above exist, stop for a human coder to figure out.
[ -r "$configure" ] || { echo "Can't find configure script for version info" 1>&2; exit 1; }

major_version="$(sed -n -E 's/LIBXML_MAJOR_VERSION=([0-9]+)/\1/p' "$configure")"
minor_version="$(sed -n -E 's/LIBXML_MINOR_VERSION=([0-9]+)/\1/p' "$configure")"
micro_version="$(sed -n -E 's/LIBXML_MICRO_VERSION=([0-9]+)/\1/p' "$configure")"
version="${major_version}.${minor_version}.${micro_version}"
build=${AUTOBUILD_BUILD_ID:=0}
echo "${version}.${build}" > "${stage}/VERSION.txt"

pushd "$TOP/$SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        windows*)
            load_vsvars

            mkdir -p "$stage/lib/release"

            pushd "$TOP/$SOURCE_DIR/win32"

                cscript configure.js zlib=yes icu=no static=yes debug=no python=no iconv=no \
                    compiler=msvc \
                    include="$(cygpath -w $stage/packages/include);$(cygpath -w $stage/packages/include/zlib)" \
                    lib="$(cygpath -w $stage/packages/lib/release)" \
                    prefix="$(cygpath -w $stage)" \
                    sodir="$(cygpath -w $stage/lib/release)" \
                    libdir="$(cygpath -w $stage/lib/release)"

                nmake /f Makefile.msvc ZLIB_LIBRARY=zlib.lib all
                nmake /f Makefile.msvc install

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    nmake /f Makefile.msvc checktests
                fi

                nmake /f Makefile.msvc clean
            popd
        ;;

        linux*)
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Prefer gcc-4.6 if available.
            if [ -x /usr/bin/gcc-4.6 -a -x /usr/bin/g++-4.6 ]; then
                export CC=/usr/bin/gcc-4.6
                export CXX=/usr/bin/g++-4.6
            fi

            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Release
            # CPPFLAGS will be used by configure and we need to
            # get the dependent packages in there as well.  Process
            # may find the system zlib.h but it won't find the
            # packaged one.
            CFLAGS="$opts -I$stage/packages/include/zlib" \
                CPPFLAGS="${CPPFLAGS:-} -I$stage/packages/include/zlib" \
                LDFLAGS="$opts -L$stage/packages/lib/release" \
                ./configure --with-python=no --with-pic --with-zlib \
                --disable-shared --enable-static \
                --prefix="$stage" --libdir="$stage"/lib/release
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make check
            fi

            make clean
        ;;

        darwin*)
            opts="${TARGET_OPTS:--arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE}"

            # Release last for configuration headers
            # CPPFLAGS will be used by configure and we need to
            # get the dependent packages in there as well.  Process
            # may find the system zlib.h but it won't find the
            # packaged one.
            CFLAGS="$opts -I$stage/packages/include/zlib" \
                CPPFLAGS="${CPPFLAGS:-} -I$stage/packages/include/zlib" \
                LDFLAGS="$opts -L$stage/packages/lib/release" \
                ./configure --with-python=no --with-pic --with-zlib \
                --disable-shared --enable-static \
                --prefix="$stage" --libdir="$stage"/lib/release
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make check
            fi

            make clean
        ;;

        *)
            echo "platform not supported" 1>&2
            exit 1
        ;;
    esac
popd

mkdir -p "$stage/LICENSES"
cp "$TOP/$SOURCE_DIR/$LICENSE" "$stage/LICENSES/$PROJECT.txt"
mkdir -p "$stage"/docs/libxml2/
cp -a "$TOP"/README.Linden "$stage"/docs/libxml2/
