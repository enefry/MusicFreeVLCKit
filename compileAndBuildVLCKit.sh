#!/usr/bin/env bash
# Copyright (C) Pierre d'Herbemont, 2010
# Copyright (C) Felix Paul Kühne, 2012-2026

set -e

BUILD_DEVICE=yes
BUILD_SIMULATOR=yes
BUILD_FRAMEWORK=no
SDK_VERSION=`xcrun --sdk iphoneos --show-sdk-version`
SDK_MIN=15.0
VERBOSE=no
DISABLEDEBUG=no
CONFIGURATION="Debug"
NONETWORK=no
SKIPLIBVLCCOMPILATION=no
TVOS=no
MACOS=no
IOS=yes
XROS=no
WATCHOS=no
BITCODE=no
INCLUDE_ARMV7=no
OSVERSIONMINCFLAG=iphoneos
OSVERSIONMINLDFLAG=ios
ROOT_DIR=empty
FARCH="all"
VLC_BUILD_CONFIG="${VLC_BUILD_CONFIG:-}"
BUILD_ROOT="${MUSICFREE_BUILD_ROOT:-}"
VLC_BUILD_ROOT="${MUSICFREE_VLC_BUILD_ROOT:-}"
INSTALL_ROOT="${MUSICFREE_INSTALL_ROOT:-}"
PLUGIN_HEADER_ROOT="${MUSICFREE_PLUGIN_HEADER_ROOT:-}"
DEVICE_STATIC_LIB="${MUSICFREE_VLC_DEVICE_STATIC_LIB:-}"
SIMULATOR_STATIC_LIB="${MUSICFREE_VLC_SIMULATOR_STATIC_LIB:-}"

if [ -z "$MAKEFLAGS" ]; then
    MAKEFLAGS="-j$(sysctl -n machdep.cpu.core_count || nproc)";
fi

TESTEDHASH="2cd8705589d3b125f236d1af695c3961fdcf6ca4" # libvlc base commit
PATCHEDTREE="34c486a4b371e57b4d37bff288222c26fb86d8a0" # tree after MusicFree patch series

usage()
{
cat << EOF
usage: $0 [-s] [-v] [-k sdk]

OPTIONS
   -k       Specify which sdk to use (see 'xcodebuild -showsdks', current: ${SDK})
   -v       Be more verbose
   -s       Build for simulator
   -f       Build framework for device and simulator
   -r       Disable Debug for Release
   -n       Skip script steps requiring network interaction
   -l       Skip libvlc compilation
   -t       Build for tvOS
   -x       Build for macOS / Mac OS X
   -i       Build for xrOS / visionOS
   -w       Build for watchOS
   -b       Enable bitcode
   -a       Build framework for specific arch (all|x86_64|armv7|aarch64)
   -e       External VLC source path
   -7       Include optional ARMv7 slice (iOS only)
EOF
}

get_actual_arch() {
    if [ "$1" = "aarch64" ]; then
        echo "arm64"
    else
        echo "$1"
    fi
}

get_arch() {
    if [ "$1" = "arm64" ]; then
        echo "aarch64"
    else
        echo "$1"
    fi
}

is_simulator_arch() {
    if [ "$1" = "x86_64" ];then
        return 0
    else
        return 1
    fi
}

spushd()
{
     pushd "$1" 2>&1> /dev/null
}

spopd()
{
     popd 2>&1> /dev/null
}

run_xcodebuild()
{
     if [ "$VERBOSE" = "yes" ]; then
         xcodebuild "$@"
     else
         xcodebuild "$@" > /dev/null
     fi
}

info()
{
     local green="\033[1;32m"
     local normal="\033[0m"
     echo "[${green}info${normal}] $1"
}

