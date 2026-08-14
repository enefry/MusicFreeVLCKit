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

mkdir -p "${RELEASE_ROOT}/third-party-licenses"

/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
REPO_ROOT="${REPO_ROOT}" BUILD_ROOT="${BUILD_ROOT}" RELEASE_ROOT="${RELEASE_ROOT}" \
/usr/bin/ruby -rjson -rdigest -rfileutils -rpathname -e '
  repo_root = ENV.fetch("REPO_ROOT")
  build_root = ENV.fetch("BUILD_ROOT")
  release_root = ENV.fetch("RELEASE_ROOT")
  manifest = JSON.parse(File.read(File.join(release_root, "build-manifest.json")))
  lock = JSON.parse(File.read(File.join(repo_root, "Config", "sources.lock.json")))
  vlc_root = File.join(repo_root, "libvlc", "vlc")
  license_file = lambda do |filename|
    Dir.glob(File.join(vlc_root, "contrib", "contrib-*", "**", filename))
      .select { |path| File.file?(path) }
      .sort
      .first
  end

  license_map = {
    "ffmpeg" => "LGPL-2.1-or-later",
    "flac" => "BSD-3-Clause OR LGPL-2.1-or-later",
    "ogg" => "BSD-3-Clause",
    "opus" => "BSD-3-Clause",
    "vorbis" => "BSD-3-Clause",
    "soxr" => "LGPL-2.1-or-later",
    "taglib" => "LGPL-2.1-or-later",
    "ebml" => "LGPL-2.1-or-later",
    "matroska" => "LGPL-2.1-or-later",
    "smb2" => "LGPL-2.1-or-later",
    "nfs" => "LGPL-2.1-or-later",
    "zlib" => "Zlib"
  }

  package = lambda do |id, name, version, license, source|
    {
      "SPDXID" => "SPDXRef-#{id}",
      "name" => name,
      "versionInfo" => version,
      "downloadLocation" => source || "NOASSERTION",
      "filesAnalyzed" => false,
      "licenseConcluded" => license,
      "licenseDeclared" => license,
      "copyrightText" => "NOASSERTION",
      "supplier" => "NOASSERTION"
    }
  end

  packages = []
  packages << package.call(
    "VLCKit", "MusicFreeVLCKit VLCKit wrapper", manifest.dig("source", "vlckit_commit"),
    "LGPL-2.1-or-later", lock.dig("vlckit", "repository")
  )
  packages << package.call(
    "LibVLC", "VideoLAN libVLC", manifest.dig("source", "libvlc_patched_commit"),
    "LGPL-2.1-or-later", lock.dig("libvlc", "repository")
  )
  lock.fetch("contrib").each do |name, details|
    version = details["version"] || details["git_commit"] || "NOASSERTION"
    packages << package.call(
      "Contrib-#{name.gsub(/[^A-Za-z0-9]/, "-")}", "#{name} contrib", version,
      license_map.fetch(name, "NOASSERTION"), "NOASSERTION"
    )
  end

  license_sources = {
    "MusicFreeVLCKit-LGPL-2.1.txt" => [File.join(repo_root, "COPYING"), File.join(vlc_root, "COPYING.LIB")].find { |path| File.file?(path) },
    "libVLC-COPYING.LIB" => File.join(vlc_root, "COPYING.LIB"),
    "FFmpeg-COPYING.LGPLv2.1" => license_file.call("COPYING.LGPLv2.1"),
    "FLAC-COPYING.Xiph" => license_file.call("COPYING.Xiph"),
    "Ogg-COPYING" => license_file.call("COPYING"),
    "Opus-COPYING" => license_file.call("COPYING"),
    "Vorbis-COPYING" => license_file.call("COPYING"),
    "SoXr-COPYING.LGPL" => license_file.call("COPYING.LGPL"),
    "TagLib-COPYING.LGPL" => license_file.call("COPYING.LGPL"),
    "EBML-LICENSE.LGPL" => license_file.call("LICENSE.LGPL"),
    "Matroska-LICENSE.LGPL" => license_file.call("LICENSE.LGPL"),
    "SMB2-COPYING" => license_file.call("COPYING"),
    "NFS-COPYING" => license_file.call("COPYING"),
    "zlib-LICENSE" => license_file.call("LICENSE")
  }

  copied_licenses = []
  license_sources.each do |name, source|
    next unless File.file?(source)
    destination = File.join(release_root, "third-party-licenses", name)
    FileUtils.cp(source, destination)
    copied_licenses << {
      "file" => File.join("third-party-licenses", name),
      "source" => Pathname.new(source).relative_path_from(Pathname.new(repo_root)).to_s,
      "sha256" => Digest::SHA256.file(destination).hexdigest,
      "size_bytes" => File.size(destination)
    }
  end

  patches = Dir.glob(File.join(repo_root, "libvlc", "patches", "*.patch")).sort.map do |path|
    {
      "path" => Pathname.new(path).relative_path_from(Pathname.new(repo_root)).to_s,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "size_bytes" => File.size(path)
    }
  end

  sbom = {
    "spdxVersion" => "SPDX-2.3",
    "dataLicense" => "CC0-1.0",
    "SPDXID" => "SPDXRef-DOCUMENT",
    "name" => "MusicFreeVLCKit audio iOS #{File.basename(build_root)}",
    "documentNamespace" => "https://github.com/enefry/MusicFreeVLCKit/sbom/#{File.basename(build_root)}",
    "creationInfo" => {
      "created" => "2026-08-14T00:00:00Z",
      "creators" => ["Tool: MusicFreeVLCKit generate-compliance.sh"]
    },
    "documentDescribes" => packages.map { |entry| entry["SPDXID"] },
    "packages" => packages,
    "annotations" => [
      {
        "annotationDate" => "2026-08-14T00:00:00Z",
        "annotationType" => "OTHER",
        "annotator" => "Tool: MusicFreeVLCKit generate-compliance.sh",
        "SPDXREF" => "SPDXRef-DOCUMENT",
        "comment" => "The audio profile disables GPL/nonfree FFmpeg components; legal review must verify the final object graph before distribution."
      }
    ]
  }

  compliance = {
    "schema_version" => 1,
    "status" => "generated-unreviewed",
    "build_root" => File.basename(build_root),
    "sbom" => {
      "format" => "SPDX-2.3",
      "path" => "sbom.spdx.json",
      "package_count" => packages.length,
      "status" => "generated"
    },
    "license_materials" => {
      "lgpl_text" => "third-party-licenses/MusicFreeVLCKit-LGPL-2.1.txt",
      "libvlc_lgpl_text" => "third-party-licenses/libVLC-COPYING.LIB",
      "third_party_notice_index" => "THIRD-PARTY-NOTICES.md",
      "copied_license_files" => copied_licenses
    },
    "corresponding_source" => {
      "vlckit_commit" => manifest.dig("source", "vlckit_commit"),
      "libvlc_base_commit" => lock.dig("libvlc", "base_commit"),
      "libvlc_patched_commit" => manifest.dig("source", "libvlc_patched_commit"),
      "patches" => patches,
      "sources_lock" => "Config/sources.lock.json",
      "build_script" => "compileAndBuildVLCKit.sh",
      "relinkable_object_files" => {
        "status" => "open",
        "included_in_this_artifact" => false,
        "reason" => "The XCFramework is a dynamic wrapper with a statically linked libVLC/contrib graph; complete relinkable object files and a legal distribution decision are still required."
      }
    },
    "gates" => {
      "sbom_generated" => "passed",
      "license_texts_collected" => copied_licenses.length >= 10 ? "passed" : "partial",
      "source_provenance" => "partial",
      "relink_material" => "open",
      "legal_review" => "open"
    },
    "notes" => [
      "This is an engineering inventory, not legal advice.",
      "NOASSERTION and provisional license expressions require review against the exact linked objects and upstream notices.",
      "The source checkout and patch hashes are recorded, but a complete corresponding-source archive is not bundled by this local build."
    ]
  }

  File.write(File.join(release_root, "sbom.spdx.json"), JSON.pretty_generate(sbom) + "\n")
  File.write(File.join(release_root, "compliance.json"), JSON.pretty_generate(compliance) + "\n")
  File.write(File.join(release_root, "THIRD-PARTY-NOTICES.md"), <<~MD)
    # MusicFreeVLCKit Third-Party Notices

    Build: `#{File.basename(build_root)}`

    This inventory was generated from `Config/sources.lock.json` and the fixed
    contrib checkout. It is engineering evidence, not a legal opinion. The
    exact linked object graph and final distribution terms still require review.

    ## Components

    | Component | Version or revision | Provisional license |
    | --- | --- | --- |
    #{packages.map { |entry| "| #{entry["name"]} | #{entry["versionInfo"]} | #{entry["licenseDeclared"]} |" }.join("\n")}

    ## License files

    #{copied_licenses.map { |entry| "- `#{entry["file"]}` (source `#{entry["source"]}`, SHA-256 `#{entry["sha256"]}`)" }.join("\n")}

    GPL texts remain in the FFmpeg source checkout because they are part of the
    upstream source distribution. The audio profile was configured with GPL and
    nonfree components disabled; that binary claim is covered by the static
    audit, but must be rechecked for every future build.
  MD
  File.write(File.join(release_root, "RELINKING.md"), <<~MD)
    # LGPL Relinking Materials

    This `#{File.basename(build_root)}` candidate is a dynamic `VLCKit.framework` wrapper that contains a
    statically linked libVLC and contrib object graph. The following provenance
    is recorded for a future corresponding-source/relink package:

    - VLCKit commit: `#{manifest.dig("source", "vlckit_commit")}`
    - libVLC base commit: `#{lock.dig("libvlc", "base_commit")}`
    - libVLC patched commit: `#{manifest.dig("source", "libvlc_patched_commit")}`
    - Patch hashes: see `compliance.json`
    - Build profile: `Config/audio-ios.env`
    - Build command: `#{manifest["build_command"]}`

    Complete corresponding source, the exact build inputs, and complete
    relinkable object files are not included in this local release directory.
    Therefore the LGPL/static-link distribution gate is **open** and this
    document must not be treated as legal approval.
  MD
  File.write(File.join(release_root, "LICENSE-STATUS.md"), <<~MD)
    # License Status

    - SBOM: generated (`sbom.spdx.json`)
    - LGPL texts: copied (`third-party-licenses/`)
    - Corresponding source archive: not generated
    - Relinkable object files: not included
    - Legal/release review: open
  MD
'
