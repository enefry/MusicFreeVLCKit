# MusicFree VLCKit 上游升级与主线合并指南

状态：维护指南

最后核对日期：2026-08-14

适用对象：后续负责把 MusicFree 音频裁剪版 VLCKit 合并到新版 VLCKit/libVLC 主线的 agent 或维护者。

## 1. 目标

本指南用于完成一次可回滚、可复现、可审计的双层升级：

1. 将外层 VLCKit 前移到经过选择的 VideoLAN VLCKit tag/commit。
2. 将内层 libVLC 前移到与该 VLCKit 版本兼容的 commit。
3. 在新主线上重新表达 MusicFree 音频裁剪意图，而不是机械保留旧代码。
4. 重新生成可携带的 libVLC 补丁、锁文件、XCFramework 和发布证据。

“编译成功”不是升级完成。只有源码、补丁重放、静态审计、SwiftPM、真机矩阵、零联网证据、复现性和 LGPL 材料都达到发布门槛，才可以把新版本标记为 release ready。

## 2. 当前基线快照

以下值是 2026-08-14 的已知基线。开始升级时先从仓库重新读取，不要只复制本文数值。

| 层级 | 当前值 | 便携真源 |
| --- | --- | --- |
| MusicFree VLCKit 分支 | <code>musicfree/audio-ios-r5</code> | 外层 Git 当前分支 |
| r5 音频裁剪实现 | <code>ccc4c87d01a11e0856690163560396c1269aa50c</code> | 外层 Git 历史 |
| 发布自动化与原指南基线 | <code>88d045963bbb2dc31af99d37f42a8fd25dbda5e6</code> | 外层 Git 历史；本指南修订前的已知维护 commit |
| 当前已知良好外层 HEAD | <code>8decf514278382c314df3e292adaf0ac1a9465d4</code> | 2026-08-14 的 <code>musicfree/audio-ios-r5</code> 与 <code>origin/musicfree/audio-ios-r5</code>；包含后续 workflow 和 VLC host tools 修订 |
| VLCKit 上游基线 | <code>e3774eb25c62c902e9066ba267e6416d82e83382</code>，tag <code>4.0.0-a23</code> | <code>Config/sources.lock.json</code> |
| libVLC 上游基线 | <code>2cd8705589d3b125f236d1af695c3961fdcf6ca4</code> | <code>Config/sources.lock.json</code> 与 <code>TESTEDHASH</code> |
| libVLC 补丁 | 28 个，<code>0001</code> 到 <code>0028</code> | <code>libvlc/patches/*.patch</code> |
| MusicFree libVLC 补丁 | <code>0028-libvlc-add-MusicFree-audio-only-build-profile.patch</code> | 外层 Git 跟踪文件 |
| 补丁后 libVLC tree | <code>34c486a4b371e57b4d37bff288222c26fb86d8a0</code> | lock 文件与 <code>PATCHEDTREE</code> |
| 本机辅助 libVLC 分支 | <code>musicfree/audio-ios-r5-libvlc</code>，HEAD <code>3c7cef710cd6ab05bbbece946f5d84f170082d2c</code> | 仅本机辅助，不是发布真源 |
| r5 SwiftPM ZIP | 43,627,677 bytes | 本地构建目录，未进 Git |
| r5 checksum | <code>873b6c4a9840565cad530ea7278b70fb3748b2136fa647abb52666ce418f6565</code> | r5 release 证据 |

当前 r5 仍是工程候选，不是发布基线。它的内部视频符号审计、真实格式/协议矩阵、零联网证据、真机播放、第二次干净构建和 LGPL 发布材料仍有开放项。升级不能继承这些未完成项，也不能把 r5 的历史通过结果直接复制给新产物。

当前已提交的 <code>Package.swift</code> 仍是上游通用 manifest，声明 macOS、tvOS、watchOS 和 visionOS，并指向 VideoLAN 通用 ZIP；MusicFree r5 XCFramework 实际只有 iOS Device/Simulator slice。首次 MusicFree pre-release 前必须先校正平台声明，最终 URL/checksum 再由 tag 发布流程写入。该偏差是开放门禁，不因 manifest 可以解析而自动通过。

## 3. 真源与边界

后续 agent 必须先理解三个不同层次：

1. 外层 <code>MusicFreeVLCKit</code> Git 历史记录 VLCKit wrapper、Xcode 工程、构建配置、审计脚本和可携带的 libVLC 补丁。
2. <code>libvlc/vlc</code> 被外层 <code>.gitignore</code> 忽略。其本地分支只用于开发、解决冲突和生成补丁，不能作为其他机器可取得的唯一来源。
3. <code>build-audio-ios-*</code> 是本地产物目录，不进入源码提交。发布时应作为不可变 release asset 保存。

因此，升级后的 libVLC 修改只有在以下三项同时更新时才算进入可携带记录：

- <code>libvlc/patches/*.patch</code>
- <code>Config/sources.lock.json</code>
- <code>compileAndBuildVLCKit.sh</code> 中的 libVLC 基线和补丁后 tree 校验

## 4. 不可破坏的产品能力

上游实现可以变化，但以下能力边界不能在冲突解决时静默改变：

- 只保留音频播放、音频解析、内嵌元数据/封面、速率、EQ 和 iOS 音频输出所需能力。
- 保留 MP3、AAC/HE-AAC、ALAC、FLAC、Opus、Vorbis、WAV/PCM、AIFF、APE、WavPack、Musepack。
- 网络只允许显式授权的 HTTP/HTTPS、SMB2/3、FTP/FTPS/FTPES、NFS 单文件直链。
- 不保留视频输出/滤镜/解码、字幕、发现、目录浏览、HLS/DASH、RTSP/RTP/UDP、SRT/RIST、SFTP、投屏、sout、编码和 mux。
- 本地扫描、probe、metadata、artwork、队列恢复和启动流程没有网络 grant，且必须有零联网证据。
- 不向业务层暴露任意 VLC option 字符串、任意 Header 或持久化凭据。
- 最终产物必须保持模块名 <code>VLCKit</code> 和 MusicFree 现有 import 边界。

如果新版主线让某项旧裁剪失去必要性，应删除旧兼容代码；如果新版主线引入新依赖，应先证明它是保留能力的硬依赖，再更新 allowlist。不能为了快速合并把完整视频栈或完整协议栈放回去。

## 5. 总体升级顺序

一次升级按以下顺序推进：

~~~text
选择兼容的 VLCKit/libVLC 目标
  -> 保存旧基线和当前验证结果
  -> 在临时 worktree 合并 VLCKit 主线
  -> 在新 libVLC 基线上重放 VLCKit 上游补丁
  -> 语义化迁移 MusicFree 音频补丁
  -> 重新生成补丁、patch_count 和 patched_tree
  -> 更新配置、模块策略、contrib 锁和 wrapper API
  -> 提交干净源码
  -> 从空缓存完整构建两次
  -> 重跑全部静态、SwiftPM、真机、协议、零联网和合规门禁
  -> 生成 tag 专属 Package.swift，发布并回读校验不可变预发布资产
  -> 形成升级记录并进入 Review
~~~

VLCKit 与 libVLC 是耦合升级。默认先选择 VLCKit 目标，再采用该版本明确绑定的 libVLC 基线和补丁栈。只有存在已确认的安全/兼容原因时，才独立把 libVLC 提前到更晚 commit，并在升级记录中说明理由。

### 5.1 命令执行契约

第 6 到第 12 节的命令按一个连续 Bash session 编写，后续代码块会使用前面定义的变量。开始前进入外层仓库并启用 fail-fast 和空 glob 保护：

~~~bash
cd /path/to/MusicFreeVLCKit
exec /bin/bash
set -euo pipefail
shopt -s nullglob
~~~

每个阶段失败后立即停止，不得继续打包或清理。解决 <code>cherry-pick</code>/<code>am</code> 冲突后，先确认 sequencer 已完成、源码状态符合预期，再进入下一阶段。若另开 shell，必须重新定义并核对所有路径、commit 和数组变量。

所有 <code>REPLACE_WITH_*</code> 都是本轮必须从实时候选、命令输出或维护者审批取得的输入，不是可猜测的示例默认值。相关命令必须在占位符未替换、URL/commit/patch identity 不匹配或审批引用为空时以非零状态停止，并把输入来源写入升级记录。目标版本、发布权限、设备、协议服务或法律批准无法取得时，正确结果是 <code>blocked</code>，不是由 agent 自行补值。

## 6. 阶段 A：预检和目标选择

### 6.1 保持已知良好分支不动

不要在 <code>musicfree/audio-ios-r5</code> 或用户正在使用的工作树上直接 merge/rebase。不要运行 <code>git reset --hard</code>。所有升级工作使用唯一命名的分支和临时 worktree。

在 <code>MusicFreeVLCKit</code> 根目录执行，并先记录当前状态：

~~~bash
vlckit_repo=$(git rev-parse --show-toplevel)
baseline_branch=musicfree/audio-ios-r5
baseline_outer_commit=$(git -C "$vlckit_repo" \
  rev-parse "$baseline_branch^{commit}")
git -C "$vlckit_repo" cat-file -e \
  "$baseline_outer_commit^{commit}"
upgrade_id=REPLACE_WITH_DATE_AND_TARGET
test -n "$upgrade_id"
test "$upgrade_id" != "REPLACE_WITH_DATE_AND_TARGET"

git -C "$vlckit_repo" status --short --branch
printf "baseline_outer_commit=%s\n" "$baseline_outer_commit"
jq . "$vlckit_repo/Config/sources.lock.json"

if git -C "$vlckit_repo/libvlc/vlc" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$vlckit_repo/libvlc/vlc" status --short --branch
  git -C "$vlckit_repo/libvlc/vlc" rev-parse HEAD
  git -C "$vlckit_repo/libvlc/vlc" rev-parse "HEAD^{tree}"
else
  printf "%s\n" "local libVLC checkout: absent"
fi
~~~

若任一源码工作树有未解释的修改，先停止并确认归属。忽略目录中的旧构建产物不等于源码 dirty，但也不能作为新升级的缓存或验证证据。

### 6.2 获取主线但不改工作树

不要假设现有 clone 是 shallow 或完整仓库。2026-08-14 当前两个本地仓库的 <code>--is-shallow-repository</code> 都是 false，但新机器、CI clone 或后续清理后的状态可能不同。fetch 后必须用 <code>git cat-file</code> 和 <code>git merge-base</code> 确认目标对象及所需祖先历史存在；看得到一个远端 ref 不代表历史完整。

~~~bash
git -C "$vlckit_repo" rev-parse --is-shallow-repository
upstream_vlckit_url=$(git -C "$vlckit_repo" \
  remote get-url videolan)
printf "videolan_remote=%s\n" "$upstream_vlckit_url"
reviewed_videolan_url=REPLACE_WITH_REVIEWED_OFFICIAL_URL
test -n "$reviewed_videolan_url"
test "$reviewed_videolan_url" != \
  "REPLACE_WITH_REVIEWED_OFFICIAL_URL"
test "$upstream_vlckit_url" = "$reviewed_videolan_url"

target_vlckit_ref=REPLACE_WITH_REVIEWED_TAG_OR_BRANCH
test -n "$target_vlckit_ref"
test "$target_vlckit_ref" != \
  "REPLACE_WITH_REVIEWED_TAG_OR_BRANCH"
git -C "$vlckit_repo" fetch videolan "$target_vlckit_ref"
target_vlckit_commit=$(git -C "$vlckit_repo" \
  rev-parse "FETCH_HEAD^{commit}")
git -C "$vlckit_repo" cat-file -e "$target_vlckit_commit^{commit}"
old_vlckit_base=$(jq -r .vlckit.base_commit \
  "$vlckit_repo/Config/sources.lock.json")
git -C "$vlckit_repo" merge-base --is-ancestor \
  "$old_vlckit_base" "$target_vlckit_commit"
~~~

若 <code>videolan</code> remote 不存在，先从 VideoLAN 官方来源核对 URL，再显式添加并记录；不能把 fork 的同名 remote 当官方主线。如果 ancestry 因 shallow history 不可用，先用明确 remote/ref 扩展历史，例如 <code>git fetch --deepen=500 videolan "$target_vlckit_ref"</code>，然后重新计算 peeled commit 并重跑 <code>--is-ancestor</code>；只有 <code>--is-shallow-repository</code> 为 true 且确实需要完整历史时才对同一 remote/ref 使用 <code>--unshallow</code>。若 old base 不是 target commit 的祖先，停止并调查分支改写或目标选择，不能只因二者有共同祖先就继续。不要用“最新 master”作为未记录的浮动输入，最终必须保存完整 40 位 commit。

### 6.3 目标选择检查

选定 VLCKit commit 后先只读检查：

- release notes、最低 Xcode/SDK/deployment target 和 Apple 平台支持变化。
- 上游 <code>compileAndBuildVLCKit.sh</code> 或替代脚本绑定的 libVLC commit。
- 上游 <code>libvlc/patches</code> 新增、删除、已 upstream 的补丁。
- VLCKit 公开头文件、播放器生命周期、静态链接和 SwiftPM 布局变化。
- libVLC modules/contrib 构建系统是否从 Automake 迁移或拆分。
- FFmpeg、TagLib、SMB2、NFS、TLS 等版本与许可证变化。
- 是否包含与音频、网络、安全、崩溃或 Apple toolchain 相关的修复。

先把目标对写入升级记录草稿：

~~~text
old VLCKit base:
new VLCKit base:
old libVLC base:
new libVLC base:
target tag/ref:
selection reason:
known upstream breaking changes:
~~~

## 7. 阶段 B：合并 VLCKit 主线

### 7.1 创建两个 VLCKit worktree

一个 worktree 保持纯上游目标，用来读取上游补丁栈；另一个 worktree 承载 MusicFree 集成。

~~~bash
target_vlckit_approval=REPLACE_WITH_TARGET_VLCKIT_REVIEW_REFERENCE
test -n "$target_vlckit_approval"
test "$target_vlckit_approval" != \
  "REPLACE_WITH_TARGET_VLCKIT_REVIEW_REFERENCE"
upgrade_root=$(mktemp -d /private/tmp/musicfree-vlckit-upgrade.XXXXXX)
upstream_vlckit_worktree="$upgrade_root/VLCKit-upstream"
vlckit_worktree="$upgrade_root/VLCKit-integration"

git -C "$vlckit_repo" worktree add --detach \
  "$upstream_vlckit_worktree" "$target_vlckit_commit"

git -C "$vlckit_repo" worktree add -b "upgrade/$upgrade_id" \
  "$vlckit_worktree" "$target_vlckit_commit"
~~~

纯上游 worktree 不做修改。集成 worktree 最终形成可 Review 分支。

### 7.2 重放 MusicFree 外层提交

先列出旧基线之后的全部 MusicFree 提交，确认范围后再 cherry-pick：

~~~bash
old_vlckit_base=$(jq -r .vlckit.base_commit \
  "$vlckit_repo/Config/sources.lock.json")

git -C "$vlckit_repo" merge-base --is-ancestor \
  "$old_vlckit_base" "$baseline_outer_commit"

merge_commits=$(git -C "$vlckit_repo" rev-list --merges \
  "$old_vlckit_base..$baseline_outer_commit")
test -z "$merge_commits"

git -C "$vlckit_repo" log --reverse --oneline \
  "$old_vlckit_base..$baseline_outer_commit"

custom_commits=()
while IFS= read -r commit; do
  custom_commits+=("$commit")
done < <(git -C "$vlckit_repo" rev-list --reverse \
  "$old_vlckit_base..$baseline_outer_commit")
test "${#custom_commits[@]}" -gt 0

for commit in "${custom_commits[@]}"; do
  git -C "$vlckit_repo" show --stat --oneline "$commit"
done

reviewed_custom_commits=(
  REPLACE_WITH_REVIEWED_40_CHARACTER_COMMIT_LIST
)
custom_commit_scope_approval=REPLACE_WITH_COMMIT_SCOPE_REVIEW_REFERENCE
test "${reviewed_custom_commits[*]}" = "${custom_commits[*]}"
test -n "$custom_commit_scope_approval"
test "$custom_commit_scope_approval" != \
  "REPLACE_WITH_COMMIT_SCOPE_REVIEW_REFERENCE"
git -C "$vlckit_worktree" cherry-pick -x \
  "${reviewed_custom_commits[@]}"
~~~

当前已知范围至少包含 <code>ccc4c87d</code> 的音频裁剪实现、<code>88d04596</code>/<code>102d9f53</code> 的发布自动化与升级流程，以及 <code>8decf514</code> 的 VLC host tools 修订；本指南后续提交还会继续增加数量。始终以命令实时列出的完整范围为准，不得写死 commit 数量。若范围包含 merge commit 或意外上游提交，停止并显式整理 MusicFree commit 清单，不要给 <code>cherry-pick</code> 猜测 mainline。

### 7.3 外层冲突处理原则

| 冲突区域 | 处理方式 |
| --- | --- |
| <code>compileAndBuildVLCKit.sh</code> | 先保留新版上游平台/toolchain 流程，再迁移音频 profile、独立 build root、clean worktree 和 tree hash 校验 |
| <code>VLCKit.xcodeproj/project.pbxproj</code> | 以上游工程为底，按新 target/source/framework 关系重新裁剪；禁止整文件选择旧版 |
| Public/Internal Headers | 保留上游 API rename、nullability 和生命周期修复，再移除新版本中的视频/发现/字幕公开面 |
| Objective-C Sources | 在新版所有权和调用链上重做音频边界；不要复活上游已删除类 |
| <code>Resources/module.modulemap</code> | 先采用上游模块布局，再限制公开 headers |
| <code>libvlc/patches</code> | 纯上游 worktree 中的补丁是新版上游起点；旧 MusicFree 补丁稍后单独 rebase |
| <code>Package.swift</code>/<code>Packaging</code>/<code>.github</code> | 保留新版 Swift tools/product/target 结构变化，但按音频产物真实 slice 重审平台声明；MusicFree 的 tag、checksum、合规资产发布流程不能被上游通用发布脚本静默覆盖 |
| <code>Config</code>/<code>Scripts</code>/<code>Tests</code> | 保留审计意图，但更新字段、模块名、toolchain 和产物布局 |

解决冲突时逐文件 <code>git add</code> 后执行 <code>git cherry-pick --continue</code>。禁止对上述核心文件批量使用 <code>--ours</code> 或 <code>--theirs</code>。

## 8. 阶段 C：在新版 libVLC 上迁移补丁

### 8.1 确认新版 libVLC 基线

从纯上游 VLCKit worktree 的构建脚本和源码锁中确定绑定 commit：

~~~bash
rg -n "TESTEDHASH|libvlc.*commit|git checkout" \
  "$upstream_vlckit_worktree/compileAndBuildVLCKit.sh" \
  "$upstream_vlckit_worktree/Config" 2>/dev/null

new_vlc_base=REPLACE_WITH_VALUE_FOUND_ABOVE
test -n "$new_vlc_base"
test "$(printf "%s" "$new_vlc_base" | wc -c | tr -d " ")" -eq 40
source_pair_approval=REPLACE_WITH_SOURCE_PAIR_REVIEW_REFERENCE
test -n "$source_pair_approval"
test "$source_pair_approval" != \
  "REPLACE_WITH_SOURCE_PAIR_REVIEW_REFERENCE"
~~~

将确认后的完整 40 位值保存为 <code>new_vlc_base</code>。如果新版上游改变了绑定方式，按新版事实更新本指南涉及的脚本，不要继续维护已经失效的 <code>TESTEDHASH</code> 模式。

### 8.2 创建新版 libVLC worktree

本机已有 <code>libvlc/vlc</code> 时可复用其 object database，但不能在旧分支上直接改。若目录不存在，使用 lock 中的 URL 创建本地辅助 clone：

~~~bash
vlc_repo="$vlckit_repo/libvlc/vlc"
vlc_url=$(jq -r .libvlc.repository \
  "$vlckit_repo/Config/sources.lock.json")

if ! git -C "$vlc_repo" rev-parse --git-dir >/dev/null 2>&1; then
  mkdir -p "$vlckit_repo/libvlc"
  git clone --filter=blob:none "$vlc_url" "$vlc_repo"
fi

actual_vlc_url=$(git -C "$vlc_repo" remote get-url origin)
printf "locked_vlc_url=%s\nactual_vlc_url=%s\n" \
  "$vlc_url" "$actual_vlc_url"
reviewed_vlc_origin_url=REPLACE_WITH_REVIEWED_LIBVLC_ORIGIN_URL
test -n "$reviewed_vlc_origin_url"
test "$reviewed_vlc_origin_url" != \
  "REPLACE_WITH_REVIEWED_LIBVLC_ORIGIN_URL"
test "$actual_vlc_url" = "$reviewed_vlc_origin_url"

new_vlc_ref=REPLACE_WITH_REVIEWED_TAG_OR_BRANCH
test -n "$new_vlc_ref"
test "$new_vlc_ref" != "REPLACE_WITH_REVIEWED_TAG_OR_BRANCH"

git -C "$vlc_repo" rev-parse --is-shallow-repository
git -C "$vlc_repo" fetch origin "$new_vlc_ref"
fetched_vlc_commit=$(git -C "$vlc_repo" \
  rev-parse "FETCH_HEAD^{commit}")
git -C "$vlc_repo" cat-file -e "$new_vlc_base^{commit}"
git -C "$vlc_repo" merge-base --is-ancestor \
  "$new_vlc_base" "$fetched_vlc_commit"

vlc_worktree="$vlckit_worktree/libvlc/vlc"
git -C "$vlc_repo" worktree add \
  -b "musicfree/upgrade-$upgrade_id-libvlc" \
  "$vlc_worktree" "$new_vlc_base"
~~~

<code>new_vlc_base</code> 必须直接来自第 8.1 节确认的上游绑定值，不能另行手填一个“接近”的 commit。若 repository URL 合法但字符串形式与 lock 不同，例如 SSH/HTTPS 或尾部 <code>.git</code> 差异，先人工确认同一仓库，再记录实际 remote；不要跳过来源检查。若 shallow history 使 ancestry 不可用，对明确 ref 执行 <code>git fetch --deepen=500 origin "$new_vlc_ref"</code> 后重新计算 <code>fetched_vlc_commit</code> 和断言。该目录仍保持外层 ignored。

### 8.3 先重放新版 VLCKit 自带补丁

第 8.3 到第 10 节的命令以“新版 VLCKit 仍使用有序 mail patch 目录”为前提。先在纯上游 worktree 和新版构建脚本中确认该前提；只使用纯上游 VLCKit worktree 中的补丁。目录可以合法地包含 0 个上游补丁，此时边界就是 <code>new_vlc_base</code>；非空时把完整序列一次交给 <code>git am</code>，这样解决冲突后 <code>git am --continue</code> 会继续剩余补丁：

~~~bash
upstream_patch_dir="$upstream_vlckit_worktree/libvlc/patches"
upstream_patch_driver="$upstream_vlckit_worktree/compileAndBuildVLCKit.sh"
test -d "$upstream_patch_dir"
test -f "$upstream_patch_driver"

# This guide supports only the reviewed ordered mail-patch mechanism.
rg -q 'libvlc/patches/.*\.patch|libvlc/patches/\*\.patch' \
  "$upstream_patch_driver"
rg -q 'git[[:space:]]+am([[:space:]]|$)' \
  "$upstream_patch_driver"
upstream_patch_driver_sha256=$(shasum -a 256 \
  "$upstream_patch_driver" | awk '{print $1}')
reviewed_patch_driver_sha256=REPLACE_WITH_REVIEWED_PATCH_DRIVER_SHA256
patch_mechanism_approval=REPLACE_WITH_PATCH_MECHANISM_REVIEW_REFERENCE
test -n "$reviewed_patch_driver_sha256"
test "$reviewed_patch_driver_sha256" != \
  "REPLACE_WITH_REVIEWED_PATCH_DRIVER_SHA256"
test "$reviewed_patch_driver_sha256" = \
  "$upstream_patch_driver_sha256"
test -n "$patch_mechanism_approval"
test "$patch_mechanism_approval" != \
  "REPLACE_WITH_PATCH_MECHANISM_REVIEW_REFERENCE"

upstream_patches=("$upstream_patch_dir"/*.patch)
for patch in "${upstream_patches[@]}"; do
  relative_patch=${patch#"$upstream_vlckit_worktree/"}
  git -C "$upstream_vlckit_worktree" ls-files --error-unmatch \
    "$relative_patch" >/dev/null
done
if test "${#upstream_patches[@]}" -gt 0; then
  git -C "$vlc_worktree" am -3 "${upstream_patches[@]}"
fi
~~~

如果上游改用 submodule commit、生成脚本或其他补丁机制，立即把本轮状态标记为 <code>blocked</code>、原因为 <code>patch-mechanism-migration-required</code>，并停止执行第 8.3 到第 10 节。先用单独、可 Review 的提交改造以下契约，再从第 8 节重新开始：构建脚本如何得到“上游修补后 tree”、MusicFree 自定义改动如何携带、lock 如何记录 mechanism/count/tree、clean replay 如何重建同一 tree、metadata/SBOM 如何列出修改源码。新机制必须提供与当前 <code>base + ordered patches -&gt; patched_tree</code> 等价的机器断言；不能只删掉非空数组或 <code>patch_count</code> 检查后继续。

全部上游补丁完成后保存边界 commit：

~~~bash
upstream_patched_commit=$(git -C "$vlc_worktree" rev-parse HEAD)
~~~

### 8.4 再迁移 MusicFree 补丁

当前 MusicFree 补丁是：

~~~text
libvlc/patches/0028-libvlc-add-MusicFree-audio-only-build-profile.patch
~~~

先把旧分支中所有名称含 <code>MusicFree</code> 的补丁固化为清单，确认数量和顺序后一次性交给 <code>git am</code>：

~~~bash
musicfree_patches=(
  "$vlckit_repo"/libvlc/patches/*MusicFree*.patch
)
test "${#musicfree_patches[@]}" -gt 0
printf "%s\n" "${musicfree_patches[@]}"

actual_musicfree_patch_identities=()
for patch in "${musicfree_patches[@]}"; do
  patch_sha256=$(shasum -a 256 "$patch" | awk '{print $1}')
  actual_musicfree_patch_identities+=(
    "$(basename "$patch"):$patch_sha256"
  )
done
reviewed_musicfree_patch_identities=(
  REPLACE_WITH_REVIEWED_BASENAME_AND_SHA256_LIST
)
musicfree_patch_scope_approval=REPLACE_WITH_PATCH_SCOPE_REVIEW_REFERENCE
test "${reviewed_musicfree_patch_identities[*]}" = \
  "${actual_musicfree_patch_identities[*]}"
test -n "$musicfree_patch_scope_approval"
test "$musicfree_patch_scope_approval" != \
  "REPLACE_WITH_PATCH_SCOPE_REVIEW_REFERENCE"
git -C "$vlc_worktree" am -3 "${musicfree_patches[@]}"
~~~

出现冲突时：

~~~bash
git -C "$vlc_worktree" status
git -C "$vlc_worktree" am --show-current-patch=diff
~~~

按新版源码语义修改，逐项暂存后执行 <code>git am --continue</code>。只有决定丢弃整个临时迁移时才 <code>git am --abort</code>。

### 8.5 libVLC 冲突分类

| 分类 | 当前主要文件 | 升级判断 |
| --- | --- | --- |
| profile 开关/Apple 构建 | <code>configure.ac</code>、<code>extras/package/apple/build.sh</code> | 若上游构建系统变化，把条件迁到新 owner；不要保留失效的 Automake hook |
| contrib 最小化 | FFmpeg/TagLib/EBML/utfcpp rules | 重新确认版本、依赖、checksum 和 license；已被上游满足的 hunk 直接删除 |
| FFmpeg 音频 allowlist | <code>contrib/src/ffmpeg</code> | 从新版实际 configure 选项重建；不允许视频 decoder/filter/network 回流 |
| libVLC API 面 | <code>lib/Makefile.am</code>、media/player/parser/picture | 保持音频播放所需 API；按新版生命周期修复调整，不恢复 discoverer/video API |
| core 视频依赖移除 | <code>src/Makefile.am</code>、<code>musicfree_audio_compat.c</code> | 优先减少兼容 stub；上游解耦后删除对应 stub，不为通过链接保留无用视频路径 |
| access/demux/codec | <code>modules/access</code>、<code>modules/demux</code>、<code>modules/codec</code> | 容器共享代码按真实音频 fixture 决定；不能仅凭函数名删除 |
| fourcc/track 描述 | media track、fourcc、es_format | 保留音频 codec 映射；视频描述符残留仍需内部符号审计 |

旧补丁某段已经进入上游时，正确处理是删除该段并记录“upstreamed”，不是强行制造相同 diff。文件被上游删除或重命名时，应在新 owner 重做能力边界，不得复活旧文件。

## 9. 阶段 D：重新生成可携带补丁和锁

### 9.1 整理 MusicFree commit

在 libVLC upgrade 分支上保持“上游 VLCKit 补丁”和“MusicFree 音频裁剪”边界清晰。MusicFree 改动优先整理成一个可解释 commit；确有独立语义时可拆成多个连续 commit。

可用 <code>git range-diff</code> 对比旧、新 MusicFree 变更，确认没有静默丢失能力或带回视频代码。

### 9.2 替换外层 MusicFree 补丁

先在集成 worktree 中固化并审核全部旧 MusicFree 补丁，然后一次性 <code>git rm</code>。MusicFree 自定义 commit 的 Subject 必须包含 <code>MusicFree</code>，使生成文件可被稳定识别。不要删除纯上游补丁。

新版上游补丁数量决定 MusicFree 补丁起始编号：

~~~bash
old_musicfree_patches=(
  "$vlckit_worktree"/libvlc/patches/*MusicFree*.patch
)
test "${#old_musicfree_patches[@]}" -gt 0
printf "%s\n" "${old_musicfree_patches[@]}"

integration_old_patch_identities=()
for patch in "${old_musicfree_patches[@]}"; do
  patch_sha256=$(shasum -a 256 "$patch" | awk '{print $1}')
  integration_old_patch_identities+=(
    "$(basename "$patch"):$patch_sha256"
  )
done
test "${integration_old_patch_identities[*]}" = \
  "${reviewed_musicfree_patch_identities[*]}"
git -C "$vlckit_worktree" rm -- \
  "${old_musicfree_patches[@]}"

upstream_patch_count="${#upstream_patches[@]}"
if test "$upstream_patch_count" -gt 0; then
  last_upstream_patch=$(printf "%s\n" \
    "${upstream_patches[@]}" | tail -n 1)
  last_upstream_number=$(basename "$last_upstream_patch" \
    | cut -d- -f1 | sed "s/^0*//")
  test -n "$last_upstream_number"
  next_patch_number=$((last_upstream_number + 1))