buildxcodeproj()
{
    local PLATFORM="$2"
    local PLATFORMNAME="$3"

    info "Building $1 (${CONFIGURATION}, $PLATFORM)"

    local architectures=""
    if [ "$FARCH" = "all" ];then
        if [ "$TVOS" = "yes" ]; then
            if [ "$PLATFORM" = "appletvsimulator" ]; then
                architectures="x86_64 arm64"
            else
                architectures="arm64"
            fi
        fi
        if [ "$IOS" = "yes" ]; then
            if [ "$PLATFORM" = "iphonesimulator" ]; then
                architectures="x86_64 arm64"
            else
                if [ "$INCLUDE_ARMV7" = "yes" ]; then
                    architectures="armv7 arm64"
                else
                    architectures="arm64"
                fi
            fi
        fi
        if [ "$MACOS" = "yes" ]; then
            architectures="arm64 x86_64"
        fi
        if [ "$XROS" = "yes" ]; then
            architectures="arm64"
        fi
        if [ "$WATCHOS" = "yes" ]; then
            if [ "$PLATFORM" = "watchsimulator" ]; then
                architectures="x86_64 arm64"
            else
                architectures="arm64_32 arm64"
            fi
        fi
    else
        architectures=`get_actual_arch $FARCH`
    fi

    local bitcodeflag=""
    if [ "$IOS" = "yes" ]; then
    if [ "$BITCODE" = "yes" ]; then
        info "Bitcode enabled"
        bitcodeflag="BITCODE_GENERATION_MODE=bitcode"
    else
        info "Bitcode disabled"
        bitcodeflag="BITCODE_GENERATION_MODE=none ENABLE_BITCODE=no"
    fi
    fi
    if [ "$TVOS" = "yes" ]; then
    if [ "$BITCODE" = "yes" ]; then
        bitcodeflag="BITCODE_GENERATION_MODE=bitcode"
    fi
    fi

    local verboseflag=""
    if [ "$VERBOSE" = "yes" ]; then
        verboseflag="-verbose"
    fi

    local deploymentTargetFlag=""
    if [ "$XROS" != "yes" ]; then
        deploymentTargetFlag="IPHONEOS_DEPLOYMENT_TARGET=${SDK_MIN}"
    fi

    # The static VLC archive and the Objective-C wrapper must use the same
    # profile. Keep the inherited expansion literal for xcodebuild.
    local defs="${GCC_PREPROCESSOR_DEFINITIONS:-}"
    defs="${defs} MUSICFREE_AUDIO_PROFILE=1"

    run_xcodebuild archive \
               -project "$1.xcodeproj" \
               -sdk $PLATFORM$SDK \
               -configuration ${CONFIGURATION} \
               -scheme "VLCKit" \
               -destination "generic/platform=${PLATFORMNAME}" \
               -archivePath "${BUILD_ROOT}/VLCKit-$PLATFORM$SDK.xcarchive" \
               -derivedDataPath "${BUILD_ROOT}/DerivedData-$PLATFORM" \
               ARCHS="${architectures}" \
               ${deploymentTargetFlag} \
               ${bitcodeflag} \
               ${verboseflag} \
               GCC_PREPROCESSOR_DEFINITIONS="${defs}" \
               MUSICFREE_VLC_INSTALL_ROOT="${INSTALL_ROOT}" \
               MUSICFREE_VLC_DEVICE_STATIC_LIB="${DEVICE_STATIC_LIB}" \
               MUSICFREE_VLC_SIMULATOR_STATIC_LIB="${SIMULATOR_STATIC_LIB}" \
               MUSICFREE_PLUGIN_HEADER_ROOT="${PLUGIN_HEADER_ROOT}" \
               SKIP_INSTALL=no \
               ONLY_ACTIVE_ARCH=NO
}

