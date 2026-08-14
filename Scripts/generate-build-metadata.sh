#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

exec /usr/bin/env -i \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    BUILD_ROOT="${BUILD_ROOT:-}" \
    MUSICFREE_VLCKIT_BUILD_ROOT="${MUSICFREE_VLCKIT_BUILD_ROOT:-}" \
    MUSICFREE_VLC_BUILD_ROOT="${MUSICFREE_VLC_BUILD_ROOT:-}" \
    MUSICFREE_VLCKIT_RELEASE_ROOT="${MUSICFREE_VLCKIT_RELEASE_ROOT:-}" \
    MUSICFREE_VLCKIT_BASELINE_BINARY="${MUSICFREE_VLCKIT_BASELINE_BINARY:-}" \
    /usr/bin/ruby -rjson -rdigest -rfileutils -ropen3 -rpathname - "$REPO_ROOT" <<'RUBY'
repo_root = ARGV.fetch(0)
requested_build_root = ENV["MUSICFREE_VLCKIT_BUILD_ROOT"] || ENV["BUILD_ROOT"]
build_root = if requested_build_root && !requested_build_root.empty?
  File.expand_path(requested_build_root, repo_root)
else
  candidates = Dir.glob(File.join(repo_root, "build-audio-ios-*"))
    .select { |path| File.directory?(path) }
    .sort_by { |path| [File.mtime(path), path] }
  candidates.last || File.join(repo_root, "build")
end
xcframework = File.join(build_root, "iOS", "VLCKit.xcframework")
release_root = if ENV["MUSICFREE_VLCKIT_RELEASE_ROOT"] && !ENV.fetch("MUSICFREE_VLCKIT_RELEASE_ROOT").empty?
  File.expand_path(ENV.fetch("MUSICFREE_VLCKIT_RELEASE_ROOT"), repo_root)
else
  File.join(build_root, "release")
end

abort "missing XCFramework: #{xcframework}" unless Dir.exist?(xcframework)

def command(*args)
  output, status = Open3.capture2e({ "TMPDIR" => "/tmp", "DARWIN_USER_TEMP_DIR" => "/tmp" }, *args)
  [output, status.success?]
end

def required_command(*args)
  output, ok = command(*args)
  abort "command failed: #{args.join(' ')}\n#{output}" unless ok
  output
end

def sha256_file(path)
  Digest::SHA256.file(path).hexdigest
end

def sha256_bytes(value)
  Digest::SHA256.hexdigest(value)
end

def relative(path, root)
  return nil if path.nil?
  Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
end

def normalize(value, root)
  value.to_s
    .gsub(root, "$WORKSPACE")
    .gsub("/Applications/Xcode.app/Contents/Developer", "$DEVELOPER_DIR")
end

def directory_size(path)
  Dir.glob(File.join(path, "**", "*"), File::FNM_DOTMATCH)
    .select { |entry| File.file?(entry) }
    .reduce(0) { |total, entry| total + File.size(entry) }
end

def parse_plist(path)
  output, ok = command("/usr/bin/plutil", "-convert", "json", "-o", "-", "--", path)
  abort "cannot parse plist #{path}: #{output}" unless ok
  JSON.parse(output)
end

def git_output(root, *args)
  required_command("/usr/bin/git", "-C", root, *args).strip
end

def git_state(root)
  status = git_output(root, "status", "--short")
  diff, = command("/usr/bin/git", "-C", root, "diff", "--binary")
  tracked = git_output(root, "ls-files", "--others", "--exclude-standard")
  {
    "dirty" => !status.empty?,
    "status" => status.empty? ? [] : status.lines.map(&:chomp),
    "tracked_diff_sha256" => sha256_bytes(diff),
    "untracked_paths" => tracked.empty? ? [] : tracked.lines.map(&:chomp)
  }
end

def uuid_by_arch(path)
  output, ok = command("/usr/bin/dwarfdump", "--uuid", path)
  return {} unless ok
  output.lines.map do |line|
    match = line.match(/UUID: ([0-9A-F-]+) \(([^)]+)\)/)
    match ? [match[2], match[1]] : nil
  end.compact.to_h
