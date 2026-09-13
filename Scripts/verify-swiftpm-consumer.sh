#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
if [ -n "${MUSICFREE_VLCKIT_BUILD_ROOT:-}" ]; then
    BUILD_ROOT="${MUSICFREE_VLCKIT_BUILD_ROOT}"
else
    BUILD_ROOT=$(find "${REPO_ROOT}" -maxdepth 1 -type d -name 'build-audio-ios-*' -print | sort | tail -n 1)
    if [ -z "${BUILD_ROOT}" ]; then
        BUILD_ROOT="${REPO_ROOT}/build-audio-ios"
    fi
fi
BUILD_ROOT=$(CDPATH= cd -- "${BUILD_ROOT}" && pwd)
RELEASE_ROOT=${MUSICFREE_VLCKIT_RELEASE_ROOT:-${BUILD_ROOT}/release}
RELEASE_ROOT=$(CDPATH= cd -- "${RELEASE_ROOT}" && pwd)
XCFRAMEWORK="${BUILD_ROOT}/iOS/VLCKit.xcframework"
ARCHIVE=$(find "${RELEASE_ROOT}" -maxdepth 1 -name '*.xcframework.zip' -print | sort | tail -n 1)
DEPLOYMENT_TARGET=$(awk '/^deployment_target:/ { print $2; exit }' "${REPO_ROOT}/Config/required-capabilities.yml")
DEPLOYMENT_TARGET=$(printf '%s' "${DEPLOYMENT_TARGET}" | tr -d '"')

if [ ! -d "${XCFRAMEWORK}" ] || [ -z "${ARCHIVE}" ] || [ ! -f "${ARCHIVE}" ]; then
    printf '%s\n' "missing XCFramework or archive under ${BUILD_ROOT}" >&2
    exit 1
fi
if ! printf '%s\n' "${DEPLOYMENT_TARGET}" | grep -Eq '^[0-9]+\.[0-9]+$'; then
    printf '%s\n' "invalid iOS deployment target: ${DEPLOYMENT_TARGET}" >&2
    exit 1
fi

verify_binary_minimum_os() {
    binary=$1
    expected_architectures=$2
    build_versions=$(xcrun vtool -show-build "${binary}")
    actual_matches=$(printf '%s\n' "${build_versions}" | awk -v target="${DEPLOYMENT_TARGET}" '$1 == "minos" && $2 == target { count += 1 } END { print count + 0 }')
    if [ "${actual_matches}" -ne "${expected_architectures}" ]; then
        printf '%s\n' "unexpected minimum OS version in ${binary}; expected ${expected_architectures} slices at iOS ${DEPLOYMENT_TARGET}" >&2
        printf '%s\n' "${build_versions}" >&2
        exit 1
    fi
}

verify_binary_minimum_os \
    "${XCFRAMEWORK}/ios-arm64/VLCKit.framework/VLCKit" \
    1
verify_binary_minimum_os \
    "${XCFRAMEWORK}/ios-arm64_x86_64-simulator/VLCKit.framework/VLCKit" \
    2

stage_root=$(mktemp -d "${TMPDIR:-/private/tmp}/musicfree-vlckit-consumer.XXXXXX")
trap 'rm -rf "${stage_root}"' EXIT HUP INT TERM
cp -R "${REPO_ROOT}/Tests/SwiftPMConsumer/." "${stage_root}/"
mkdir -p "${stage_root}/Artifacts" "${stage_root}/ModuleCache"
cp -R "${XCFRAMEWORK}" "${stage_root}/Artifacts/VLCKit.xcframework"
CDPATH= cd -- "${stage_root}"

checksum=$(swift package compute-checksum "${ARCHIVE}")
archive_sha256=$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')
expected_checksum=$(cat "${RELEASE_ROOT}/swiftpm-checksum.txt")
if [ "${checksum}" != "${expected_checksum}" ] || [ "${checksum}" != "${archive_sha256}" ]; then
    printf '%s\n' "checksum mismatch" >&2
    exit 1
fi

archive_listing="${stage_root}/archive-files.txt"
unzip -Z1 "${ARCHIVE}" > "${archive_listing}"
expected_license_count=$(find "${RELEASE_ROOT}/third-party-licenses" -type f | wc -l | tr -d ' ')
archive_license_count=$(awk '/^VLCKit\.xcframework\/LICENSES\/third-party-licenses\/[^\/]+$/ { count += 1 } END { print count + 0 }' "${archive_listing}")
if [ "${archive_license_count}" != "${expected_license_count}" ]; then
    printf '%s\n' "license count mismatch: archive=${archive_license_count}, expected=${expected_license_count}" >&2
    exit 1