buildLibVLC() {
    ARCH="$1"
    PLATFORM="$2"

    if [ "$DISABLEDEBUG" = "yes" ]; then
        DEBUGFLAG="--disable-debug"
    else
        DEBUGFLAG=""
    fi
    if [ "$VERBOSE" = "yes" ]; then
        VERBOSEFLAG="--verbose"
    else
        VERBOSEFLAG=""
    fi
    if [ "$BITCODE" = "yes" ]; then
        if [[ "$PLATFORM" == *"os"* ]]; then
            BITCODEFLAG="--enable-bitcode"
        else
            BITCODEFLAG=""
        fi
    else
        BITCODEFLAG=""
    fi
    info "Compiling ${ARCH} with SDK version ${SDK_VERSION}, platform ${PLATFORM}"

    ACTUAL_ARCH=`get_actual_arch $ARCH`
    BUILDDIR="${VLC_BUILD_ROOT}/build-${PLATFORM}-${ACTUAL_ARCH}"

    mkdir -p ${BUILDDIR}
    spushd ${BUILDDIR}

    "${VLCROOT}/extras/package/apple/build.sh" --arch=$ARCH --sdk=${PLATFORM}${SDK_VERSION} --config="${VLC_BUILD_CONFIG}" ${DEBUGFLAG} ${VERBOSEFLAG} ${BITCODEFLAG} ${MAKEFLAGS}

    spopd # builddir

    info "Finished compiling libvlc for ${ARCH} with SDK version ${SDK_VERSION}, platform ${PLATFORM}"
}

buildMobileKit() {
    PLATFORM="$1"

    if [ "$SKIPLIBVLCCOMPILATION" != "yes" ]; then
        if [ "$FARCH" = "all" ];then
            if [ "$TVOS" = "yes" ]; then
                if [ "$PLATFORM" = "iphonesimulator" ]; then
                    buildLibVLC "x86_64" "appletvsimulator"
                    buildLibVLC "aarch64" "appletvsimulator"
                else
                    buildLibVLC "aarch64" "appletvos"
                fi
            fi
            if [ "$MACOS" = "yes" ]; then
                buildLibVLC "aarch64" "macosx"
                buildLibVLC "x86_64" "macosx"
            fi
            if [ "$XROS" = "yes" ]; then
                info "building for xrOS"
                buildLibVLC "aarch64" "xros"
                buildLibVLC "aarch64" "xrsimulator"
                # there is no xrSimulator for the Intel platform
            fi
            if [ "$WATCHOS" = "yes" ]; then
                info "building for watchOS"
                buildLibVLC "arm64_32" "watchos"
                buildLibVLC "arm64" "watchos"
                buildLibVLC "x86_64" "watchsimulator"
                buildLibVLC "aarch64" "watchsimulator"
            fi
            if [ "$IOS" = "yes" ]; then
                if [ "$PLATFORM" = "iphonesimulator" ]; then
                    buildLibVLC "x86_64" $PLATFORM
                    buildLibVLC "aarch64" $PLATFORM
                else
                    if [ "$INCLUDE_ARMV7" = "yes" ]; then
                        buildLibVLC "armv7" $PLATFORM
                    fi
                    buildLibVLC "aarch64" $PLATFORM
                fi
            fi
        else
            if [ "$FARCH" != "x86_64" -a "$FARCH" != "aarch64" -a "$FARCH" != "armv7" ];then
                echo "*** Framework ARCH: ${FARCH} is invalid ***"
                exit 1
            fi
            if (is_simulator_arch $FARCH);then
                if [ "$TVOS" = "yes" ]; then
                    PLATFORM="appletvsimulator"
                fi
                if [ "$IOS" = "yes" ]; then
                    PLATFORM="iphonesimulator"
                fi
                if [ "$MACOS" = "yes" ]; then
                    PLATFORM="macosx"
                fi
                if [ "$XROS" = "yes" ]; then
                    PLATFORM="xrsimulator"
                fi
                if [ "$WATCHOS" = "yes" ]; then
                    PLATFORM="watchsimulator"
                fi
            else
                if [ "$TVOS" = "yes" ]; then
                    PLATFORM="appletvos"
                fi
                if [ "$IOS" = "yes" ]; then
                    PLATFORM="iphoneos"
                fi
                if [ "$MACOS" = "yes" ]; then
                    PLATFORM="macosx"
                fi
                if [ "$XROS" = "yes" ]; then
                    PLATFORM="xros"
                fi
                if [ "$WATCHOS" = "yes" ]; then
                    PLATFORM="watchos"
                fi
            fi

            buildLibVLC $FARCH "$PLATFORM"
        fi
    fi
}