end

def modules_from_static_list(path)
  File.read(path).scan(/vlc_entry__([A-Za-z0-9_]+)/).flatten.uniq
end

def parse_policy(path)
  forbidden = []
  allowed = []
  required = []
  section = nil
  File.readlines(path).each do |line|
    section = "allowed" if line.start_with?("allowed_modules:")
    section = "required" if line.start_with?("required_modules:")
    section = "forbidden" if line.start_with?("forbidden_modules:")
    if section == "allowed" && (match = line.match(/^\s+-\s+([^\s#]+)\s*$/))
      allowed << match[1]
    elsif section == "required" && (match = line.match(/^\s+-\s+([^\s#]+)\s*$/))
      required << match[1]
    elsif section == "forbidden" && (match = line.match(/^\s+-\s+name:\s*([^\s#]+)\s*$/))
      forbidden << match[1]
    end
  end
  [allowed.uniq, required.uniq, forbidden.uniq]
end

def ffmpeg_components(config_path, kind)
  return [] unless config_path && File.file?(config_path)
  regex = /^CONFIG_([A-Z0-9_]+)_#{Regexp.escape(kind)}=yes$/
  File.readlines(config_path).map do |line|
    match = line.chomp.match(regex)
    match && match[1]
  end.compact.uniq.sort
end

def ffmpeg_configuration(config_path, root)
  return nil unless config_path && File.file?(config_path)
  line = File.readlines(config_path).find { |entry| entry.start_with?("FFMPEG_CONFIGURATION=") }
  line && normalize(line.split("=", 2).last.chomp, root)
end

def ffmpeg_config_macro(config_path, name)
  return nil unless config_path && File.file?(config_path)
  lines = File.readlines(config_path)
  if lines.any? { |line| line.chomp == "CONFIG_#{name}=yes" || line.chomp == "#define CONFIG_#{name} 1" }
    true
  elsif lines.any? { |line| line.chomp == "!CONFIG_#{name}=yes" || line.chomp == "#define CONFIG_#{name} 0" }
    false
  else
    nil
  end
end

def first_defined_macro(*values)
  values.find { |value| !value.nil? }
end

def report_status(path)
  return "not-run" unless File.file?(path)
  value = JSON.parse(File.read(path))
  value.fetch("status", "invalid")
rescue JSON::ParserError, KeyError
  "invalid"
end

def matching_symbols(symbols, pattern)
  symbols.select { |symbol| pattern.match?(symbol.sub(/\A_/, "")) }.first(500)
end

def symbol_audit(path, architectures)
  nm_results = architectures.map do |architecture|
    command("/usr/bin/nm", "-arch", architecture, path)
  end
  nm_output = nm_results.map(&:first).join
  nm_ok = nm_results.all?(&:last)
  exports_output, exports_ok = command("/usr/bin/dyld_info", "-exports", path)
  strings_output, strings_ok = command("/usr/bin/strings", path)
  symbol_table_symbols = nm_output.lines.map do |line|
    fields = line.split
    next if fields.length < 3
    next if fields[-2].match?(/\A[Uu]\z/)
    fields.last
  end.compact.uniq
  exported_symbols = exports_output.lines.map do |line|
    match = line.match(/^\s*0x[0-9A-Fa-f]+\s+(\S+)\s*$/)
    match && match[1]
  end.compact.uniq
  ffmpeg_video_pattern = /\A_?(?:av_(?:.*(?:video|subtitle)|video)|avformat_.*(?:video|subtitle)|ff_(?:.*(?:video|subtitle)|.*(?:h264|hevc|vp9|av1|vvc|mjpeg|prores|dnxhd|vc1|evc|apv)))/i
  core_video_pattern = /\A(?:libvlc_(?:video|picture|renderer).*|libvlc_media_player_.*video.*|vlc_(?:input_decoder_.*spu|player_.*(?:vout|video|renderer|subtitle)|video_context.*|renderer_item.*|render_subpicture.*|spu_.*)|VideoInit|VideoFilterCallback|OpenVideo|SetupVideoES|ImageQueueVideo|ModuleThread_(?:NewVideoBuffer|QueueVideo|UpdateVideoFormat)(?:\.cold\.\d+)?|VoutVideoFilter.*|decoder_UpdateVideo(?:Format|Output)|es_format_InitFromVideo|video_format_.*|filter_chain_(?:NewVideo|Video.*))/i
  video_codec_descriptor_pattern = /\A(?:vlc_fourcc_GetCodec|vlc_fourcc_GetChromaDescription|av_parse_video_rate|ff_codec_movvideo_tags)\z/i
  symbol_table_ffmpeg_video_symbols = matching_symbols(symbol_table_symbols, ffmpeg_video_pattern)
  symbol_table_core_video_symbols = matching_symbols(symbol_table_symbols, core_video_pattern)
  symbol_table_video_codec_descriptor_symbols = matching_symbols(symbol_table_symbols, video_codec_descriptor_pattern)
  ffmpeg_video_symbols = matching_symbols(exported_symbols, ffmpeg_video_pattern)
  core_video_symbols = matching_symbols(exported_symbols, core_video_pattern)
  video_codec_descriptor_symbols = matching_symbols(exported_symbols, video_codec_descriptor_pattern)
  forbidden_symbols = (ffmpeg_video_symbols + core_video_symbols).uniq
  internal_video_symbols = (symbol_table_core_video_symbols + symbol_table_video_codec_descriptor_symbols).uniq
  strings = strings_output.lines.map(&:strip).select do |line|
    line.match?(/\b(?:sftp|udp|rtp|h264|hevc|vp9|av1|videotoolbox|subtitle|renderer|video output)\b/i)
  end.uniq.first(100)
  {
    "nm_succeeded" => nm_ok,
    "nm_architectures" => architectures,
    "dyld_exports_succeeded" => exports_ok,
    "exported_symbol_count" => exported_symbols.length,
    "ffmpeg_video_symbols" => ffmpeg_video_symbols,
    "core_video_symbols" => core_video_symbols,
    "video_codec_descriptor_symbols" => video_codec_descriptor_symbols,
    "forbidden_video_symbols" => forbidden_symbols,
    "symbol_table_ffmpeg_video_symbols" => symbol_table_ffmpeg_video_symbols,
    "symbol_table_core_video_symbols" => symbol_table_core_video_symbols,
    "symbol_table_video_codec_descriptor_symbols" => symbol_table_video_codec_descriptor_symbols,
    "internal_video_symbols" => internal_video_symbols,
    "forbidden_video_symbols_passed" => exports_ok && forbidden_symbols.empty?,
    "internal_video_symbol_audit_passed" => nm_ok && internal_video_symbols.empty?,
    "strings_succeeded" => strings_ok,
    "representative_video_or_non_whitelist_strings" => strings
  }
end

def public_header_audit(xcframework, root)
  headers = Dir.glob(File.join(xcframework, "**", "Headers", "**", "*")).select { |path| File.file?(path) }
  forbidden = headers.select do |path|
    path.match?(%r{/Headers/vlc/}) ||
      File.basename(path).match?(/\A(?:VLCVideo|VLCFilter|VLCAdjustFilter|VLCRenderer|VLCMediaSlave|VLCMediaDownloader|VLCMediaDiscoverer|VLCMediaListPlayer|VLCMediaThumbnailer|VLCTranscoder|VLCStream|VLCDialogProvider)/)
  end
  {
    "header_count" => headers.length,
    "headers" => headers.map { |path| relative(path, root) }.sort,
    "forbidden_headers" => forbidden.map { |path| relative(path, root) }.sort,
    "passed" => forbidden.empty?
  }
end

def dependencies(path)
  output, ok = command("/usr/bin/otool", "-L", path)
  return { "succeeded" => false, "libraries" => [] } unless ok
  libraries = output.lines.drop(1).map do |line|
    next if line.match?(/\(architecture [^)]+\):\s*\z/)
    match = line.match(/^\s*(\S+)\s+\(/)
    match && match[1]
  end.compact
  { "succeeded" => true, "libraries" => libraries }
end

source_lock_path = File.join(repo_root, "Config", "sources.lock.json")
source_lock = JSON.parse(File.read(source_lock_path))
vlc_root = File.join(repo_root, "libvlc", "vlc")
requested_vlc_build_root = ENV["MUSICFREE_VLC_BUILD_ROOT"]
vlc_build_root = if requested_vlc_build_root && !requested_vlc_build_root.empty?
  File.expand_path(requested_vlc_build_root, repo_root)
else
  candidates = Dir.glob(File.join(vlc_root, "audio-ios-build-*"))
    .select { |path| File.directory?(path) }
    .sort_by { |path| [File.mtime(path), path] }
  candidates.last || File.join(vlc_root, "audio-ios-build")
end

info = parse_plist(File.join(xcframework, "Info.plist"))
policy_allowed, policy_required, policy_forbidden = parse_policy(File.join(repo_root, "Config", "module-policy.yml"))

module_sources = {
  "device-arm64" => File.join(vlc_build_root, "build-iphoneos-arm64", "static-lib", "static-module-list.c"),
  "simulator-arm64" => File.join(vlc_build_root, "build-iphonesimulator-arm64", "static-lib", "static-module-list.c"),
  "simulator-x86_64" => File.join(vlc_build_root, "build-iphonesimulator-x86_64", "static-lib", "static-module-list.c")
}
modules_by_arch = module_sources.transform_values { |path| modules_from_static_list(path) }
common_modules = modules_by_arch.values.reduce { |memo, modules| memo & modules }
forbidden_matches = policy_forbidden.to_h do |forbidden|
  [forbidden, common_modules.select { |module_name| module_name.downcase.include?(forbidden.downcase) }]
end
required_missing = policy_required.reject { |required| common_modules.include?(required) }

find_ffmpeg_config = lambda do |pattern|
  Dir.glob(File.join(vlc_root, "contrib", pattern, "ffmpeg", "vlc_build", "ffbuild", "config.mak"))
    .select { |path| File.file?(path) }
    .sort
    .last
end
ffmpeg_sources = {
  "device-arm64" => find_ffmpeg_config.call("contrib-arm64-apple-iOS_*") ,
  "simulator-arm64" => find_ffmpeg_config.call("contrib-arm64-apple-iOS-Simulator_*") ,
  "simulator-x86_64" => find_ffmpeg_config.call("contrib-x86_64-apple-iOS-Simulator_*")
}
ffmpeg_audit = ffmpeg_sources.transform_values do |config_path|
  config_header_path = config_path && File.join(File.dirname(config_path), "..", "config.h")
  {
    "config_path" => relative(config_path, repo_root),
    "config_sha256" => File.file?(config_path) ? sha256_file(config_path) : nil,
    "configuration" => ffmpeg_configuration(config_path, repo_root),
    "config_header_path" => relative(config_header_path, repo_root),
    "config_header_sha256" => config_header_path && File.file?(config_header_path) ? sha256_file(config_header_path) : nil,
    "musicfree_audio_profile_macro" => config_path && File.file?(config_path) && File.read(config_path).include?("MUSICFREE_AUDIO_PROFILE"),
    "config_videotoolbox" => first_defined_macro(ffmpeg_config_macro(config_header_path, "VIDEOTOOLBOX"), ffmpeg_config_macro(config_path, "VIDEOTOOLBOX")),
    "config_small" => first_defined_macro(ffmpeg_config_macro(config_header_path, "SMALL"), ffmpeg_config_macro(config_path, "SMALL")),
    "config_hwaccels" => first_defined_macro(ffmpeg_config_macro(config_header_path, "HWACCELS"), ffmpeg_config_macro(config_path, "HWACCELS")),
    "enabled_decoders" => ffmpeg_components(config_path, "DECODER"),
    "enabled_parsers" => ffmpeg_components(config_path, "PARSER"),
    "enabled_demuxers" => ffmpeg_components(config_path, "DEMUXER"),
    "enabled_encoders" => ffmpeg_components(config_path, "ENCODER"),
    "enabled_muxers" => ffmpeg_components(config_path, "MUXER"),
    "enabled_filters" => ffmpeg_components(config_path, "FILTER"),
    "enabled_devices" => ffmpeg_components(config_path, "DEVICE"),
    "video_components_enabled" => %w[H264 HEVC VP9 AV1].product(%w[DECODER PARSER DEMUXER ENCODER MUXER]).map do |name, kind|
      "#{name}_#{kind}" if File.file?(config_path) && File.readlines(config_path).any? { |line| line.chomp == "CONFIG_#{name}_#{kind}=yes" }
    end.compact
  }
end

slice_metadata = info.fetch("AvailableLibraries").map do |library|
  identifier = library.fetch("LibraryIdentifier")
  slice_root = File.join(xcframework, identifier)
  binary = File.join(slice_root, library.fetch("BinaryPath"))
  dsym = File.join(slice_root, library.fetch("DebugSymbolsPath"), "VLCKit.framework.dSYM")
  dwarf = File.join(dsym, "Contents", "Resources", "DWARF", "VLCKit")
  arch_key = identifier == "ios-arm64" ? "device-arm64" : "simulator-arm64"
  module_keys = identifier == "ios-arm64" ? ["device-arm64"] : ["simulator-arm64", "simulator-x86_64"]
  binary_uuids = uuid_by_arch(binary)
  dsym_uuids = uuid_by_arch(dwarf)
  {
    "library_identifier" => identifier,
    "supported_platform" => library.fetch("SupportedPlatform"),
    "supported_platform_variant" => library["SupportedPlatformVariant"],
    "architectures" => library.fetch("SupportedArchitectures"),
    "framework_binary" => relative(binary, repo_root),
    "framework_binary_size_bytes" => File.size(binary),
    "framework_binary_sha256" => sha256_file(binary),
    "framework_size_bytes" => directory_size(File.join(slice_root, library.fetch("LibraryPath"))),
    "binary_uuids" => binary_uuids,
    "dsym" => {
      "path" => relative(dsym, repo_root),
      "dwarf_path" => relative(dwarf, repo_root),
      "dwarf_sha256" => sha256_file(dwarf),
      "dwarf_size_bytes" => File.size(dwarf),
      "uuids" => dsym_uuids,
      "matches_binary" => binary_uuids == dsym_uuids
    },
    "static_module_sources" => module_keys.map { |key| relative(module_sources.fetch(key), repo_root) },
    "static_module_count" => module_keys.map { |key| modules_by_arch.fetch(key).length }.uniq,
    "static_module_sha256" => module_keys.to_h { |key| [key, sha256_file(module_sources.fetch(key))] },
    "dependencies" => dependencies(binary),
    "symbol_audit" => symbol_audit(binary, library.fetch("SupportedArchitectures")),
    "ffmpeg_audit_arch_key" => arch_key
  }
end

tree_files = Dir.glob(File.join(xcframework, "**", "*")).select { |path| File.file?(path) }.sort.map do |path|
  { "path" => relative(path, repo_root), "size_bytes" => File.size(path), "sha256" => sha256_file(path) }
end
public_header_audit_result = public_header_audit(xcframework, repo_root)

framework_dependencies = slice_metadata.flat_map do |slice|
  slice.fetch("dependencies").fetch("libraries")
end.map do |dependency|
  dependency.sub(%r{^#{Regexp.escape(repo_root)}/}, "$WORKSPACE/")
end.uniq.sort
forbidden_frameworks = %w[VideoToolbox OpenGLES AVKit].select do |name|
  framework_dependencies.any? { |dependency| dependency.end_with?("/#{name}") }
end
release_archives = Dir.glob(File.join(release_root, "*.xcframework.zip")).sort
video_components_enabled = ffmpeg_audit.values.flat_map { |entry| entry.fetch("video_components_enabled") }.uniq.sort
all_dsym_match = slice_metadata.all? { |slice| slice.fetch("dsym").fetch("matches_binary") }
slice_layout_ok = info.fetch("AvailableLibraries").map { |entry| entry.fetch("LibraryIdentifier") }.sort == ["ios-arm64", "ios-arm64_x86_64-simulator"].sort
module_policy_ok = forbidden_matches.values.all?(&:empty?)
required_module_policy_ok = required_missing.empty?
ffmpeg_profile_ok = ffmpeg_audit.values.all? do |entry|
  entry.fetch("musicfree_audio_profile_macro") &&
    entry.fetch("config_videotoolbox") == false &&
    entry.fetch("config_small") == true &&
    entry.fetch("config_hwaccels") == false &&
    entry.fetch("video_components_enabled").empty?
end
symbol_policy_ok = slice_metadata.all? { |slice| slice.fetch("symbol_audit").fetch("forbidden_video_symbols_passed") }
internal_video_symbol_policy_ok = slice_metadata.all? { |slice| slice.fetch("symbol_audit").fetch("internal_video_symbol_audit_passed") }
framework_policy_ok = forbidden_frameworks.empty?
public_header_policy_ok = public_header_audit_result.fetch("passed")
static_audit_ok = slice_layout_ok && all_dsym_match && module_policy_ok && required_module_policy_ok && ffmpeg_profile_ok && symbol_policy_ok && internal_video_symbol_policy_ok && framework_policy_ok && public_header_policy_ok

validation_reports = {
  "local_format_matrix" => report_status(File.join(release_root, "format-matrix.json")),
  "network_protocol_matrix" => report_status(File.join(release_root, "network-protocol-matrix.json")),
  "no-grant-zero-network-evidence" => report_status(File.join(release_root, "zero-network-evidence.json")),
  "physical_device_playback" => report_status(File.join(release_root, "physical-device.json")),
  "swiftpm_consumer" => report_status(File.join(release_root, "swiftpm-consumer.json")),
  "second_clean_build_reproducibility" => report_status(File.join(release_root, "reproducibility.json")),
  "sbom_and_lgpl_release_materials" => report_status(File.join(release_root, "compliance.json"))
}
all_release_reports_passed = validation_reports.values.all? { |status| status == "passed" }
baseline_binary = ENV["MUSICFREE_VLCKIT_BASELINE_BINARY"]
device_slice = slice_metadata.find { |slice| slice.fetch("library_identifier") == "ios-arm64" }
size_comparison = if baseline_binary && !baseline_binary.empty? && File.file?(baseline_binary) && device_slice
  baseline_size = File.size(baseline_binary)
  candidate_size = device_slice.fetch("framework_binary_size_bytes")
  {
    "status" => "measured",
    "basis" => "iOS device arm64 VLCKit Mach-O",
    "baseline_reference" => "MUSICFREE_VLCKIT_BASELINE_BINARY",
    "baseline_size_bytes" => baseline_size,
    "candidate_size_bytes" => candidate_size,
    "reduction_bytes" => baseline_size - candidate_size,
    "reduction_percent" => ((baseline_size - candidate_size).to_f / baseline_size * 100).round(2)
  }
else
  { "status" => "not-run", "basis" => "iOS device arm64 VLCKit Mach-O" }
end

manifest = {
  "schema_version" => 1,
  "profile" => "musicfree-audio-ios",
  "build_status" => static_audit_ok ? "build-complete-static-audit-passed-runtime-gates-open" : "build-complete-static-audit-failed",
  "release_ready" => static_audit_ok && all_release_reports_passed,
  "build_command" => "env -u VLC_PATH MAKEFLAGS=-j2 ./compileAndBuildVLCKit.sh -f -r",
  "source" => {
    "vlckit_commit" => git_output(repo_root, "rev-parse", "HEAD"),
    "vlckit_base_commit" => source_lock.fetch("vlckit").fetch("base_commit"),
    "vlckit_worktree" => git_state(repo_root),
    "libvlc_base_commit" => source_lock.fetch("libvlc").fetch("base_commit"),
    "libvlc_patched_commit" => git_output(vlc_root, "rev-parse", "HEAD"),
    "libvlc_worktree" => git_state(vlc_root),
    "contrib_lock" => source_lock.fetch("contrib"),
    "sources_lock_sha256" => sha256_file(source_lock_path),
    "audio_profile_sha256" => sha256_file(File.join(repo_root, "Config", "audio-ios.env")),
    "module_policy_sha256" => sha256_file(File.join(repo_root, "Config", "module-policy.yml")),
    "required_capabilities_sha256" => sha256_file(File.join(repo_root, "Config", "required-capabilities.yml")),
    "build_script_sha256" => sha256_file(File.join(repo_root, "compileAndBuildVLCKit.sh"))
  },
  "toolchain" => {
    "xcodebuild_version" => normalize(required_command("/usr/bin/xcodebuild", "-version"), repo_root).strip,
    "iphoneos_sdk" => required_command("/usr/bin/xcrun", "--sdk", "iphoneos", "--show-sdk-version").strip,
    "iphonesimulator_sdk" => required_command("/usr/bin/xcrun", "--sdk", "iphonesimulator", "--show-sdk-version").strip,
    "clang_version" => normalize(required_command("/usr/bin/xcrun", "clang", "--version"), repo_root).strip,
    "deployment_target" => File.readlines(File.join(repo_root, "Config", "required-capabilities.yml"))
      .map { |line| line[/^deployment_target:\s*["']?([^"']+)["']?/, 1] }
      .compact
      .first,
    "configuration" => "Release"
  },
  "artifact" => {
    "xcframework" => relative(xcframework, repo_root),
    "xcframework_size_bytes" => directory_size(xcframework),
    "size_comparison" => size_comparison,
    "files" => tree_files,
    "available_libraries" => info.fetch("AvailableLibraries")
  },
  "release" => release_archives.empty? ? {} : {
    "archive" => relative(release_archives.last, repo_root),
    "archive_size_bytes" => File.size(release_archives.last),
    "archive_sha256" => sha256_file(release_archives.last),
    "swiftpm_checksum" => File.file?(File.join(release_root, "swiftpm-checksum.txt")) ? File.read(File.join(release_root, "swiftpm-checksum.txt")).strip : nil
  },
  "slices" => slice_metadata,
  "static_modules" => {
    "count_per_architecture" => modules_by_arch.transform_values(&:length),
    "common_count" => common_modules.length,
    "common_modules" => common_modules.sort,
    "forbidden_policy" => {
      "configured_forbidden_modules" => policy_forbidden,
      "configured_allowed_capabilities" => policy_allowed,
      "required_modules" => policy_required,
      "required_missing" => required_missing,
      "forbidden_matches" => forbidden_matches,
      "passed" => module_policy_ok && required_module_policy_ok
    }
  },
  "ffmpeg" => {
    "profile" => "disable-everything with audio decoder/parser/demuxer allowlist",
    "by_architecture" => ffmpeg_audit,
    "video_components_enabled" => video_components_enabled,
    "audio_profile_gate_passed" => ffmpeg_profile_ok
  },
  "linkage_audit" => {
    "framework_dependencies" => framework_dependencies,
    "video_or_rendering_system_frameworks_present" => forbidden_frameworks,
    "forbidden_framework_gate_passed" => framework_policy_ok,
    "forbidden_symbol_gate_passed" => symbol_policy_ok,
    "internal_video_symbol_gate_passed" => internal_video_symbol_policy_ok,
    "public_header_audit" => public_header_audit_result,
    "public_header_gate_passed" => public_header_policy_ok,
    "interpretation" => "VLCKit is a dynamic framework containing a statically linked libVLC archive. The iOS audio-only release gate rejects video/rendering system frameworks, exported FFmpeg/libVLC video symbols, and internal video-core or video-codec descriptor symbols. Container metadata strings are reported separately and are not sufficient evidence that video code is absent."
  },
  "validation" => {
    "xcframework_slice_layout" => slice_layout_ok ? "passed" : "failed",
    "dsym_uuid_match" => all_dsym_match ? "passed" : "failed",
    "static_module_forbidden_policy" => module_policy_ok ? "passed" : "failed",
    "static_module_required_policy" => required_module_policy_ok ? "passed" : "failed",
    "ffmpeg_video_decoder_profile" => ffmpeg_profile_ok ? "passed" : "failed",
    "ffmpeg_binary_symbol_audit" => symbol_policy_ok ? "passed" : "failed",
    "internal_video_symbol_audit" => internal_video_symbol_policy_ok ? "passed" : "failed",
    "system_framework_dependency_audit" => framework_policy_ok ? "passed" : "failed",
    "public_header_surface_audit" => public_header_policy_ok ? "passed" : "failed",
    "static_release_audit" => static_audit_ok ? "passed" : "failed",
  }.merge(validation_reports),
  "known_limitations" => [
    "The generated binary has not been validated against the eleven-format fixture matrix on a physical iPhone.",
    "The four protocol groups in the plan have not been exercised against controlled servers.",
    "The four protocol groups require controlled servers; unavailable rows remain blocked or not-run.",
    "A local SwiftPM consumer validates the artifact without changing MusicFree's production dependency; public URL/tag publication remains a separate release action.",
    "The final framework export surface has no audited video symbols and no VideoToolbox/OpenGLES/AVKit dependency, but the current statically linked libVLC core still contains internal video symbols; the internal-video gate therefore fails.",
    "LGPL distribution materials are generated, but legal review and the final App Store distribution decision remain open."
  ]
}

internal_video_symbol_report = {
  "schema_version" => 1,
  "profile" => "musicfree-audio-ios",
  "status" => internal_video_symbol_policy_ok ? "passed" : "failed",
  "criterion" => "No internal libVLC video-core or video-codec descriptor symbols in any XCFramework architecture",
  "slices" => slice_metadata.map do |slice|
    audit = slice.fetch("symbol_audit")
    {
      "library_identifier" => slice.fetch("library_identifier"),
      "architectures" => audit.fetch("nm_architectures"),
      "nm_succeeded" => audit.fetch("nm_succeeded"),
      "internal_video_symbol_audit_passed" => audit.fetch("internal_video_symbol_audit_passed"),
      "internal_video_symbols" => audit.fetch("internal_video_symbols"),
      "symbol_table_core_video_symbols" => audit.fetch("symbol_table_core_video_symbols"),
      "symbol_table_video_codec_descriptor_symbols" => audit.fetch("symbol_table_video_codec_descriptor_symbols")
    }
  end
}

inventory = {
  "schema_version" => 1,
  "profile" => "musicfree-audio-ios",
  "source" => {
    "vlckit_commit" => git_output(repo_root, "rev-parse", "HEAD"),
    "libvlc_patched_commit" => git_output(vlc_root, "rev-parse", "HEAD")
  },
  "architectures" => modules_by_arch.transform_values do |modules|
    modules.map do |name|
      { "entry" => "vlc_entry__#{name}", "name" => name, "category" => name.split("_", 2).first }
    end.sort_by { |module_entry| module_entry.fetch("name") }
  end,
  "common_modules" => common_modules.sort.map do |name|
    { "entry" => "vlc_entry__#{name}", "name" => name, "category" => name.split("_", 2).first }
  end,
  "policy" => {
    "required_modules" => policy_required,
    "required_missing" => required_missing,
    "forbidden_modules" => policy_forbidden,
    "forbidden_matches" => forbidden_matches,
    "passed" => module_policy_ok && required_module_policy_ok
  }
}

FileUtils.mkdir_p(release_root)
File.write(File.join(release_root, "build-manifest.json"), JSON.pretty_generate(manifest) + "\n")
File.write(File.join(release_root, "module-inventory.json"), JSON.pretty_generate(inventory) + "\n")
File.write(File.join(release_root, "internal-video-symbol-audit.json"), JSON.pretty_generate(internal_video_symbol_report) + "\n")
puts "wrote #{File.join(release_root, 'build-manifest.json')}"
puts "wrote #{File.join(release_root, 'module-inventory.json')}"
puts "wrote #{File.join(release_root, 'internal-video-symbol-audit.json')}"
RUBY
