#!/bin/sh

set -eu

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
    printf '%s\n' "usage: $0 <owner/repository> <release-tag> <archive-name> <checksum> [manifest]" >&2
    exit 64
fi

repository=$1
release_tag=$2
archive_name=$3
checksum=$4
manifest=${5:-Package.swift}

if ! printf '%s\n' "${repository}" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
    printf '%s\n' "invalid GitHub repository: ${repository}" >&2
    exit 64
fi

# SwiftPM release tags must be semantic versions. Requiring a pre-release
# suffix prevents this engineering build from looking like a stable release.
if ! printf '%s\n' "${release_tag}" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*$'; then
    printf '%s\n' "release tag must be a SemVer pre-release, for example 4.0.0-audio.20260814.1" >&2
    exit 64
fi

if ! printf '%s\n' "${archive_name}" | grep -Eq '^[A-Za-z0-9._-]+\.xcframework\.zip$'; then
    printf '%s\n' "invalid XCFramework archive name: ${archive_name}" >&2
    exit 64
fi

if ! printf '%s\n' "${checksum}" | grep -Eq '^[0-9a-f]{64}$'; then
    printf '%s\n' "invalid SwiftPM checksum" >&2
    exit 64
fi

if [ ! -f "${manifest}" ]; then
    printf '%s\n' "missing manifest: ${manifest}" >&2
    exit 66
fi

package_url="https://github.com/${repository}/releases/download/${release_tag}/${archive_name}"

PACKAGE_URL="${package_url}" SWIFTPM_CHECKSUM="${checksum}" /usr/bin/ruby - "${manifest}" <<'RUBY'
manifest = ARGV.fetch(0)
source = File.read(manifest)
pattern = /(\.binaryTarget\(\s*name:\s*"VLCKit",\s*url:\s*)"[^"]+"(,\s*checksum:\s*)"[^"]+"(\s*\))/m

abort "expected exactly one VLCKit binary target in #{manifest}" unless source.scan(pattern).length == 1

updated = source.sub(pattern) do
  match = Regexp.last_match
  %(#{match[1]}"#{ENV.fetch("PACKAGE_URL")}"#{match[2]}"#{ENV.fetch("SWIFTPM_CHECKSUM")}"#{match[3]})
end
File.write(manifest, updated)
RUBY

printf '%s\n' "updated ${manifest}"
printf '%s\n' "url=${package_url}"
printf '%s\n' "checksum=${checksum}"