get_symbol()
{
    echo "$1" | grep vlc_entry_$2|cut -d" " -f 3|sed 's/_vlc/vlc/'
}

function check_lipo {
    os_style="$1"
    os_arch="$2"
    header=""
    if [ -z "${os_style%%*simulator}" ]; then
        header=vlc-plugins-${os_style%simulator}-simulator-${os_arch}.h
    else
        header=vlc-plugins-${os_style%os}-device-${os_arch}.h
    fi

    build_dir="${VLC_BUILD_ROOT}/build-${os_style}-${os_arch}"
    if [ -d "${build_dir}" ]; then
        if [ ! -f "${build_dir}/${VLCSTATICLIBRARYNAME}" ] || [ ! -f "${build_dir}/static-lib/static-module-list.c" ]; then
            echo "*** Incomplete libVLC build at ${build_dir} ***" >&2
            exit 1
        fi
        VLCSTATICLIBS+=" ${build_dir}/${VLCSTATICLIBRARYNAME}"
        VLCSTATICMODULELIST="${build_dir}/static-lib/static-module-list.c"
        mkdir -p "${PLUGIN_HEADER_ROOT}"
        cp "$VLCSTATICMODULELIST" "${PLUGIN_HEADER_ROOT}/${header}"
    else
        echo "Directory ${build_dir} doesn't exist"
    fi
}

build_simulator_static_lib() {
    PROJECT_DIR=`pwd`
    OSSTYLE="$1"
    info "building simulator static lib for $OSSTYLE"

    # remove old module list
    mkdir -p "${PLUGIN_HEADER_ROOT}" "${INSTALL_ROOT}"
    rm -f "${PLUGIN_HEADER_ROOT}/vlc-plugins-$OSSTYLE-simulator.h"
    touch "${PLUGIN_HEADER_ROOT}/vlc-plugins-$OSSTYLE-simulator.h"
    rm -f "${INSTALL_ROOT}/libvlc-simulator-static.a"

    VLCSTATICLIBS=""
    VLCSTATICLIBRARYNAME="static-lib/libvlc-full-static.a"
    VLCSTATICMODULELIST=""

    # brute-force test the available architectures we could lipo
    check_lipo "${OSSTYLE}simulator" x86_64
    check_lipo "${OSSTYLE}simulator" arm64
    # watch and XR is not -simulator suffixed in the script unfortunately.
    check_lipo "${OSSTYLE}" arm64
    check_lipo "${OSSTYLE}" x86_64

    if [ ! -z "${VLCSTATICLIBS}" ]; then
        lipo $VLCSTATICLIBS -create -output "${INSTALL_ROOT}/libvlc-simulator-static.a"
    fi
}

build_device_static_lib() {
    PROJECT_DIR=`pwd`
    OSSTYLE="$1"
    info "building device static lib for $OSSTYLE"

    # remove old module list
    mkdir -p "${PLUGIN_HEADER_ROOT}" "${INSTALL_ROOT}"
    rm -f "${PLUGIN_HEADER_ROOT}/vlc-plugins-$OSSTYLE-device"*
    rm -f "${INSTALL_ROOT}/libvlc-device-static.a"

    VLCSTATICLIBS=""
    VLCSTATICLIBRARYNAME="static-lib/libvlc-full-static.a"
    VLCSTATICMODULELIST=""

    # brute-force test the available architectures we could lipo
    check_lipo "${OSSTYLE}os" arm64
    if [ "$IOS" = "yes" ]; then
        check_lipo "${OSSTYLE}os" armv7
    fi
    if [ "$WATCHOS" = "yes" ]; then
        check_lipo "${OSSTYLE}" arm64_32
    fi
    # macosx and XR are not -os or -simulator suffixed in the script unfortunately.
    check_lipo "${OSSTYLE}" x86_64
    check_lipo "${OSSTYLE}" arm64

    if [ ! -z "${VLCSTATICLIBS}" ]; then
        lipo $VLCSTATICLIBS -create -output "${INSTALL_ROOT}/libvlc-device-static.a"
    fi
}