else
  next_patch_number=1
fi

expected_musicfree_patch_count=$(git -C "$vlc_worktree" \
  rev-list --count "$upstream_patched_commit..HEAD")
test "$expected_musicfree_patch_count" -gt 0
git -C "$vlc_worktree" format-patch \
  "$upstream_patched_commit..HEAD" \
  --start-number "$next_patch_number" \
  --numbered \
  --output-directory "$vlckit_worktree/libvlc/patches"

generated_musicfree_patches=(
  "$vlckit_worktree"/libvlc/patches/*MusicFree*.patch
)
test "${#generated_musicfree_patches[@]}" \
  -eq "$expected_musicfree_patch_count"

all_patches=(
  "$vlckit_worktree"/libvlc/patches/*.patch
)
test "${#all_patches[@]}" \
  -eq "$((upstream_patch_count + expected_musicfree_patch_count))"

expected_number=1
for patch in "${all_patches[@]}"; do
  actual_prefix=$(basename "$patch" | cut -d- -f1)
  expected_prefix=$(printf "%04d" "$expected_number")
  test "$actual_prefix" = "$expected_prefix"
  expected_number=$((expected_number + 1))
done
~~~

检查生成结果只包含预期 MusicFree commit，编号连续，Subject 可读，且补丁能从 <code>new_vlc_base</code> 重放。

### 9.3 建立旧补丁迁移映射

每个旧 MusicFree patch 必须在 <code>Documentation/upgrades/&lt;upgrade_id&gt;.patch-map.json</code> 中恰好出现一次，不能只在自由文本里写“已处理”。使用固定 schema：

~~~json
{
  "schema_version": 1,
  "old_libvlc_base": "40-character commit",
  "new_libvlc_base": "40-character commit",
  "entries": [
    {
      "old_patch": "0028-example-MusicFree.patch",
      "old_sha256": "64-character sha256",
      "disposition": "rebased",
      "replacements": ["0031-example-MusicFree.patch"],
      "upstream_commits": [],
      "rationale": "How the old intent is represented on the new tree",
      "approval": "REPLACE_WITH_REVIEW_REFERENCE"
    }
  ]
}
~~~

<code>disposition</code> 只能是 <code>rebased</code>、<code>split</code>、<code>upstreamed</code> 或 <code>dropped</code>。<code>split</code> 必须同时列 replacement 和 upstream commit；<code>upstreamed</code> 必须列进入新 base 的 commit；<code>dropped</code> 必须有范围变更批准。用结构化编辑器完成映射后执行：

~~~bash
patch_map="$vlckit_worktree/Documentation/upgrades/$upgrade_id.patch-map.json"
test -f "$patch_map"
old_vlc_base=$(jq -r .libvlc.base_commit \
  "$vlckit_repo/Config/sources.lock.json")
jq -e \
  --arg old "$old_vlc_base" \
  --arg new "$new_vlc_base" \
  '.schema_version == 1 and
   .old_libvlc_base == $old and
   .new_libvlc_base == $new and
   (.entries | type == "array")' \
  "$patch_map" >/dev/null
test "$(jq '.entries | length' "$patch_map")" \
  -eq "${#reviewed_musicfree_patch_identities[@]}"

for identity in "${reviewed_musicfree_patch_identities[@]}"; do
  old_patch_name=${identity%%:*}
  old_patch_sha256=${identity#*:}
  test "$(jq --arg name "$old_patch_name" \
    '[.entries[] | select(.old_patch == $name)] | length' \
    "$patch_map")" -eq 1
  jq -e \
    --arg name "$old_patch_name" \
    --arg sha "$old_patch_sha256" \
    '.entries[] | select(.old_patch == $name) |
     .old_sha256 == $sha and
     (.rationale | type == "string" and length > 0) and
     (.approval | type == "string" and length > 0) and
     .approval != "REPLACE_WITH_REVIEW_REFERENCE" and
     (.disposition == "rebased" or
      .disposition == "split" or
      .disposition == "upstreamed" or
      .disposition == "dropped") and
     (if .disposition == "rebased" then
        (.replacements | length > 0) and
        (.upstream_commits | length == 0)
      elif .disposition == "split" then
        (.replacements | length > 0) and
        (.upstream_commits | length > 0)
      elif .disposition == "upstreamed" then
        (.replacements | length == 0) and
        (.upstream_commits | length > 0)
      else
        (.replacements | length == 0) and
        (.upstream_commits | length == 0)
      end)' "$patch_map" >/dev/null
done

map_replacements=()
while IFS= read -r replacement; do
  map_replacements+=("$replacement")
done < <(jq -r '.entries[].replacements[]?' "$patch_map")

# The replacement multiset must equal the generated MusicFree patch set.
# This rejects duplicates, paths, and references to an upstream patch.
test "${#map_replacements[@]}" \
  -eq "${#generated_musicfree_patches[@]}"
for replacement in "${map_replacements[@]}"; do
  test -n "$replacement"
  test "$replacement" = "$(basename "$replacement")"
  replacement_matches=0
  for generated_patch in "${generated_musicfree_patches[@]}"; do
    if test "$replacement" = "$(basename "$generated_patch")"; then
      replacement_matches=$((replacement_matches + 1))
    fi
  done
  test "$replacement_matches" -eq 1
  test "$(jq --arg name "$replacement" \
    '[.entries[].replacements[]? | select(. == $name)] | length' \
    "$patch_map")" -eq 1
done

for generated_patch in "${generated_musicfree_patches[@]}"; do
  generated_name=$(basename "$generated_patch")
  test "$(jq --arg name "$generated_name" \
    '[.entries[].replacements[]? | select(. == $name)] | length' \
    "$patch_map")" -eq 1
done

while IFS= read -r upstream_commit; do
  git -C "$vlc_repo" cat-file -e "$upstream_commit^{commit}"
  git -C "$vlc_repo" merge-base --is-ancestor \
    "$upstream_commit" "$new_vlc_base"
done < <(jq -r '.entries[].upstream_commits[]?' "$patch_map")

patch_map_sha256=$(shasum -a 256 "$patch_map" | awk '{print $1}')
printf "patch_map_sha256=%s\n" "$patch_map_sha256"
~~~

映射证明“每个旧 patch 去了哪里”；第 10 节 tree 重放和第 13 节能力门禁再证明最终语义与产物。二者缺一不可。

### 9.4 更新锁定信息

至少更新：

- <code>Config/sources.lock.json</code>
  - <code>vlckit.base_commit</code>
  - <code>libvlc.base_commit</code>
  - <code>libvlc.patch_count</code>
  - <code>libvlc.patched_tree</code>
  - 所有实际变化的 contrib version/commit/checksum
  - Xcode、SDK 和 deployment target
- <code>compileAndBuildVLCKit.sh</code>
  - 新 libVLC base
  - 新 patched tree
  - 新上游构建入口对应的 clean checkout 逻辑
- <code>Config/audio-ios.env</code>
  - 新 configure 参数、contrib allowlist、模块删除表
- <code>Config/module-policy.yml</code>
  - 新版真实模块名和 required/forbidden 集合
- <code>Config/audio-ios-exported-symbols.txt</code>
  - 经过 Review 的公开符号面
- <code>Config/required-capabilities.yml</code>
  - 只有产品范围变化时才修改；不能为让测试通过而缩小需求
- <code>Package.swift</code>
  - 合并新版 Swift tools version、product/target 结构和最低系统要求
  - 声明的平台必须与最终 XCFramework 的实际 slice 一致；当前音频产物只有 iOS Device/Simulator 时，不能沿用上游通用多平台承诺
  - 源码集成提交中不预填尚未生成的 release URL/checksum；最终值由不可变 ZIP 生成后再写入 tag 专属 manifest
- <code>Scripts/update-swiftpm-manifest.sh</code> 与 <code>.github/workflows/publish-swift-package-prerelease.yml</code>
  - 若新版 <code>Package.swift</code> 改变 <code>binaryTarget</code> 布局，必须同步更新精确匹配和失败测试
  - workflow 必须从已 Review 的 upgrade commit 构建，不得从浮动默认分支猜测源码

计算新版 tree：

~~~bash
patched_tree=$(git -C "$vlc_worktree" rev-parse "HEAD^{tree}")
patch_count="${#all_patches[@]}"

printf "patch_count=%s\npatched_tree=%s\n" \
  "$patch_count" "$patched_tree"
~~~

## 10. 阶段 E：证明补丁可重放

提交构建前，必须从新 libVLC base 创建第二个临时 worktree，完整重放外层补丁：

~~~bash
replay_root=$(mktemp -d /private/tmp/musicfree-vlc-replay.XXXXXX)
replay_worktree="$replay_root/vlc"

git -C "$vlc_repo" worktree add --detach \
  "$replay_worktree" "$new_vlc_base"

replay_patches=(
  "$vlckit_worktree"/libvlc/patches/*.patch
)
test "${#replay_patches[@]}" -eq "$patch_count"
git -C "$replay_worktree" am "${replay_patches[@]}"

actual_tree=$(git -C "$replay_worktree" rev-parse "HEAD^{tree}")
expected_tree=$(jq -r .libvlc.patched_tree \
  "$vlckit_worktree/Config/sources.lock.json")

test "$actual_tree" = "$expected_tree"
test -z "$(git -C "$replay_worktree" \
  status --porcelain --untracked-files=all)"

git -C "$vlc_repo" worktree remove "$replay_worktree"
~~~

commit hash 会因 commit metadata 变化，不能作为补丁重放的稳定判断；tree hash 才是这里的固定契约。若 tree 不一致，先修复补丁或 lock，禁止修改审计规则绕过。

## 11. 阶段 F：先提交干净源码，再构建

r5 的复现性缺口来自 dirty VLCKit/libVLC worktree。新版必须先检查待提交内容，完成源码提交，再用硬断言确认两个源码 worktree 干净：

~~~bash
git -C "$vlckit_worktree" diff --check \
  -- . ":(exclude)libvlc/patches/*MusicFree*.patch"
git -C "$vlckit_worktree" diff --cached --check \
  -- . ":(exclude)libvlc/patches/*MusicFree*.patch"

outer_scripts=(
  "$vlckit_worktree/compileAndBuildVLCKit.sh" \
  "$vlckit_worktree"/Scripts/*.sh
)
test "${#outer_scripts[@]}" -gt 1
for script in "${outer_scripts[@]}"; do
  bash -n "$script"
done

jq -e . "$vlckit_worktree/Config/sources.lock.json" >/dev/null

git -C "$vlckit_worktree" status --short
git -C "$vlckit_worktree" diff --name-status
git -C "$vlckit_worktree" diff

# This dedicated worktree has not built yet. Stage only after every path above
# is identified as part of this upgrade. Split logical groups here if needed.
git -C "$vlckit_worktree" add -A
git -C "$vlckit_worktree" diff --cached --name-status
git -C "$vlckit_worktree" diff --cached
git -C "$vlckit_worktree" diff --cached --check \
  -- . ":(exclude)libvlc/patches/*MusicFree*.patch"
test -n "$(git -C "$vlckit_worktree" \
  diff --cached --name-only)"

staged_diff_sha256=$(git -C "$vlckit_worktree" \
  diff --cached --binary | shasum -a 256 | awk '{print $1}')
printf "staged_diff_sha256=%s\n" "$staged_diff_sha256"
reviewed_staged_diff_sha256=REPLACE_WITH_APPROVED_STAGED_DIFF_SHA256
source_review_approval=REPLACE_WITH_REVIEW_REFERENCE
test -n "$reviewed_staged_diff_sha256"
test "$reviewed_staged_diff_sha256" != \
  "REPLACE_WITH_APPROVED_STAGED_DIFF_SHA256"
test "$reviewed_staged_diff_sha256" = "$staged_diff_sha256"
test -n "$source_review_approval"
test "$source_review_approval" != "REPLACE_WITH_REVIEW_REFERENCE"
git -C "$vlckit_worktree" commit \
  -m "libvlc: migrate MusicFree audio profile to $new_vlc_base"

outer_commit=$(git -C "$vlckit_worktree" rev-parse HEAD)
vlc_commit=$(git -C "$vlc_worktree" rev-parse HEAD)
test -z "$(git -C "$vlckit_worktree" \
  status --porcelain --untracked-files=all)"
test -z "$(git -C "$vlc_worktree" \
  status --porcelain --untracked-files=all)"
test "$(git -C "$vlc_worktree" rev-parse "HEAD^{tree}")" \
  = "$(jq -r .libvlc.patched_tree \
    "$vlckit_worktree/Config/sources.lock.json")"
~~~

嵌套 mail patch 中的统一 diff 上下文空行可能被外层 <code>git diff --check</code> 报告为 trailing whitespace。必须确认提示只来自嵌套补丁语法，不能因此删除统一 diff 必需的前缀。

上述 <code>outer_commit</code> 和 <code>vlc_commit</code> 必须写入升级记录。只显示 <code>git status</code> 不算通过；任一 <code>test</code> 失败都停止构建。

建议将升级拆成便于 Review 的提交：

1. <code>vlckit: merge upstream &lt;tag/commit&gt;</code>
2. <code>libvlc: rebase MusicFree audio profile onto &lt;commit&gt;</code>
3. <code>build: update audio policy and source locks</code>
4. <code>docs: record &lt;upgrade_id&gt; validation status</code>

实际历史可以因冲突范围调整，但不要把二进制产物混入源码提交。

## 12. 阶段 G：干净构建和打包

使用全新的 build/install/cache 路径，不复用 r5：

~~~bash
evidence_root=REPLACE_WITH_EXISTING_ABSOLUTE_DURABLE_DIRECTORY
test -n "$evidence_root"
test "$evidence_root" != \
  "REPLACE_WITH_EXISTING_ABSOLUTE_DURABLE_DIRECTORY"
test -d "$evidence_root"
evidence_root=$(cd "$evidence_root" && pwd -P)
case "$evidence_root" in
  /private/tmp|/private/tmp/*|/tmp|/tmp/*)
    printf "evidence_root must not be a temporary directory: %s\n" \
      "$evidence_root" >&2
    exit 1
    ;;
esac

# Evidence must survive removal of source and temporary worktrees.
for disposable_root in \
  "$vlckit_repo" \
  "$vlckit_worktree" \
  "$upstream_vlckit_worktree" \
  "$upgrade_root"
do
  disposable_root=$(cd "$disposable_root" && pwd -P)
  case "$evidence_root/" in
    "$disposable_root/"*)
      printf "evidence_root is inside disposable source: %s\n" \
        "$disposable_root" >&2
      exit 1
      ;;
  esac
done

first_evidence="$evidence_root/$upgrade_id/first-build"
test ! -e "$first_evidence"
mkdir -p "$first_evidence"

build_root="$vlckit_worktree/build-audio-ios-$upgrade_id"
cache_root="$upgrade_root/build-cache-$upgrade_id"
vlc_build_root="$cache_root/vlc-build"
install_root="$cache_root/vlc-install"

(
  cd "$vlckit_worktree"
  MUSICFREE_BUILD_ROOT="$build_root" \
  MUSICFREE_VLC_BUILD_ROOT="$vlc_build_root" \
  MUSICFREE_INSTALL_ROOT="$install_root" \
  env -u VLC_PATH MAKEFLAGS=-j2 \
    ./compileAndBuildVLCKit.sh -f -r

  MUSICFREE_VLCKIT_BUILD_ROOT="$build_root" \
    ./Scripts/package-release.sh
)

test -z "$(git -C "$vlckit_worktree" \
  status --porcelain --untracked-files=all)"
test -z "$(git -C "$vlc_worktree" \
  status --porcelain --untracked-files=all)"
first_checksum=$(cat "$build_root/release/swiftpm-checksum.txt")
test -n "$first_checksum"
cp -R "$build_root/release/." "$first_evidence/"
test -f "$first_evidence/build-manifest.json"
test -f "$first_evidence/swiftpm-checksum.txt"
~~~

<code>package-release.sh</code> 会生成 metadata、ZIP/checksum、合规材料并运行 SwiftPM consumer。不要在它完成之前删除 archive、DerivedData 或底层 build/install 目录。

底层 build/install cache 必须位于 libVLC source worktree 外部。当前 VLC <code>.gitignore</code> 不会匹配 <code>audio-ios-build-*</code> 这类目录；把它们放进源码树会重新制造 dirty-source 证据。

### 12.1 第二次独立构建

第二次构建从已经提交的外层 commit 和可携带补丁开始，不复用第一次的 libVLC helper branch、contrib、build 或 install cache：

~~~bash
second_root=$(mktemp -d /private/tmp/musicfree-vlckit-repro.XXXXXX)
second_vlckit_worktree="$second_root/VLCKit"
second_vlc_worktree="$second_vlckit_worktree/libvlc/vlc"

git -C "$vlckit_repo" worktree add --detach \
  "$second_vlckit_worktree" "$outer_commit"
git -C "$vlc_repo" worktree add --detach \
  "$second_vlc_worktree" "$new_vlc_base"

second_patches=(
  "$second_vlckit_worktree"/libvlc/patches/*.patch
)
test "${#second_patches[@]}" -eq "$patch_count"
git -C "$second_vlc_worktree" am "${second_patches[@]}"
test "$(git -C "$second_vlc_worktree" rev-parse "HEAD^{tree}")" \
  = "$patched_tree"

second_build_root="$second_vlckit_worktree/build-audio-ios-$upgrade_id-repro"
second_cache_root="$second_root/build-cache"
second_evidence="$evidence_root/$upgrade_id/second-build"
test ! -e "$second_evidence"
mkdir -p "$second_evidence"

(
  cd "$second_vlckit_worktree"
  MUSICFREE_BUILD_ROOT="$second_build_root" \
  MUSICFREE_VLC_BUILD_ROOT="$second_cache_root/vlc-build" \
  MUSICFREE_INSTALL_ROOT="$second_cache_root/vlc-install" \
  env -u VLC_PATH MAKEFLAGS=-j2 \
    ./compileAndBuildVLCKit.sh -f -r

  MUSICFREE_VLCKIT_BUILD_ROOT="$second_build_root" \
    ./Scripts/package-release.sh
)

second_checksum=$(cat \
  "$second_build_root/release/swiftpm-checksum.txt")
test "$first_checksum" = "$second_checksum"
test -z "$(git -C "$second_vlckit_worktree" \
  status --porcelain --untracked-files=all)"
test -z "$(git -C "$second_vlc_worktree" \
  status --porcelain --untracked-files=all)"
cp -R "$second_build_root/release/." "$second_evidence/"
test -f "$second_evidence/build-manifest.json"
test -f "$second_evidence/swiftpm-checksum.txt"

printf "first=%s\nsecond=%s\n" \
  "$first_checksum" "$second_checksum"
~~~

### 12.2 生成固定 schema 的复现报告

checksum 相等只是一个比较项。以下报告还比较 source contract、toolchain、slice/architecture、Mach-O 与 dSYM hash/UUID/大小、静态模块、FFmpeg、符号和系统依赖。任一项不同都输出 <code>failed</code> 并终止：

~~~bash
reproducibility_report="$evidence_root/$upgrade_id/reproducibility.json"
first_comparison_manifest="$first_evidence/build-manifest.pre-repro.json"
second_comparison_manifest="$second_evidence/build-manifest.pre-repro.json"
cp "$first_evidence/build-manifest.json" "$first_comparison_manifest"
cp "$second_evidence/build-manifest.json" "$second_comparison_manifest"
/usr/bin/env -i \
PATH=/usr/bin:/bin:/usr/sbin:/sbin \
FIRST_MANIFEST="$first_comparison_manifest" \
SECOND_MANIFEST="$second_comparison_manifest" \
FIRST_CHECKSUM="$first_checksum" \
SECOND_CHECKSUM="$second_checksum" \
OUTER_COMMIT="$outer_commit" \
PATCHED_TREE="$patched_tree" \
FIRST_BUILD_ROOT="$build_root" \
SECOND_BUILD_ROOT="$second_build_root" \
FIRST_CACHE_ROOT="$cache_root" \
SECOND_CACHE_ROOT="$second_cache_root" \
REPORT_PATH="$reproducibility_report" \
/usr/bin/ruby -rjson -rdigest -e '
  def pick(hash, *keys)
    keys.each_with_object({}) { |key, out| out[key] = hash.fetch(key) }
  end

  def canonical(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) do |key, out|
        out[key] = canonical(value.fetch(key))
      end
    when Array
      value.map { |entry| canonical(entry) }
    else
      value
    end
  end

  def slice_projection(slice)
    projected = pick(
      slice,
      "library_identifier",
      "architectures",
      "supported_platform",
      "supported_platform_variant",
      "framework_binary_sha256",
      "framework_binary_size_bytes",
      "framework_size_bytes",
      "binary_uuids",
      "dependencies",
      "static_module_count",
      "static_module_sha256",
      "symbol_audit"
    )
    projected["dsym"] = pick(
      slice.fetch("dsym"),
      "dwarf_sha256",
      "dwarf_size_bytes",
      "uuids",
      "matches_binary"
    )
    projected
  end

  def projection(manifest)
    source = manifest.fetch("source")
    {
      "profile" => manifest.fetch("profile"),
      "source_contract" => pick(
        source,
        "vlckit_commit",
        "vlckit_expected_commit",
        "libvlc_base_commit",
        "contrib_lock",
        "sources_lock_sha256",
        "audio_profile_sha256",
        "module_policy_sha256",
        "required_capabilities_sha256",
        "build_script_sha256"
      ),
      "toolchain" => manifest.fetch("toolchain"),
      "available_libraries" =>
        manifest.fetch("artifact").fetch("available_libraries"),
      "xcframework_size_bytes" =>
        manifest.fetch("artifact").fetch("xcframework_size_bytes"),
      "slices" => manifest.fetch("slices")
        .map { |slice| slice_projection(slice) }
        .sort_by { |slice| slice.fetch("library_identifier") },
      "static_modules" => manifest.fetch("static_modules"),
      "ffmpeg" => manifest.fetch("ffmpeg"),
      "linkage_audit" => manifest.fetch("linkage_audit")
    }
  end

  first_path = ENV.fetch("FIRST_MANIFEST")
  second_path = ENV.fetch("SECOND_MANIFEST")
  first = JSON.parse(File.read(first_path))
  second = JSON.parse(File.read(second_path))
  first_projection = canonical(projection(first))
  second_projection = canonical(projection(second))
  first_checksum = ENV.fetch("FIRST_CHECKSUM")
  second_checksum = ENV.fetch("SECOND_CHECKSUM")
  outer_commit = ENV.fetch("OUTER_COMMIT")

  comparisons = {
    "archive_checksum_equal" => first_checksum == second_checksum,
    "first_manifest_archive_matches" =>
      first.dig("release", "swiftpm_checksum") == first_checksum &&
      first.dig("release", "archive_sha256") == first_checksum,
    "second_manifest_archive_matches" =>
      second.dig("release", "swiftpm_checksum") == second_checksum &&
      second.dig("release", "archive_sha256") == second_checksum,
    "outer_commit_equal" =>
      first.dig("source", "vlckit_commit") == outer_commit &&
      second.dig("source", "vlckit_commit") == outer_commit,
    "source_worktrees_clean" =>
      first.dig("source", "vlckit_worktree", "dirty") == false &&
      first.dig("source", "libvlc_worktree", "dirty") == false &&
      second.dig("source", "vlckit_worktree", "dirty") == false &&
      second.dig("source", "libvlc_worktree", "dirty") == false,
    "binary_and_policy_projection_equal" =>
      first_projection == second_projection
  }
  status = comparisons.values.all? ? "passed" : "failed"
  report = {
    "schema_version" => 1,
    "status" => status,
    "profile" => "musicfree-audio-ios",
    "source" => {
      "outer_commit" => outer_commit,
      "libvlc_patched_tree" => ENV.fetch("PATCHED_TREE")
    },
    "first_build" => {
      "build_root" => ENV.fetch("FIRST_BUILD_ROOT"),
      "cache_root" => ENV.fetch("FIRST_CACHE_ROOT"),
      "comparison_manifest" => File.basename(first_path),
      "manifest_sha256" => Digest::SHA256.file(first_path).hexdigest,
      "projection_sha256" => Digest::SHA256.hexdigest(
        JSON.generate(first_projection)
      ),
      "artifact_sha256" => first_checksum
    },
    "second_build" => {
      "build_root" => ENV.fetch("SECOND_BUILD_ROOT"),
      "cache_root" => ENV.fetch("SECOND_CACHE_ROOT"),
      "comparison_manifest" => File.basename(second_path),
      "manifest_sha256" => Digest::SHA256.file(second_path).hexdigest,
      "projection_sha256" => Digest::SHA256.hexdigest(
        JSON.generate(second_projection)
      ),
      "artifact_sha256" => second_checksum
    },
    "comparisons" => comparisons
  }
  File.write(ENV.fetch("REPORT_PATH"), JSON.pretty_generate(report) + "\n")
  abort "reproducibility comparison failed" unless status == "passed"
'

jq -e \
  --arg outer "$outer_commit" \
  --arg tree "$patched_tree" \
  '.schema_version == 1 and .status == "passed" and
   .source.outer_commit == $outer and
   .source.libvlc_patched_tree == $tree and
   all(.comparisons[]; . == true)' \
  "$reproducibility_report" >/dev/null
reproducibility_sha256=$(shasum -a 256 "$reproducibility_report" \
  | awk '{print $1}')

cp "$reproducibility_report" \
  "$build_root/release/reproducibility.json"
cp "$reproducibility_report" \
  "$second_build_root/release/reproducibility.json"

MUSICFREE_VLCKIT_BUILD_ROOT="$build_root" \
MUSICFREE_VLCKIT_RELEASE_ROOT="$build_root/release" \
  "$vlckit_worktree/Scripts/generate-build-metadata.sh"
MUSICFREE_VLCKIT_BUILD_ROOT="$second_build_root" \
MUSICFREE_VLCKIT_RELEASE_ROOT="$second_build_root/release" \
  "$second_vlckit_worktree/Scripts/generate-build-metadata.sh"

for manifest in \
  "$build_root/release/build-manifest.json" \
  "$second_build_root/release/build-manifest.json"
do
  jq -e \
    '.validation.second_clean_build_reproducibility == "passed"' \
    "$manifest" >/dev/null
done

cp -R "$build_root/release/." "$first_evidence/"
cp -R "$second_build_root/release/." "$second_evidence/"
printf "%s  reproducibility.json\n" "$reproducibility_sha256" \
  > "$evidence_root/$upgrade_id/reproducibility.sha256"
test "$(shasum -a 256 "$first_evidence/reproducibility.json" \
  | awk '{print $1}')" = "$reproducibility_sha256"
test "$(shasum -a 256 "$second_evidence/reproducibility.json" \
  | awk '{print $1}')" = "$reproducibility_sha256"
~~~

该 schema 的 projection 是复现性契约；新版 manifest 增删影响二进制或策略的字段时，必须同步 Review projection，不能让新字段落在比较之外。报告中的绝对 build/cache 路径只用于证明两次隔离，不作为可重现输入。

<code>release/</code> 之外若有 manifest 引用的 build log、module inventory 或原始审计文件，也必须复制到对应 evidence 目录并保存 hash。清理前对上述两个 evidence 目录及 reproducibility report 做存在性和 hash 检查；临时 worktree 中的副本不是交接位置。

结果不同必须记录差异来源并保持 blocked。<code>package-release.sh</code> 负责归一化 ZIP metadata；这不等于允许忽略二进制内容差异。

## 13. 每次升级必须重跑的门禁

### 13.0 测试输入和环境合同

运行门禁前先在升级记录中锁定测试输入。当前仓库没有足以自动证明全部真机/协议门禁的完整 fixture 和服务环境，因此缺少以下任一项时必须标记 <code>blocked</code> 或 <code>not-run</code>：

- 工具链：Xcode/SDK/clang/Swift 完整版本，以及 Bash、Ruby、jq、rg、zip 和构建系统版本。
- 音频 fixture manifest：11 类格式每个样本的 SHA-256、来源/许可、预期时长、关键 metadata/artwork 和至少一个合法 Seek 点。
- 协议服务 manifest：HTTP/HTTPS、SMB2/3、FTP/FTPS/FTPES、NFS 服务版本、配置、证书模式、测试文件 checksum 和受控失败场景。secret 只通过临时安全渠道提供，不写入仓库或日志。
- 真机矩阵：设备型号、iOS build、连接方式、音频路由和电源/网络条件。
- 零联网证据方法：受控抓包、运行时拒绝 harness 或二者组合；记录观察接口、时间窗口、过滤条件、原始日志 hash 和判定人。
- 体积/性能基线：上一实际发布版同架构 Mach-O、启动/首播、CPU、内存、功耗测量方法。

门禁与持久证据的固定映射如下。表中“当前无 runner”不是让 agent 自行猜命令，而是明确 blocker：必须先提交可 Review 的 harness/操作规程，或保持 <code>blocked</code>。

| Gate | Producer | Required durable evidence |
| --- | --- | --- |
| 静态模块/符号/依赖/header | <code>package-release.sh</code> -> <code>generate-build-metadata.sh</code> | <code>build-manifest.json</code>、<code>module-inventory.json</code>、<code>internal-video-symbol-audit.json</code> |
| SwiftPM 本地资产 consumer | <code>package-release.sh</code> -> <code>verify-swiftpm-consumer.sh</code> | <code>swiftpm-consumer.json</code> 和 build log hash |
| 二次干净构建 | 第 12.2 节固定 projection 比较 | <code>reproducibility.json</code> 与 <code>reproducibility.sha256</code> |
| 11 类格式 | 当前无仓库 runner；必须提供锁定 fixtures 和真机 harness | <code>format-matrix.json</code>，每行 fixture SHA-256、各检查结果和原始日志 hash |
| 协议矩阵 | 当前无仓库 runner；必须提供受控服务 manifest 和真机 harness | <code>network-protocol-matrix.json</code>，每行服务配置 hash、成功/失败检查和抓包/日志 hash |
| 无 grant 零联网 | 当前无仓库 runner；必须提供抓包或网络拒绝 harness | <code>zero-network-evidence.json</code>，每个场景的观察窗口、接口、capture hash 和空连接列表 |
| 真机/后台/路由/长播 | 当前无仓库 runner；必须提供设备操作规程 | <code>physical-device.json</code>，设备/iOS/audio route、逐项结果和日志 hash |
| 体积/性能/功耗 | 当前只生成 Mach-O 体积对比；其余无 runner | <code>performance.json</code>，基线/候选方法、样本、结果和原始数据 hash |
| SBOM/LGPL/法律 | <code>generate-compliance.sh</code> 加对应源码、重链接材料和审批输入 | <code>compliance.json</code>、SBOM、licenses、source bundle/relink hash 和法律 Review reference |

当前 <code>generate-compliance.sh</code> 会有意生成 <code>generated-unreviewed</code>，且把 source provenance、relink material 和 legal review 保持为开放状态；这只够工程预发布。第一次生产升级必须先让脚本消费维护者或法务提供的结构化审批输入，生成 <code>legal-review.json</code>，并把它与准确的 outer commit、patched tree、产物、<code>compliance.json</code> 和 SBOM hash 绑定。agent 不得自行把审批状态改成 passed，也不得直接编辑 release 目录伪造通过。

生产候选的最小审批数据契约如下；所有 hash 都必须来自完成两次干净构建后冻结的候选。审批报告是外部 Review 的机器可读副本，不是 agent 自批结果：

~~~json
{
  "schema_version": 1,
  "status": "approved",
  "approval_reference": "REPLACE_WITH_LEGAL_REVIEW_REFERENCE",
  "approver": "reviewer identity",
  "approved_at": "ISO-8601 timestamp",
  "scope": {
    "outer_commit": "40-character commit",
    "libvlc_patched_tree": "40-character tree",
    "artifact_sha256": "64-character sha256",
    "compliance_json_sha256": "64-character sha256",
    "sbom_sha256": "64-character sha256"
  }
}
~~~

生产候选 workflow 必须把已批准的报告作为不可变输入，断言 CI 重建 ZIP 与 <code>scope.artifact_sha256</code> 相同，再把报告放入 compliance archive。工程预发布没有批准报告时保持法律 gate 为 open，不能借用另一候选的报告。

所有缺失 runner 和 schema 扩展必须在构建源码 commit 中实现；禁止在 release 目录手填 <code>passed</code>。生产候选在发布前至少执行以下机器断言：

~~~bash
release_dir="$build_root/release"
runtime_reports=(
  format-matrix.json
  network-protocol-matrix.json
  zero-network-evidence.json
  physical-device.json
)
for report in "${runtime_reports[@]}"; do
  jq -e \
    '.schema_version == 1 and
     .status == "passed" and .claimable == true' \
    "$release_dir/$report" >/dev/null
done

jq -e \
  '.schema_version == 1 and .status == "passed" and
   .package_dump == "passed" and .swift_build == "passed" and
   .ios_link == "passed" and
   .checksum_matches_archive_sha256 == true' \
  "$release_dir/swiftpm-consumer.json" >/dev/null
jq -e \
  '.schema_version == 1 and .status == "passed" and
   all(.comparisons[]; . == true)' \
  "$release_dir/reproducibility.json" >/dev/null

required_compliance_gates=(
  sbom_generated
  license_texts_collected
  source_provenance
  relink_material
  legal_review
)
jq -e \
  '.schema_version == 1 and .status == "passed" and
   (.gates | type == "object") and
   all(.gates[]; . == "passed")' \
  "$release_dir/compliance.json" >/dev/null
for gate in "${required_compliance_gates[@]}"; do
  jq -e --arg gate "$gate" \
    '.gates[$gate] == "passed"' \
    "$release_dir/compliance.json" >/dev/null
done

legal_review_report="$release_dir/legal-review.json"
test -f "$legal_review_report"
compliance_json_sha256=$(shasum -a 256 \
  "$release_dir/compliance.json" | awk '{print $1}')
sbom_sha256=$(shasum -a 256 \
  "$release_dir/sbom.spdx.json" | awk '{print $1}')
jq -e \
  --arg outer "$outer_commit" \
  --arg tree "$patched_tree" \
  --arg artifact "$first_checksum" \
  --arg compliance "$compliance_json_sha256" \
  --arg sbom "$sbom_sha256" \
  '.schema_version == 1 and .status == "approved" and
   (.approval_reference | type == "string" and length > 0) and
   .approval_reference != "REPLACE_WITH_LEGAL_REVIEW_REFERENCE" and
   (.approver | type == "string" and length > 0) and
   (.approved_at | type == "string" and length > 0) and
   .scope.outer_commit == $outer and
   .scope.libvlc_patched_tree == $tree and
   .scope.artifact_sha256 == $artifact and
   .scope.compliance_json_sha256 == $compliance and
   .scope.sbom_sha256 == $sbom' \
  "$legal_review_report" >/dev/null
legal_review_sha256=$(shasum -a 256 \
  "$legal_review_report" | awk '{print $1}')
legal_review_evidence="$evidence_root/$upgrade_id/legal-review"
test ! -e "$legal_review_evidence"
mkdir -p "$legal_review_evidence"
cp "$legal_review_report" "$legal_review_evidence/legal-review.json"
printf "%s  legal-review.json\n" "$legal_review_sha256" \
  > "$legal_review_evidence/legal-review.sha256"
(
  cd "$legal_review_evidence"
  shasum -a 256 -c legal-review.sha256
)
jq -e \
  '.schema_version == 1 and .release_ready == true and
   .validation.static_release_audit == "passed" and
   .validation.second_clean_build_reproducibility == "passed"' \
  "$release_dir/build-manifest.json" >/dev/null
test -f "$release_dir/performance.json"
jq -e '.schema_version == 1 and .status == "passed"' \
  "$release_dir/performance.json" >/dev/null
~~~

通过标准必须是机器可判断或人工步骤明确：

- 格式矩阵每个样本的 import、probe、metadata、artwork、首播、Seek、连续播放和 teardown 全部 passed。
- 协议矩阵每个允许协议的成功、认证、Seek 和受控失败用例 passed，所有非白名单入口稳定失败。
- 零联网场景在完整观察窗口内没有任何出站连接尝试；仅“没有业务请求日志”不算证据。
- 真机后台、锁屏、路由和中断用例没有崩溃、卡死、泄漏或无法恢复。
- 任一必需用例 failed/blocked/not-run 时，整体 <code>release_ready</code> 保持 false。

### 13.1 源码和补丁

- VLCKit/libVLC/contrib/toolchain 全部锁定到完整 commit/version/checksum。
- 外层和嵌套源码工作树 clean。
- 新 base 完整重放补丁后 tree hash 匹配。
- module allow/deny/required policy 根据新版实际产物更新。
- 上游已合并的旧 patch 已删除，不重复维护。

### 13.2 二进制和 SwiftPM

- iOS Device arm64、Simulator arm64/x86_64 slice 正确。
- dSYM UUID 与各 slice 匹配。
- 最终 Mach-O 不依赖 VideoToolbox、OpenGLES、AVKit 等视频框架。
- 无导出视频符号，内部视频符号审计也必须通过既定规则。
- forbidden module/FFmpeg video component 不存在，required module 全部存在。
- 公开 headers/module map 不重新暴露视频、发现、字幕或任意 option API。
- SwiftPM checksum 等于 ZIP SHA-256，空 consumer 可以 import/link。
- <code>Package.swift</code> 的平台声明与 XCFramework slice 一致，tag 中 URL/checksum 精确指向该 tag 的不可变资产。
- Device Mach-O 与上一发布版同口径比较，体积增长有明确解释和 Review。

### 13.3 运行时和真机

- 11 类音频格式：import、probe、metadata、artwork、首播、Seek、rate、EQ、连续播放、teardown。
- HTTP/HTTPS、SMB2/3、FTP/FTPS/FTPES、NFS 单文件直链、认证、Range/Seek 和失败路径。
- 无 grant 的启动、扫描、metadata、artwork、队列恢复全过程零连接证据。
- 非白名单协议、目录 URL、播放列表、跨 origin 凭据泄漏等负向测试。
- iPhone 后台、锁屏、耳机/蓝牙/扬声器路由、中断恢复、长时播放、功耗和内存。

Simulator 或静态模块名不能代替真机证据。上游升级会使旧 runtime evidence 失效，必须用新二进制重跑。

### 13.4 合规和发布

- 新 contrib 的许可证、notice、SBOM 条目和源码 URL 完整。
- 无 GPL/nonfree 组件进入音频 profile。
- LGPL 对应源码、修改补丁、构建脚本、重新链接材料和 dSYM 齐全。
- 第二次干净构建证据通过。
- release ZIP/tag/checksum 不可变；任何二进制变化使用新版本。
- 法律/发布 Review 未完成时保持 <code>release_ready: false</code>。

## 14. 阶段 H：SwiftPM 预发布与远端回读

### 14.1 发布对象和状态边界

当前 MusicFree 发布链分为三个对象：

1. <code>Scripts/package-release.sh</code> 在本地或 CI 中生成 XCFramework ZIP、checksum、SwiftPM consumer 结果和内嵌 LGPL/SBOM 材料，不修改远端。
2. <code>Scripts/update-swiftpm-manifest.sh</code> 只接受 SemVer pre-release tag，并要求 <code>Package.swift</code> 中恰好有一个名为 <code>VLCKit</code> 的 URL binary target；它把最终 tag URL 和 checksum 写入 manifest。
3. <code>.github/workflows/publish-swift-package-prerelease.yml</code> 从明确选择的 Git ref 重新构建，创建只修改 <code>Package.swift</code> 的 manifest commit，在该 commit 上创建 annotated tag，再发布 GitHub pre-release 和资产。

workflow 当前只 push tag，不把 manifest commit push 回 upgrade branch。因此必须分别记录：

- <code>outer_commit</code>：workflow 实际构建的、已经 Review 的源码 commit。
- <code>tag_commit</code>：以 <code>outer_commit</code> 为唯一 parent、只更新 <code>Package.swift</code> 的 commit；SwiftPM 通过版本 tag 读取它。

不得把二者笼统写成“release commit”。也不要把 tag-only manifest commit 随手 merge 回源码分支；若团队决定同步 manifest，必须作为单独策略 Review。

工程候选可在维护者明确批准后发布为 pre-release，即使真机或法律门禁仍为 <code>blocked</code>，但 release notes 和升级记录必须保留 <code>release_ready: false</code>，且 MusicFree 生产依赖不能指向它。只有 <code>build-manifest.json</code> 的 <code>release_ready</code> 为 true、法律/发布 Review 完成后，才可作为生产升级候选。当前 workflow 只支持 pre-release，不代表已经存在稳定版发布流程。

### 14.2 发布前预检

发布脚本和 workflow 必须先进入 <code>outer_commit</code>；仅存在于某个 dirty 工作树不算可执行发布链：

~~~bash
publication_purpose=REPLACE_WITH_PUBLICATION_PURPOSE
case "$publication_purpose" in
  engineering-pre-release|production-candidate)
    ;;
  *)
    printf "invalid publication purpose: %s\n" \
      "$publication_purpose" >&2
    exit 1
    ;;
esac
if test "$publication_purpose" = "production-candidate"; then
  test -n "${legal_review_sha256:-}"
  test -f "$legal_review_evidence/legal-review.json"
  (
    cd "$legal_review_evidence"
    shasum -a 256 -c legal-review.sha256
  )
fi

release_files=(
  Package.swift
  Scripts/package-release.sh
  Scripts/generate-compliance.sh
  Scripts/verify-swiftpm-consumer.sh
  Scripts/update-swiftpm-manifest.sh
  .github/workflows/publish-swift-package-prerelease.yml
)

for release_file in "${release_files[@]}"; do
  git -C "$vlckit_worktree" ls-files --error-unmatch \
    "$release_file" >/dev/null
done

test -z "$(git -C "$vlckit_worktree" \
  status --porcelain --untracked-files=all)"
test "$(git -C "$vlckit_worktree" rev-parse HEAD)" = "$outer_commit"

for release_script in \
  Scripts/package-release.sh \
  Scripts/generate-compliance.sh \
  Scripts/verify-swiftpm-consumer.sh \
  Scripts/update-swiftpm-manifest.sh
do
  bash -n "$vlckit_worktree/$release_script"
done

package_preflight="$upgrade_root/package-preflight.json"
(
  cd "$vlckit_worktree"
  swift package dump-package --disable-sandbox \
    > "$package_preflight"
)
jq -e \
  '[.targets[] | select(.name == "VLCKit" and .type == "binary")] |
   length == 1' "$package_preflight" >/dev/null

artifact_platforms=$(plutil -extract AvailableLibraries json -o - \
  "$build_root/iOS/VLCKit.xcframework/Info.plist" \
  | jq -r '.[].SupportedPlatform' | sort -u | tr '\n' ' ')
manifest_platforms=$(jq -r '.platforms[].platformName' \
  "$package_preflight" | sort -u | tr '\n' ' ')
test "$manifest_platforms" = "$artifact_platforms"

required_ios_version=$(
  /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/bin/ruby -ryaml -e \
      'puts YAML.load_file(ARGV.fetch(0)).fetch("deployment_target")' \
      "$vlckit_worktree/Config/required-capabilities.yml"
)
manifest_ios_version=$(jq -r \
  '.platforms[] | select(.platformName == "ios") | .version' \
  "$package_preflight")
test "$manifest_ios_version" = "$required_ios_version"

publish_origin=$(git -C "$vlckit_worktree" remote get-url origin)
publish_repository=$(
  cd "$vlckit_worktree"
  gh repo view --json nameWithOwner --jq .nameWithOwner
)
printf "publish_origin=%s\npublish_repository=%s\n" \
  "$publish_origin" "$publish_repository"
gh auth status
reviewed_publish_repository=REPLACE_WITH_APPROVED_OWNER_AND_REPOSITORY
publication_approval=REPLACE_WITH_PUBLICATION_APPROVAL_REFERENCE
test -n "$reviewed_publish_repository"
test "$reviewed_publish_repository" != \
  "REPLACE_WITH_APPROVED_OWNER_AND_REPOSITORY"
test "$publish_repository" = "$reviewed_publish_repository"
test -n "$publication_approval"
test "$publication_approval" != \
  "REPLACE_WITH_PUBLICATION_APPROVAL_REFERENCE"

# After the authorized branch push, prove that CI will build outer_commit.
release_branch=$(git -C "$vlckit_worktree" branch --show-current)
test -n "$release_branch"
git -C "$vlckit_worktree" fetch origin "$release_branch"
remote_release_commit=$(git -C "$vlckit_worktree" \
  rev-parse "FETCH_HEAD^{commit}")
test "$remote_release_commit" = "$outer_commit"
~~~

先确认 <code>publish_origin</code>/<code>publish_repository</code> 是本轮获准发布的 MusicFree 仓库，GitHub 身份具有 workflow、tag 和 release 权限；不能因 remote 名为 <code>origin</code> 就默认正确。然后人工 Review <code>Package.swift</code>：Swift tools version、最低 iOS、product/target 名称和 binary target 必须与新产物一致。上游通用 manifest 当前可能声明多个 Apple 平台，但 MusicFree 音频 XCFramework 只有 iOS slice；发布前必须修正这种能力声明偏差，不能仅以 <code>dump-package</code> 能解析作为通过。

tag 使用不可复用的 SemVer pre-release，例如 <code>4.0.0-audio.20260814.1</code>。发布前确认目标 tag 和 release 都不存在、upgrade branch 已 push 且远端 commit 与 <code>outer_commit</code> 相同。push 分支、触发 workflow、创建 tag/release 都是外部发布动作，需要维护者明确授权。

若本次目的是生产升级，还必须执行：

~~~bash
jq -e '.release_ready == true' \
  "$build_root/release/build-manifest.json" >/dev/null
~~~

pre-release 工程候选不得运行这条断言后假装通过；应在升级记录中逐项保留真实的 <code>blocked</code>/<code>not-run</code> 门禁和批准人。

### 14.3 workflow 预期行为

从 GitHub Actions 手动选择精确 upgrade branch/commit，输入 <code>release_tag</code>。后续 agent 必须确认 workflow 顺序仍然是：

1. 验证 pre-release tag 格式，并拒绝已存在的 tag/release。
2. 记录并检查 Xcode/iOS SDK，然后从 clean checkout 完整构建。
3. 用固定资产名 <code>MusicFreeVLCKit.xcframework.zip</code> 打包，计算 checksum，运行 SwiftPM consumer，生成合规 archive，并把该 tarball 的 SHA-256 与 basename 单独写入 <code>compliance-checksums.txt</code>。
4. 用最终 tag、资产名和 checksum 更新 <code>Package.swift</code>，再通过结构化 <code>swift package dump-package</code> 验证 URL/checksum。
5. 拒绝除 <code>Package.swift</code> 外的 tracked file 变化；创建 manifest-only commit 和 annotated tag，只 push 该 tag。
6. 先创建 draft pre-release，上传 ZIP、checksum、SHA-256、合规 archive 和 <code>compliance-checksums.txt</code>，最后执行等价于 <code>gh release edit --draft=false</code> 的操作，将它发布为仍标记 <code>prerelease=true</code> 的非 draft release。

当前 r5 workflow 尚未发布 <code>compliance-checksums.txt</code>，所以下一次升级必须先用单独提交补上生成、上传和失败测试，再触发发布。若新版上游改变 Package/target 布局、Xcode runner、构建入口或 release asset 结构，也要先修改并 Review workflow。不能在 workflow 中用正则误匹配后静默改错 target，也不能绕过空 consumer、合规打包或远端唯一性检查。

workflow 生成的 checksum 文件固定为一行 <code>&lt;sha256&gt;  &lt;basename&gt;</code>，不能写 runner 绝对路径：

~~~bash
compliance_basename=$(basename "$compliance_archive")
compliance_archive_sha256=$(shasum -a 256 \
  "$compliance_archive" | awk '{print $1}')
test -n "$compliance_archive_sha256"
printf "%s  %s\n" \
  "$compliance_archive_sha256" "$compliance_basename" \
  > "$RELEASE_ROOT/compliance-checksums.txt"
test "$(awk 'NR == 1 {print $1}' \
  "$RELEASE_ROOT/compliance-checksums.txt")" \
  = "$compliance_archive_sha256"
~~~

workflow 在 tag push 后失败时，不移动、不覆盖、也不复用已发布 tag。保存失败 run 和残留远端状态，修复后使用递增的新 pre-release tag。

### 14.4 发布后从远端回读

workflow 绿色只证明 CI 步骤返回成功。还必须从远端 tag 和 release 重新下载、解析和计算，避免用 runner 本地文件自证：

~~~bash
release_tag=REPLACE_WITH_PUBLISHED_PRERELEASE
test -n "$release_tag"
test "$release_tag" != "REPLACE_WITH_PUBLISHED_PRERELEASE"
workflow_run_url=REPLACE_WITH_COMPLETED_WORKFLOW_RUN_URL
test -n "$workflow_run_url"
test "$workflow_run_url" != \
  "REPLACE_WITH_COMPLETED_WORKFLOW_RUN_URL"
release_verify_root=$(mktemp -d \
  /private/tmp/musicfree-vlckit-release-verify.XXXXXX)
tag_worktree="$release_verify_root/source"

git -C "$vlckit_repo" fetch origin tag "$release_tag"
test "$(git -C "$vlckit_repo" cat-file -t "$release_tag")" = "tag"
tag_commit=$(git -C "$vlckit_repo" rev-parse \
  "$release_tag^{commit}")
test "$(git -C "$vlckit_repo" rev-list --parents -n 1 \
  "$tag_commit" | wc -w | tr -d " ")" -eq 2
tag_parent=$(git -C "$vlckit_repo" rev-parse "$tag_commit^")
test "$tag_parent" = "$outer_commit"
test "$(git -C "$vlckit_repo" diff-tree --no-commit-id \
  --name-only -r "$tag_commit")" = "Package.swift"

git -C "$vlckit_repo" worktree add --detach \
  "$tag_worktree" "$tag_commit"
mkdir -p "$release_verify_root/assets"

(
  cd "$tag_worktree"
  swift package dump-package --disable-sandbox \
    > "$release_verify_root/package.json"
  gh release view "$release_tag" \
    --json tagName,isDraft,isPrerelease,url,assets \
    > "$release_verify_root/release.json"
  gh release download "$release_tag" \
    --pattern MusicFreeVLCKit.xcframework.zip \
    --dir "$release_verify_root/assets"
  gh release download "$release_tag" \
    --pattern swiftpm-checksum.txt \
    --pattern checksums.txt \
    --pattern compliance-checksums.txt \
    --pattern "MusicFreeVLCKit-compliance-$release_tag.tar.gz" \
    --dir "$release_verify_root/assets"
)

remote_archive="$release_verify_root/assets/MusicFreeVLCKit.xcframework.zip"
remote_checksum=$(swift package compute-checksum "$remote_archive")
remote_archive_sha256=$(shasum -a 256 "$remote_archive" \
  | awk '{print $1}')
remote_archive_bytes=$(wc -c < "$remote_archive" | tr -d " ")
published_checksum=$(tr -d '\r\n' \
  < "$release_verify_root/assets/swiftpm-checksum.txt")
published_sha256=$(awk 'NR == 1 {print $1}' \
  "$release_verify_root/assets/checksums.txt")
compliance_archive="$release_verify_root/assets/MusicFreeVLCKit-compliance-$release_tag.tar.gz"
test -s "$compliance_archive"
compliance_sha256=$(shasum -a 256 "$compliance_archive" \
  | awk '{print $1}')
published_compliance_sha256=$(awk 'NR == 1 {print $1}' \
  "$release_verify_root/assets/compliance-checksums.txt")
published_compliance_name=$(awk 'NR == 1 {print $2}' \
  "$release_verify_root/assets/compliance-checksums.txt" \
  | sed 's/^\*//')
unzip -Z1 "$remote_archive" \
  > "$release_verify_root/remote-archive-files.txt"
grep -Eq \
  '^VLCKit\.xcframework/LICENSES/third-party-licenses/[^/]+$' \
  "$release_verify_root/remote-archive-files.txt"
for packaged_compliance_file in \
  VLCKit.xcframework/LICENSES/THIRD-PARTY-NOTICES.md \
  VLCKit.xcframework/LICENSES/LICENSE-STATUS.md \
  VLCKit.xcframework/LICENSES/RELINKING.md \
  VLCKit.xcframework/LICENSES/compliance.json \
  VLCKit.xcframework/LICENSES/sbom.spdx.json
do
  grep -Fxq "$packaged_compliance_file" \
    "$release_verify_root/remote-archive-files.txt"
done
tar -tzf "$compliance_archive" \
  > "$release_verify_root/compliance-archive-files.txt"
for compliance_file in \
  ./THIRD-PARTY-NOTICES.md \
  ./LICENSE-STATUS.md \
  ./RELINKING.md \
  ./compliance.json \
  ./sbom.spdx.json
do
  grep -Fxq "$compliance_file" \
    "$release_verify_root/compliance-archive-files.txt"
done
if test "$publication_purpose" = "production-candidate"; then
  grep -Fxq ./legal-review.json \
    "$release_verify_root/compliance-archive-files.txt"
  tar -xOf "$compliance_archive" ./legal-review.json \
    > "$release_verify_root/remote-legal-review.json"
  remote_legal_review_sha256=$(shasum -a 256 \
    "$release_verify_root/remote-legal-review.json" \
    | awk '{print $1}')
  test "$remote_legal_review_sha256" = "$legal_review_sha256"
  jq -e '.schema_version == 1 and .status == "approved"' \
    "$release_verify_root/remote-legal-review.json" >/dev/null
fi
manifest_checksum=$(jq -r \
  '.targets[] | select(.name == "VLCKit") | .checksum' \
  "$release_verify_root/package.json")
manifest_url=$(jq -r \
  '.targets[] | select(.name == "VLCKit") | .url' \
  "$release_verify_root/package.json")
release_repository=$(
  cd "$tag_worktree"
  gh repo view --json nameWithOwner --jq .nameWithOwner
)
expected_url="https://github.com/$release_repository/releases/download/$release_tag/MusicFreeVLCKit.xcframework.zip"

test "$remote_checksum" = "$remote_archive_sha256"
test "$remote_checksum" = "$published_checksum"
test "$remote_checksum" = "$published_sha256"
test "$remote_checksum" = "$manifest_checksum"
test "$remote_checksum" = "$first_checksum"
test "$manifest_url" = "$expected_url"
test "$remote_archive_bytes" -gt 0
test "$published_compliance_name" = \
  "$(basename "$compliance_archive")"
test "$compliance_sha256" = "$published_compliance_sha256"
jq -e \
  --arg tag "$release_tag" \
  '.tagName == $tag and .isDraft == false and .isPrerelease == true' \
  "$release_verify_root/release.json" >/dev/null
~~~

随后用远端 repository + exact tag 建立全新 iOS consumer；不能复用本地 path-based consumer 或已下载的 XCFramework：

~~~bash
remote_consumer_root="$release_verify_root/remote-consumer"
mkdir -p \
  "$remote_consumer_root/Sources/Consumer" \
  "$remote_consumer_root/ModuleCache"
cp "$tag_worktree/Tests/SwiftPMConsumer/Sources/Consumer/Consumer.swift" \
  "$remote_consumer_root/Sources/Consumer/Consumer.swift"
consumer_ios_version=$(
  /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/bin/ruby -ryaml -e \
      'puts YAML.load_file(ARGV.fetch(0)).fetch("deployment_target")' \
      "$tag_worktree/Config/required-capabilities.yml"
)
test -n "$consumer_ios_version"

/usr/bin/env -i \
PATH=/usr/bin:/bin:/usr/sbin:/sbin \
RELEASE_REPOSITORY="$release_repository" \
RELEASE_TAG="$release_tag" \
IOS_DEPLOYMENT_TARGET="$consumer_ios_version" \
/usr/bin/ruby - "$remote_consumer_root/Package.swift" <<'RUBY'
repository = ENV.fetch("RELEASE_REPOSITORY")
tag = ENV.fetch("RELEASE_TAG")
deployment_target = ENV.fetch("IOS_DEPLOYMENT_TARGET")
identity = repository.split("/").last.downcase
manifest = <<~SWIFT
  // swift-tools-version: 5.9
  import PackageDescription

  let package = Package(
      name: "MusicFreeVLCKitRemoteConsumer",
      platforms: [.iOS("#{deployment_target}")],
      products: [
          .executable(
              name: "MusicFreeVLCKitRemoteConsumer",
              targets: ["MusicFreeVLCKitRemoteConsumer"]
          )
      ],
      dependencies: [
          .package(
              url: "https://github.com/#{repository}.git",
              exact: "#{tag}"
          )
      ],
      targets: [
          .executableTarget(
              name: "MusicFreeVLCKitRemoteConsumer",
              dependencies: [
                  .product(name: "VLCKit", package: "#{identity}")
              ],
              path: "Sources/Consumer"
          )
      ]
  )
SWIFT
File.write(ARGV.fetch(0), manifest)
RUBY

(
  cd "$remote_consumer_root"
  SWIFT_MODULECACHE_PATH="$remote_consumer_root/ModuleCache" \
  CLANG_MODULE_CACHE_PATH="$remote_consumer_root/ModuleCache" \
    swift package resolve --disable-sandbox \
      > "$release_verify_root/remote-consumer-resolve.log" 2>&1
  SWIFT_MODULECACHE_PATH="$remote_consumer_root/ModuleCache" \
  CLANG_MODULE_CACHE_PATH="$remote_consumer_root/ModuleCache" \
    swift build --disable-sandbox --configuration release \
      --triple "arm64-apple-ios$consumer_ios_version" \
      --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
      --product MusicFreeVLCKitRemoteConsumer \
      > "$release_verify_root/remote-consumer-build.log" 2>&1
)

package_identity=$(printf "%s" "$release_repository" \
  | awk -F/ '{print tolower($NF)}')
jq -e \
  --arg identity "$package_identity" \
  --arg tag "$release_tag" \
  --arg revision "$tag_commit" \
  '.pins[] | select(.identity == $identity) |
    .state.version == $tag and .state.revision == $revision' \
  "$remote_consumer_root/Package.resolved" >/dev/null
test -f "$remote_consumer_root/.build/arm64-apple-ios/release/MusicFreeVLCKitRemoteConsumer"

remote_release_evidence="$evidence_root/$upgrade_id/remote-release"
test ! -e "$remote_release_evidence"
mkdir -p "$remote_release_evidence"
cp "$release_verify_root/package.json" \
  "$release_verify_root/release.json" \
  "$release_verify_root/remote-consumer-resolve.log" \
  "$release_verify_root/remote-consumer-build.log" \
  "$release_verify_root/remote-archive-files.txt" \
  "$release_verify_root/compliance-archive-files.txt" \
  "$remote_consumer_root/Package.resolved" \
  "$release_verify_root/assets/swiftpm-checksum.txt" \
  "$release_verify_root/assets/checksums.txt" \
  "$release_verify_root/assets/compliance-checksums.txt" \
  "$remote_release_evidence/"
printf "archive_bytes=%s\narchive_sha256=%s\ncompliance_sha256=%s\n" \
  "$remote_archive_bytes" \
  "$remote_archive_sha256" \
  "$compliance_sha256" \
  > "$remote_release_evidence/remote-assets.txt"
if test "$publication_purpose" = "production-candidate"; then
  cp "$release_verify_root/remote-legal-review.json" \
    "$remote_release_evidence/"
  printf "legal_review_sha256=%s\n" "$remote_legal_review_sha256" \
    >> "$remote_release_evidence/remote-assets.txt"
fi
release_url=$(jq -r .url "$release_verify_root/release.json")
printf "outer_commit=%s\ntag_commit=%s\nworkflow_run=%s\nrelease_url=%s\n" \
  "$outer_commit" \
  "$tag_commit" \
  "$workflow_run_url" \
  "$release_url" \
  >> "$remote_release_evidence/remote-assets.txt"
~~~

将 workflow run URL/ID、<code>outer_commit</code>、<code>tag_commit</code>、release URL、远端 ZIP 字节数/SHA-256/checksum、合规 archive hash 和 remote consumer 结果写入升级记录。远端 ZIP 已与 <code>first_evidence</code> 中持久保存的 ZIP 做 checksum 等值断言，因此无需再保存第三份同字节副本；远端 compliance tar 必须与 CI 独立发布的 <code>compliance-checksums.txt</code> 等值，不能用下载后现场计算出的 hash 自证。<code>remote_release_evidence</code> 是本地交接副本。

验证完成后，先移除 <code>tag_worktree</code>，再按第 18 节原则处理临时目录。任何资产内容变化都必须使用新 tag；禁止替换同名 ZIP 后只更新 checksum。

## 15. 常见错误处理

| 情况 | 正确动作 |
| --- | --- |
| 新主线已包含旧 patch | 删除已 upstream 的 patch/hunk，并记录对应上游 commit |
| 文件或 API 被上游删除 | 在新 owner 重新实现能力边界，不恢复旧文件 |
| 模块重命名或拆分 | 从新静态模块表生成 inventory，再更新 policy |
| 新模块是音频路径硬依赖 | 保存调用/链接证据、体积和安全影响，经 Review 后加入 |
| 编译缺符号 | 先追踪新版调用链；不得默认把旧视频源重新加入 |
| FFmpeg 配置选项失效 | 基于新版 <code>configure --help</code> 和 config 输出重建 allowlist |
| patch 可应用但 tree 不同 | 检查 patch 顺序、生成范围和未跟踪文件，不改 expected tree 掩盖 |
| 只有 dirty worktree 能构建 | 停止发布，补齐可携带 patch/commit 后从 clean worktree 重建 |
| 真机某格式回归 | 保持 blocked，修复或经产品 Review 明确变更范围 |
| 上游完整版本可用 | 不能作为 release 静默 fallback；只能通过明确版本切换和评审 |

## 16. 升级记录模板

每次升级在 <code>Documentation/upgrades/&lt;upgrade_id&gt;.md</code> 新建记录，至少包含：

~~~markdown
# MusicFree VLCKit Upgrade <upgrade_id>

## Source Pair

- Old VLCKit base:
- New VLCKit base:
- Old libVLC base:
- New libVLC base:
- Upstream tags/refs:
- Selection reason:
- Target/source-pair approval references:

## Patch Stack

- Upstream VLCKit patch count:
- Upstream patch driver SHA-256 / mechanism approval reference:
- MusicFree patch files:
- Commit/patch scope approval references:
- Final patch count:
- Patched tree:
- Patch map path/SHA-256:
- Rebased/split/upstreamed/dropped counts:

## Conflict Decisions

| File/area | Upstream change | MusicFree intent | Resolution |
| --- | --- | --- | --- |

## Build

- Clean source commits:
- Reviewed staged diff SHA-256 / approval reference:
- Xcode/SDK/deployment target:
- Build command:
- First artifact checksum:
- Second artifact checksum:
- Durable evidence root:
- Reproducibility report/SHA-256:
- Device Mach-O bytes:
- XCFramework/ZIP bytes:

## SwiftPM Publication

- Publication purpose: engineering pre-release / production candidate
- Publication approval reference:
- Source outer commit:
- Tag manifest commit:
- Manifest-only diff verified:
- Tag/version:
- Workflow run URL/ID:
- Release URL:
- Remote archive bytes/SHA-256/SwiftPM checksum:
- Compliance archive calculated/published SHA-256:
- Legal review report/reference/hash (production only):
- Remote exact-tag consumer result:
- Package platforms match artifact slices:

## Validation

| Gate | Status | Evidence |
| --- | --- | --- |
| Patch replay |  |  |
| Static module/symbol audit |  |  |
| SwiftPM consumer |  |  |
| Audio format matrix |  |  |
| Network protocol matrix |  |  |
| Zero-network evidence |  |  |
| Physical device |  |  |
| Reproducibility |  |  |
| SBOM/LGPL |  |  |

## Test Inputs

- Fixture manifest and checksums:
- Protocol service versions/config:
- Physical device and OS matrix:
- Zero-network capture method/log hash:
- Performance/size baseline:

## Remaining Blockers

- 

## Handoff

- Outer branch/commit:
- Local libVLC helper branch/commit:
- Portable patch path:
- Artifact/release path:
- Remote tag/release and immutable asset URL:
- Source commit vs tag manifest commit:
- Cleanup approval reference:
- Temporary roots removed / retained with reason:
- Commands already run:
- Commands not run:
~~~

状态只能使用 <code>passed</code>、<code>failed</code>、<code>blocked</code> 或 <code>not-run</code>，并链接实际证据。不要用“应该可以”“理论通过”替代状态。

## 17. 后续 agent 开工清单

后续 agent 接手时按顺序读取：

1. 本文。
2. <code>Config/sources.lock.json</code>。
3. <code>Config/audio-ios.env</code>、<code>module-policy.yml</code>、<code>required-capabilities.yml</code>。
4. <code>Package.swift</code>、<code>Scripts/update-swiftpm-manifest.sh</code> 和预发布 workflow。
5. 最新 <code>Documentation/upgrades/*.md</code>。
6. 当前候选的 <code>release/VALIDATION-STATUS.md</code> 和 <code>build-manifest.json</code>。
7. 外层和嵌套仓库的 <code>git status</code>、当前分支、commit 和 tree。

开始修改前必须输出：

- 选定的 VLCKit/libVLC commit 对。
- 计划重放的 MusicFree commit/patch 范围。
- 预期冲突区域。
- 新 build id 和独立 worktree/cache 路径。
- 本轮可执行及受环境阻塞的验证项。

结束交接时必须明确区分：

- 已实现并进入 Git 的内容。
- 已由当前新产物验证的内容。
- 沿用但尚未重跑的旧证据。
- 因设备、服务、网络、法律或发布权限阻塞的内容。

## 18. 清理

升级完成或放弃后，先确认需要的 commits、patches、logs、两次构建 evidence 和 release artifacts 已保存到 worktree 外部。执行 <code>git status</code>，如果仍有 <code>cherry-pick</code> 或 <code>am</code> sequencer，先明确选择 continue 或 abort；不能靠删除目录结束。

完成了两次构建时先验证持久证据。若尚未开始构建，中止升级必须在升级记录写明没有产物可保留；若任一 build root 已创建但复现报告尚未通过，先把部分日志、产物 inventory、hash 和保留路径写入持久证据，不能把它描述成“没有产物”。下面的自动清理会拒绝删除这种部分构建，后续必须单独 Review 精确路径和部分证据后再清理：

~~~bash
build_cleanup_evidence_verified=false
if test -n "${build_root:-}" || \
   test -n "${second_build_root:-}"; then
  test -n "${build_root:-}"
  test -n "${second_build_root:-}"
  test -n "${reproducibility_report:-}"
  upgrade_evidence="$evidence_root/$upgrade_id"
  test -f "$upgrade_evidence/reproducibility.json"
  test -f "$upgrade_evidence/reproducibility.sha256"
  (
    cd "$upgrade_evidence"
    shasum -a 256 -c reproducibility.sha256
  )
  jq -e '.status == "passed" and all(.comparisons[]; . == true)' \
    "$upgrade_evidence/reproducibility.json" >/dev/null
  test -f "$upgrade_evidence/first-build/build-manifest.json"
  test -f "$upgrade_evidence/second-build/build-manifest.json"
  build_cleanup_evidence_verified=true
fi
if test -n "${remote_release_evidence:-}"; then
  test -f "$remote_release_evidence/remote-assets.txt"
  test -f "$remote_release_evidence/Package.resolved"
  test -f "$remote_release_evidence/remote-consumer-build.log"
  if test "${publication_purpose:-}" = "production-candidate"; then
    test -f "$remote_release_evidence/remote-legal-review.json"
    test "$(shasum -a 256 \
      "$remote_release_evidence/remote-legal-review.json" \
      | awk '{print $1}')" = "$legal_review_sha256"
  fi
fi
if test -n "${legal_review_evidence:-}"; then
  test -f "$legal_review_evidence/legal-review.json"
  test -f "$legal_review_evidence/legal-review.sha256"
  (
    cd "$legal_review_evidence"
    shasum -a 256 -c legal-review.sha256
  )
fi

cleanup_approval=REPLACE_WITH_CLEANUP_APPROVAL_REFERENCE
test -n "$cleanup_approval"
test "$cleanup_approval" != \
  "REPLACE_WITH_CLEANUP_APPROVAL_REFERENCE"

# Remove only generated build roots whose evidence was verified above.
generated_build_roots=(
  "${build_root:-}"
  "${second_build_root:-}"
)
for generated_root in "${generated_build_roots[@]}"; do
  test -n "$generated_root" || continue
  test "$build_cleanup_evidence_verified" = true
  case "$generated_root" in
    "${vlckit_worktree:-/__unset__}"/build-audio-ios-*|\
    "${second_vlckit_worktree:-/__unset__}"/build-audio-ios-*)
      ;;
    *)
      printf "refusing unexpected build root: %s\n" \
        "$generated_root" >&2
      exit 1
      ;;
  esac
  test -d "$generated_root"
  test ! -L "$generated_root"
  du -sh "$generated_root"
  rm -rf -- "$generated_root"
  test ! -e "$generated_root"
done
~~~

该代码块失败后不得跳到 worktree remove 或临时根目录删除步骤；build root 通常位于 worktree 内，绕过前置断言仍会间接丢失部分构建证据。

先列出 Git 已登记的 worktree：

~~~bash
git -C "$vlc_repo" worktree list
git -C "$vlckit_repo" worktree list
~~~

只对仍在列表中且内容已保存的 worktree 执行 remove，顺序固定为：

1. 第二次构建的嵌套 <code>second_vlc_worktree</code>。
2. 第二次构建的外层 <code>second_vlckit_worktree</code>。
3. 发布后远端验证的 <code>tag_worktree</code>。
4. 尚未移除的 <code>replay_worktree</code>。
5. 主集成中的嵌套 <code>vlc_worktree</code>。
6. 只读 <code>upstream_vlckit_worktree</code>。
7. 外层 <code>vlckit_worktree</code> 最后移除；它的 upgrade 分支和提交必须已确认存在。

示例：

~~~bash
git -C "$vlc_repo" worktree remove "$second_vlc_worktree"
git -C "$vlckit_repo" worktree remove "$second_vlckit_worktree"
git -C "$vlckit_repo" worktree remove "$tag_worktree"
git -C "$vlc_repo" worktree remove "$replay_worktree"
git -C "$vlc_repo" worktree remove "$vlc_worktree"
git -C "$vlckit_repo" worktree remove "$upstream_vlckit_worktree"
git -C "$vlckit_repo" worktree remove "$vlckit_worktree"
~~~

若某路径已经在前面移除，不要重复执行对应命令。<code>worktree remove</code> 拒绝时先检查 <code>git status --short --ignored</code> 和 <code>git clean -ndX</code> 的预览，不使用 <code>--force</code> 绕过，也不直接执行 <code>git clean</code>。

所有 worktree 从 Git 列表消失后，才删除本轮 <code>mktemp</code> 根。以下命令先验证名称、目录类型以及没有残留 worktree，再删除精确路径；不会触碰 <code>evidence_root</code>：

~~~bash
temporary_roots=(
  "${upgrade_root:-}"
  "${second_root:-}"
  "${replay_root:-}"
  "${release_verify_root:-}"
)
for temporary_root in "${temporary_roots[@]}"; do
  test -n "$temporary_root" || continue
  case "$temporary_root" in
    /private/tmp/musicfree-vlckit-upgrade.*|\
    /private/tmp/musicfree-vlckit-repro.*|\
    /private/tmp/musicfree-vlc-replay.*|\
    /private/tmp/musicfree-vlckit-release-verify.*)
      ;;
    *)
      printf "refusing unexpected temporary root: %s\n" \
        "$temporary_root" >&2
      exit 1
      ;;
  esac
  test -d "$temporary_root"
  test ! -L "$temporary_root"
  test -z "$(git -C "$vlckit_repo" worktree list --porcelain \
    | awk -v root="$temporary_root" \
      '$1 == "worktree" && index($2, root "/") == 1 {print $2}')"
  test -z "$(git -C "$vlc_repo" worktree list --porcelain \
    | awk -v root="$temporary_root" \
      '$1 == "worktree" && index($2, root "/") == 1 {print $2}')"
  du -sh "$temporary_root"
  find "$temporary_root" -mindepth 1 -maxdepth 1 -print
done

for temporary_root in "${temporary_roots[@]}"; do
  test -n "$temporary_root" || continue
  test -d "$temporary_root"
  rm -rf -- "$temporary_root"
  test ! -e "$temporary_root"
done

git -C "$vlc_repo" worktree list
git -C "$vlckit_repo" worktree list
~~~

不要直接递归删除未知路径，也不要清理用户原有 <code>MusicFree</code>、<code>MusicFreeVLCKit</code> 或 <code>dist</code> 内容。

已知良好 r5 产物可在新版本验收前保留作体积和行为对照，但不能作为新版本的发布证据。
