#!/bin/bash -xe
OPTIND=1         # Reset in case getopts has been used previously in the shell.
CMD=$(basename $0)

build_number=0
extract_symbols=false
nightly_build=false
cmake_params=
path=

show_usage() {
    echo "Usage: $CMD [-e] [-c \"cmake params\"] [-h|-?] container_path"
}

show_help() {
    show_usage
    echo ""
    echo "Available arguments:"
    echo "  -b ................ Build number (default: 0)"
    echo "  -c ................ Pass additional parameters to cmake"
    echo "  -e ................ Extract symbols for use with breakpad to \$PWD/symbols"
    echo "  -n ................ Build nightly build"
    echo "  -h, -? ............ Show this help"
}

build_client() {
    params="$1"

    mkdir -p build
    pushd build

    if [ ! -z "$oem_theme" ]; then
      tar xvfj ../$oem_theme.tar.bz2
      if [ -d $PWD/$oem_theme/syncclient ]; then
        params="-DOEM_THEME_DIR=$PWD/$oem_theme/syncclient"
      else
        params="-DOEM_THEME_DIR=$PWD/$oem_theme/mirall"
      fi
    fi

    if [ "$extract_symbols" = true ]; then
      params="-DWITH_CRASHREPORTER=ON $params"
    fi

    if [ "$nightly_build" = true ]; then
      today=$(date +%Y%m%d)
      params="$params -DVERSION_SUFFIX=-nightly$today -DMIRALL_VERSION_SUFFIX=-nightly$today"
    fi

    params="$params -DMIRALL_VERSION_BUILD=$build_number -DBUILD_WITH_QT4=OFF"

    cmake -DCMAKE_TOOLCHAIN_FILE=../admin/win/Toolchain-mingw32-openSUSE.cmake \
          -DCMAKE_BUILD_TYPE="RelWithDebInfo" \
          $params ..
    make -j4 VERBOSE=1
    popd
}

extract_symbols() {
    mkdir -p symbols/

    shopt -s globstar
    for f in $(find build/bin/ -name \*.dll -or -name \*.exe)
    do
        echo "Generate symbols for $f"
        i686-w64-mingw32-gen_sym_files "$f"
        i686-w64-mingw32-strip "$f"
    done

    # Pull in OBS built debug symbols
    for f in $(egrep "^   File.*dll" cmake/modules/NSIS.template.in | sed -e 's/^.*\\//' | sed -e 's/\"$//' | grep -v '\$')
    do
        if [ ! -d "symbols/$f" ]; then
            if [ ! -d "/usr/i686-w64-mingw32/sys-root/mingw/symbols/$f" ]; then
                echo "No debug symbols available for $f"
                #exit -1
            else
                echo "Pull in symbols for $f"
                cp -rvf "/usr/i686-w64-mingw32/sys-root/mingw/symbols/$f" symbols/$f
            fi
        fi
    done

    if [ "$nightly_build" = true ]; then
        folder="nightly"
    else
        folder="stable"
    fi
}

create_package() {
    pushd build

    if [ -e  ../admin/win/download_runtimes.sh ]; then
      ../admin/win/download_runtimes.sh
    fi
    make package
    popd
}

# main
while getopts "b:h?ec:n:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    b)  build_number=$OPTARG
        ;;
    c)  cmake_params=$OPTARG
        ;;
    e)  extract_symbols=true
        ;;
    n)  nighly_builds=true
        ;;
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift

path=$@

if [ -z $path ]; then
    show_usage
    exit 0
fi

cd "$path"
build_client
if [ "$extract_symbols" = true ]; then
    extract_symbols
fi
create_package