while getopts "hvsfbrxiwntl7k:a:e:" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         v)
             VERBOSE=yes
             ;;
         s)
             BUILD_DEVICE=no
             BUILD_SIMULATOR=yes
             BUILD_FRAMEWORK=no
             ;;
         f)
             BUILD_DEVICE=yes
             BUILD_SIMULATOR=yes
             BUILD_FRAMEWORK=yes
             ;;
         r)  CONFIGURATION="Release"
             DISABLEDEBUG=yes
             ;;
         n)
             NONETWORK=yes
             ;;
         l)
             SKIPLIBVLCCOMPILATION=yes
             ;;
         k)
             SDK=$OPTARG
             ;;
         a)
             BUILD_DEVICE=yes
             BUILD_SIMULATOR=yes
             BUILD_FRAMEWORK=yes
             FARCH=$OPTARG
             ;;
         b)
             BITCODE=yes
             ;;
         t)
             TVOS=yes
             IOS=no
             SDK_VERSION=`xcrun --sdk appletvos --show-sdk-version`
             SDK_MIN=10.2
             OSVERSIONMINCFLAG=tvos
             OSVERSIONMINLDFLAG=tvos
             ;;
         x)
             MACOS=yes
             IOS=no
             BITCODE=no
             SDK_VERSION=`xcrun --sdk macosx --show-sdk-version`
             SDK_MIN=10.11
             OSVERSIONMINCFLAG=macosx
             OSVERSIONMINLDFLAG=macosx
             BUILD_DEVICE=yes
             BUILD_FRAMEWORK=yes
             ;;
         i)
             XROS=yes
             IOS=no
             BITCODE=no
             SDK_VERSION=`xcrun --sdk xros --show-sdk-version`
             SDK_MIN=1.0
             OSVERSIONMINCFLAG=xros
             OSVERSIONMINLDFLAG=xros
             BUILD_DEVICE=yes
             BUILD_FRAMEWORK=yes
             ;;
         w)
             WATCHOS=yes
             IOS=no
             BITCODE=no
             SDK_VERSION=`xcrun --sdk watchos --show-sdk-version`
             SDK_MIN=7.4
             OSVERSIONMINCFLAG=watchos
             OSVERSIONMINLDFLAG=watchos
             BUILD_DEVICE=yes
             BUILD_FRAMEWORK=yes
             ;;
         e)
             VLCROOT=$OPTARG
             ;;
         7)
             INCLUDE_ARMV7=yes
             ;;
         ?)
             usage
             exit 1
             ;;
     esac
done
shift $(($OPTIND - 1))

out="/dev/null"
if [ "$VERBOSE" = "yes" ]; then
   out="/dev/stdout"
fi

if [ "$1" != "" ]; then
    usage
    exit 1
fi

# Get root dir
spushd .
ROOT_DIR=`pwd`
spopd

if [ -z "${VLC_BUILD_CONFIG}" ]; then
    VLC_BUILD_CONFIG="${ROOT_DIR}/Config/audio-ios.env"
fi
if [ ! -f "${VLC_BUILD_CONFIG}" ]; then
    echo "*** Build configuration not found: ${VLC_BUILD_CONFIG} ***" >&2
    exit 1
fi

