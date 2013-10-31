#!/bin/bash

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

TOP="$(dirname "$0")"

PROJECT=libxml2
LICENSE=COPYING
VERSION="2.9.1"
SOURCE_DIR="$PROJECT"


if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

# load autobuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

stage="$(pwd)"
case "$AUTOBUILD_PLATFORM" in
    "linux")
        pushd "$TOP/$SOURCE_DIR"
            CPPFLAGS="-m32" LDFLAGS="-m32 -L$stage/packages/lib/release" ./configure --prefix="$stage"  --with-python=no
            make
            make install
        popd
        mv lib release
        mkdir -p lib
        mv release lib
    ;;
    *)
        echo "platform not supported"
        exit -1
    ;;
esac


mkdir -p "$stage/LICENSES"
cp "$TOP/$SOURCE_DIR/$LICENSE" "$stage/LICENSES/$PROJECT.txt"

pass