fi
for license_path in "${RELEASE_ROOT}/third-party-licenses"/*
do
    [ -f "${license_path}" ] || continue
    packaged_path="VLCKit.xcframework/LICENSES/third-party-licenses/$(basename "${license_path}")"
    if ! grep -Fxq "${packaged_path}" "${archive_listing}"; then
        printf '%s\n' "missing packaged license: ${packaged_path}" >&2
        exit 1
    fi
done
for required_file in \
    VLCKit.xcframework/LICENSES/THIRD-PARTY-NOTICES.md \
    VLCKit.xcframework/LICENSES/LICENSE-STATUS.md \
    VLCKit.xcframework/LICENSES/RELINKING.md \
    VLCKit.xcframework/LICENSES/compliance.json \
    VLCKit.xcframework/LICENSES/sbom.spdx.json
do
    if ! grep -Fxq "${required_file}" "${archive_listing}"; then
        printf '%s\n' "missing packaged license material: ${required_file}" >&2
        exit 1
    fi
done

dump_status=passed
if ! SWIFT_MODULECACHE_PATH="${stage_root}/ModuleCache" \
    CLANG_MODULE_CACHE_PATH="${stage_root}/ModuleCache" \
    swift package dump-package --disable-sandbox > "${stage_root}/dump-package.json" 2> "${stage_root}/dump-package.stderr"; then
    dump_status=failed
fi

build_status=passed
if ! SWIFT_MODULECACHE_PATH="${stage_root}/ModuleCache" \
    CLANG_MODULE_CACHE_PATH="${stage_root}/ModuleCache" \
    swift build --disable-sandbox --configuration release \
        --triple "arm64-apple-ios${DEPLOYMENT_TARGET}" \
        --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
        --product MusicFreeVLCKitConsumer > "${stage_root}/build.log" 2>&1; then
    build_status=failed
fi

artifact="${stage_root}/.build/arm64-apple-ios/release/MusicFreeVLCKitConsumer"
link_status=failed
[ -f "${artifact}" ] && link_status=passed

build_id=$(basename "${BUILD_ROOT}")
build_id=${build_id#build-audio-ios-}
BUILD_ID="${build_id}" \
ARCHIVE_PATH="${ARCHIVE}" \
ARCHIVE_SHA256="${archive_sha256}" \
SWIFTPM_CHECKSUM="${checksum}" \
ARCHIVE_LICENSE_COUNT="${archive_license_count}" \
PACKAGE_DUMP_STATUS="${dump_status}" \
BUILD_STATUS="${build_status}" \
LINK_STATUS="${link_status}" \
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
BUILD_LOG_PATH="${stage_root}/build.log" \
RELEASE_ROOT="${RELEASE_ROOT}" \
/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
BUILD_ID="${build_id}" \
ARCHIVE_PATH="${ARCHIVE}" \
ARCHIVE_SHA256="${archive_sha256}" \
SWIFTPM_CHECKSUM="${checksum}" \
ARCHIVE_LICENSE_COUNT="${archive_license_count}" \
PACKAGE_DUMP_STATUS="${dump_status}" \
BUILD_STATUS="${build_status}" \
LINK_STATUS="${link_status}" \
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
BUILD_LOG_PATH="${stage_root}/build.log" \
RELEASE_ROOT="${RELEASE_ROOT}" \
/usr/bin/ruby -rjson -rdigest -e '
  release_root = ENV.fetch("RELEASE_ROOT")
  build_log = ENV.fetch("BUILD_LOG_PATH")
  log_sha256 = File.file?(build_log) ? Digest::SHA256.file(build_log).hexdigest : nil
  evidence = {
    "schema_version" => 1,
    "status" => ENV.fetch("BUILD_STATUS") == "passed" && ENV.fetch("LINK_STATUS") == "passed" && ENV.fetch("PACKAGE_DUMP_STATUS") == "passed" ? "passed" : "failed",
    "consumer" => "Tests/SwiftPMConsumer",
    "build_root" => "build-audio-ios-#{ENV.fetch("BUILD_ID")}",
    "archive" => File.basename(ENV.fetch("ARCHIVE_PATH")),
    "archive_sha256" => ENV.fetch("ARCHIVE_SHA256"),
    "swiftpm_checksum" => ENV.fetch("SWIFTPM_CHECKSUM"),
    "checksum_matches_archive_sha256" => ENV.fetch("ARCHIVE_SHA256") == ENV.fetch("SWIFTPM_CHECKSUM"),
    "packaged_license_file_count" => ENV.fetch("ARCHIVE_LICENSE_COUNT").to_i,
    "licenses_packaged" => ENV.fetch("ARCHIVE_LICENSE_COUNT").to_i > 0,
    "package_dump" => ENV.fetch("PACKAGE_DUMP_STATUS"),
    "swift_build" => ENV.fetch("BUILD_STATUS"),
    "ios_link" => ENV.fetch("LINK_STATUS"),
    "target" => "arm64-apple-ios#{ENV.fetch("DEPLOYMENT_TARGET")}",
    "sdk" => `xcrun --sdk iphoneos --show-sdk-version`.strip,
    "notes" => [
      "The consumer imports VLCKit and references its library, media, player, equalizer, playback-rate, volume, and mute APIs.",
      "The SwiftPM manifest, XCFramework slices, and consumer build all target iOS #{ENV.fetch("DEPLOYMENT_TARGET")}.",
      "The framework is built with the installed iPhoneOS SDK, which may be newer than its deployment target."
    ],
    "build_log_sha256" => log_sha256,
    "build_log_bytes" => File.file?(build_log) ? File.size(build_log) : 0
  }
  File.write(File.join(release_root, "swiftpm-consumer.json"), JSON.pretty_generate(evidence) + "\n")
  abort "SwiftPM consumer failed" unless evidence["status"] == "passed"
'