if [ "$VLCROOT" = "" ]; then
    VLCROOT=${ROOT_DIR}/libvlc/vlc
    info "Preparing build dirs"

    mkdir -p libvlc
    spushd libvlc

    if [ "$NONETWORK" != "yes" ]; then
        if ! [ -e vlc ]; then
            git clone https://code.videolan.org/videolan/vlc.git --branch master --single-branch vlc
            info "Applying patches to vlc.git"
            cd vlc
            git checkout -B localBranch ${TESTEDHASH}
            git branch --set-upstream-to=origin/master localBranch
            git am ${ROOT_DIR}/libvlc/patches/*.patch
            if [ $? -ne 0 ]; then
                git am --abort
                info "Applying the patches failed, aborting git-am"
                exit 1
            fi
            cd ..
        else
            cd vlc
            current_hash=`git rev-parse HEAD`
            current_tree=`git rev-parse 'HEAD^{tree}'`
            if [ "${current_tree}" = "${PATCHEDTREE}" ]; then
                if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
                    echo "*** Refusing to reuse a dirty patched VLC checkout ***" >&2
                    exit 1
                fi
                info "Reusing existing patched VLC checkout with tree ${PATCHEDTREE}"
            elif [ "${current_hash}" = "${TESTEDHASH}" ]; then
                if [ -n "$(git status --porcelain)" ]; then
                    echo "*** Refusing to apply patches to a dirty VLC checkout at ${TESTEDHASH} ***" >&2
                    exit 1
                fi
                info "Applying patches to the clean VLC baseline"
                git am ${ROOT_DIR}/libvlc/patches/*.patch
                current_tree=`git rev-parse 'HEAD^{tree}'`
                if [ "${current_tree}" != "${PATCHEDTREE}" ]; then
                    echo "*** Patched VLC tree ${current_tree} does not match expected ${PATCHEDTREE} ***" >&2
                    exit 1
                fi
            else
                echo "*** Refusing to reset or patch VLC checkout at ${current_hash}; expected base ${TESTEDHASH} or patched tree ${PATCHEDTREE} ***" >&2
                exit 1
            fi
            cd ..
        fi
    fi

    spopd
fi

BUILD_ROOT="${BUILD_ROOT:-${ROOT_DIR}/build-audio-ios}"
VLC_BUILD_ROOT="${VLC_BUILD_ROOT:-${VLCROOT}/audio-ios-build}"
INSTALL_ROOT="${INSTALL_ROOT:-${VLCROOT}/audio-ios-install}"
PLUGIN_HEADER_ROOT="${PLUGIN_HEADER_ROOT:-${BUILD_ROOT}/generated-headers}"
DEVICE_STATIC_LIB="${DEVICE_STATIC_LIB:-${INSTALL_ROOT}/libvlc-device-static.a}"
SIMULATOR_STATIC_LIB="${SIMULATOR_STATIC_LIB:-${INSTALL_ROOT}/libvlc-simulator-static.a}"
mkdir -p "${BUILD_ROOT}" "${VLC_BUILD_ROOT}" "${INSTALL_ROOT}" "${PLUGIN_HEADER_ROOT}"
# The XCFramework assembly step changes into BUILD_ROOT. Normalize it before
# constructing archive and dSYM paths so relative caller-provided roots do not
# get duplicated after the directory change.
BUILD_ROOT="$(CDPATH= cd -- "${BUILD_ROOT}" && pwd)"

fetch_python3_path() {
    PYTHON3_PATH=$(echo /Library/Frameworks/Python.framework/Versions/3.*/bin | awk '{print $1;}')
    if [ ! -d "${PYTHON3_PATH}" ]; then
        PYTHON3_PATH=""
    fi
}

#
# Build time
#

out="/dev/null"
if [ "$VERBOSE" = "yes" ]; then
   out="/dev/stdout"
fi

if [ "$SKIPLIBVLCCOMPILATION" != "yes" ]; then
    info "Building tools"

    fetch_python3_path
    # Keep host tools deterministic. In particular, an inherited VLC_PATH can
    # prepend stale binaries such as an incompatible external protoc. CI can
    # explicitly provide a curated host-tool directory without inheriting the
    # runner's full PATH.
    HOST_TOOLS_PATH="${MUSICFREE_VLC_HOST_TOOLS_PATH:-}"
    TOOL_PATH=""
    if [ -n "${HOST_TOOLS_PATH}" ]; then
        TOOL_PATH="${HOST_TOOLS_PATH}"
    fi
    if [ -n "${PYTHON3_PATH}" ]; then
        TOOL_PATH="${TOOL_PATH:+${TOOL_PATH}:}${PYTHON3_PATH}"
    fi
    export PATH="${TOOL_PATH:+${TOOL_PATH}:}${VLCROOT}/extras/tools/build/bin:${VLCROOT}/contrib/${TARGET}/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    spushd ${VLCROOT}/extras/tools
    ./bootstrap
    if [ "${MUSICFREE_VLC_REQUIRE_HOST_TOOLS:-no}" = "yes" ]; then
        BOOTSTRAP_TARGETS=$(sed -n 's/^all:[[:space:]]*//p' Makefile)
        UNEXPECTED_BOOTSTRAP_TARGETS=""
        for target in ${BOOTSTRAP_TARGETS}; do
            case "${target}" in
                .buildconfigguess)
                    ;;
                *)
                    UNEXPECTED_BOOTSTRAP_TARGETS="${UNEXPECTED_BOOTSTRAP_TARGETS} ${target}"
                    ;;
            esac
        done
        if [ -n "${UNEXPECTED_BOOTSTRAP_TARGETS}" ]; then
            echo "*** VLC bootstrap rejected required host tools:${UNEXPECTED_BOOTSTRAP_TARGETS} ***" >&2
            exit 1
        fi
    fi
    make
    spopd #${VLCROOT}/extras/tools
