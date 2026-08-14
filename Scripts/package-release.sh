#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

if [ -n "${MUSICFREE_VLCKIT_BUILD_ROOT:-}" ]; then
    BUILD_ROOT=$(CDPATH= cd -- "${MUSICFREE_VLCKIT_BUILD_ROOT}" && pwd)
else
    BUILD_ROOT=$(find "${REPO_ROOT}" -maxdepth 1 -type d -name 'build-audio-ios-*' -print | sort | tail -n 1)
    if [ -z "${BUILD_ROOT}" ]; then
        BUILD_ROOT="${REPO_ROOT}/build"
    fi
fi

XCFRAMEWORK="${BUILD_ROOT}/iOS/VLCKit.xcframework"
RELEASE_DIR="${MUSICFREE_VLCKIT_RELEASE_ROOT:-${BUILD_ROOT}/release}"
BUILD_ID=$(basename "${BUILD_ROOT}")
BUILD_ID=${BUILD_ID#build-audio-ios-}
ARCHIVE_NAME="${MUSICFREE_VLCKIT_ARCHIVE_NAME:-MusicFreeVLCKit-audio-ios-${BUILD_ID}.xcframework.zip}"
ARCHIVE_PATH="${RELEASE_DIR}/${ARCHIVE_NAME}"

MUSICFREE_VLCKIT_BUILD_ROOT="${BUILD_ROOT}" \
    MUSICFREE_VLCKIT_RELEASE_ROOT="${RELEASE_DIR}" \
    "${SCRIPT_DIR}/generate-build-metadata.sh"

stage_dir=$(mktemp -d "${TMPDIR:-/private/tmp}/musicfree-vlckit-package.XXXXXX")
trap 'rm -rf "${stage_dir}"' EXIT HUP INT TERM
mkdir -p "${RELEASE_DIR}"
if [ ! -d "${XCFRAMEWORK}" ]; then
    printf '%s\n' "missing XCFramework: ${XCFRAMEWORK}" >&2
    exit 1
fi
cp -R "${XCFRAMEWORK}" "${stage_dir}/VLCKit.xcframework"
# Normalize archive metadata so repeated packaging of the same XCFramework
# produces the same SwiftPM checksum.
find "${stage_dir}/VLCKit.xcframework" -exec touch -t 202601010000 {} +

archive_tmp="${stage_dir}/${ARCHIVE_NAME}"
(CDPATH= cd -- "${stage_dir}" && zip -r -X "${archive_tmp}" VLCKit.xcframework >/dev/null)
mv "${archive_tmp}" "${ARCHIVE_PATH}"

swift_checksum=$(swift package compute-checksum "${ARCHIVE_PATH}")
printf '%s\n' "${swift_checksum}" > "${RELEASE_DIR}/swiftpm-checksum.txt"
shasum -a 256 "${ARCHIVE_PATH}" > "${RELEASE_DIR}/checksums.txt"

MUSICFREE_VLCKIT_BUILD_ROOT="${BUILD_ROOT}" \
    MUSICFREE_VLCKIT_RELEASE_ROOT="${RELEASE_DIR}" \
    "${SCRIPT_DIR}/generate-compliance.sh"

MUSICFREE_VLCKIT_BUILD_ROOT="${BUILD_ROOT}" \
    MUSICFREE_VLCKIT_RELEASE_ROOT="${RELEASE_DIR}" \
    "${SCRIPT_DIR}/verify-swiftpm-consumer.sh"

# Include the final immutable archive hash in the manifest after packaging.
MUSICFREE_VLCKIT_BUILD_ROOT="${BUILD_ROOT}" \
    MUSICFREE_VLCKIT_RELEASE_ROOT="${RELEASE_DIR}" \
    "${SCRIPT_DIR}/generate-build-metadata.sh"

printf '%s\n' "archive=${ARCHIVE_PATH}"
printf '%s\n' "swiftpm_checksum=${swift_checksum}"