fi

if [ "$BUILD_DEVICE" != "no" ]; then
    buildMobileKit iphoneos
fi
if [ "$BUILD_SIMULATOR" != "no" ]; then
    buildMobileKit iphonesimulator
fi

DEVICEARCHS=""
SIMULATORARCHS=""

if [ "$TVOS" = "yes" ]; then
    build_simulator_static_lib "appletv"
    build_device_static_lib "appletv"
fi
if [ "$XROS" = "yes" ]; then
    build_simulator_static_lib "xros"
    build_device_static_lib "xros"
fi
if [ "$WATCHOS" = "yes" ]; then
    build_simulator_static_lib "watch"
    build_device_static_lib "watchos"
fi
if [ "$MACOS" = "yes" ]; then
    build_device_static_lib "macosx"
fi
if [ "$IOS" = "yes" ]; then
    build_simulator_static_lib "iphone"
    build_device_static_lib "iphone"
fi

info "all done"

if [ "$BUILD_FRAMEWORK" = "no" ]; then
	exit 0
fi
if [ "$TVOS" = "yes" ]; then
    info "Building VLCKit.xcframework for tvOS"

    frameworks=""
    platform=""
    if [ "$FARCH" = "all" ] || (! is_simulator_arch $FARCH);then
        platform="appletvos"
        buildxcodeproj VLCKit ${platform} tvOS
        dsymfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/dSYMs/VLCKit.framework.dSYM
        bcsymbolmapfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/BCSymbolMaps
        frameworks="$frameworks -framework VLCKit-${platform}.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols $dsymfolder"
        if [ -d ${bcsymbolmapfolder} ];then
            info "Bitcode support found"
            spushd $bcsymbolmapfolder
            for i in `ls *.bcsymbolmap`
            do
                frameworks+=" -debug-symbols $bcsymbolmapfolder/$i"
            done
            spopd
        fi
    fi
    if [ "$FARCH" = "all" ] || (is_simulator_arch $FARCH);then
        platform="appletvsimulator"
        buildxcodeproj VLCKit ${platform} "tvOS Simulator"
        dsymfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/dSYMs/VLCKit.framework.dSYM
        frameworks="$frameworks -framework VLCKit-${platform}.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols $dsymfolder"
    fi

    # Assumes both platforms were built currently
    spushd "$BUILD_ROOT"
    rm -rf tvOS
    mkdir tvOS
    xcodebuild -create-xcframework $frameworks -output tvOS/VLCKit.xcframework
    spopd # build

    info "Build of VLCKit.xcframework for tvOS completed"
fi
if [ "$IOS" = "yes" ]; then
    info "Building VLCKit.xcframework for iOS"

    frameworks=""
    platform=""
    if [ "$FARCH" = "all" ] || (! is_simulator_arch $FARCH);then
        platform="iphoneos"
        buildxcodeproj VLCKit ${platform} iOS
        dsymfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/dSYMs/VLCKit.framework.dSYM
        bcsymbolmapfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/BCSymbolMaps
        frameworks="$frameworks -framework VLCKit-${platform}.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols $dsymfolder"
        if [ -d ${bcsymbolmapfolder} ];then
            info "Bitcode support found"
            spushd $bcsymbolmapfolder
            for i in `ls *.bcsymbolmap`
            do
                frameworks+=" -debug-symbols $bcsymbolmapfolder/$i"
            done
            spopd
        fi
    fi
    if [ "$FARCH" = "all" ] || (is_simulator_arch $FARCH);then
        platform="iphonesimulator"
        buildxcodeproj VLCKit ${platform} "iOS Simulator"
        dsymfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/dSYMs/VLCKit.framework.dSYM
        frameworks="$frameworks -framework VLCKit-${platform}.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols $dsymfolder"
    fi

    # Assumes both platforms were built currently
    spushd "$BUILD_ROOT"
    rm -rf iOS
    mkdir iOS
    xcodebuild -create-xcframework $frameworks -output iOS/VLCKit.xcframework
    spopd # build

    info "Build of VLCKit.xcframework for iOS completed"
fi
if [ "$XROS" = "yes" ]; then
    info "Building VLCKit.xcframework for xrOS"

    frameworks=""
    platform=""
    if [ "$FARCH" = "all" ] || (! is_simulator_arch $FARCH);then
        platform="xros"
        buildxcodeproj VLCKit ${platform} xrOS
        dsymfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/dSYMs/VLCKit.framework.dSYM
        frameworks="$frameworks -framework VLCKit-${platform}.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols $dsymfolder"
    fi
    if [ "$FARCH" = "all" ] || (is_simulator_arch $FARCH);then
        platform="xrsimulator"
        buildxcodeproj VLCKit ${platform} "xrOS Simulator"
        dsymfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/dSYMs/VLCKit.framework.dSYM
        frameworks="$frameworks -framework VLCKit-${platform}.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols $dsymfolder"
    fi

    # Assumes both platforms were built currently
    spushd "$BUILD_ROOT"
    rm -rf xrOS
    mkdir xrOS
    xcodebuild -create-xcframework $frameworks -output xrOS/VLCKit.xcframework
    spopd # build

    info "Build of VLCKit.xcframework for xrOS completed"
fi
if [ "$WATCHOS" = "yes" ]; then
    info "Building VLCKit.xcframework for watchOS"

    frameworks=""
    platform=""
    if [ "$FARCH" = "all" ] || (! is_simulator_arch $FARCH);then
        platform="watchos"
        buildxcodeproj VLCKit ${platform} watchOS
        dsymfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/dSYMs/VLCKit.framework.dSYM
        frameworks="$frameworks -framework VLCKit-${platform}.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols $dsymfolder"
    fi
    if [ "$FARCH" = "all" ] || (is_simulator_arch $FARCH);then
        platform="watchsimulator"
        buildxcodeproj VLCKit ${platform} "watchOS Simulator"
        dsymfolder=$BUILD_ROOT/VLCKit-${platform}.xcarchive/dSYMs/VLCKit.framework.dSYM
        frameworks="$frameworks -framework VLCKit-${platform}.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols $dsymfolder"
    fi

    # Assumes both platforms were built currently
    spushd "$BUILD_ROOT"
    rm -rf watchOS
    mkdir watchOS
    xcodebuild -create-xcframework $frameworks -output watchOS/VLCKit.xcframework
    spopd # build

    info "Build of VLCKit.xcframework for watchOS completed"
fi
if [ "$MACOS" = "yes" ]; then
    CURRENT_DIR=`pwd`
    info "Building VLCKit.xcframework for macOS in ${CURRENT_DIR}"

    buildxcodeproj VLCKit "macosx" macOS

    spushd build
    rm -rf macOS
    mkdir macOS
    xcodebuild -create-xcframework -framework VLCKit-macosx.xcarchive/Products/Library/Frameworks/VLCKit.framework -debug-symbols "$BUILD_ROOT/VLCKit-macosx.xcarchive/dSYMs/VLCKit.framework.dSYM" -output macOS/VLCKit.xcframework
    spopd # build

    info "Build of VLCKit.xcframework for macOS completed"
fi
