#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream_source_repo="https://github.com/hrk4649/godot_ios_plugin_iap"
upstream_source_commit="f5b3747efb066c00ea3e206ff9b4f732ade5ed37"
build_repo="https://github.com/dawn-forge/godot_ios_plugin_iap"
godot_version="4.7.0"
release_tag="dawnforge-deferred-finish-v8"
output_dir="$repo_root/dist"
preflight_only=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-commit|--upstream-source-commit) upstream_source_commit="$2"; shift 2 ;;
        --godot-version) godot_version="$2"; shift 2 ;;
        --output-dir) output_dir="$2"; shift 2 ;;
        --preflight) preflight_only=true; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ "$upstream_source_commit" == "f5b3747efb066c00ea3e206ff9b4f732ade5ed37" ]] || {
    echo "upstream source commit must remain pinned to f5b3747efb066c00ea3e206ff9b4f732ade5ed37" >&2
    exit 1
}

build_source_preflight() {
    [[ -z "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]] || {
        echo "build source must be clean" >&2
        exit 1
    }
    local actual_build_repo
    actual_build_repo="$(git -C "$repo_root" remote get-url origin)"
    actual_build_repo="${actual_build_repo%.git}"
    [[ "$actual_build_repo" == "$build_repo" ]] || {
        echo "build source must use approved fork remote" >&2
        exit 1
    }
    build_commit="$(git -C "$repo_root" rev-parse HEAD)"
    build_tag="$(git -C "$repo_root" tag --points-at "$build_commit" --list "$release_tag")"
    [[ "$build_tag" == "$release_tag" ]] || {
        echo "build source must be tagged $release_tag" >&2
        exit 1
    }
    [[ "$(git -C "$repo_root" cat-file -t "refs/tags/$release_tag")" == tag ]] || {
        echo "local release tag must be annotated" >&2
        exit 1
    }
    [[ "$(git -C "$repo_root" rev-parse "refs/tags/$release_tag^{}")" == "$build_commit" ]] || {
        echo "local release tag must peel to build commit" >&2
        exit 1
    }
    local remote_tags remote_tag_object remote_peeled_commit
    remote_tags="$(git ls-remote --tags "$build_repo" "refs/tags/$release_tag" "refs/tags/$release_tag^{}")"
    remote_tag_object="$(printf '%s\n' "$remote_tags" | awk -v tag="refs/tags/$release_tag" '$2 == tag { value = $1 } END { print value }')"
    remote_peeled_commit="$(printf '%s\n' "$remote_tags" | awk -v tag="refs/tags/$release_tag^{}" '$2 == tag { value = $1 } END { print value }')"
    [[ -n "$remote_tag_object" && -n "$remote_peeled_commit" ]] || {
        echo "remote release tag must be annotated" >&2
        exit 1
    }
    [[ "$remote_peeled_commit" == "$build_commit" ]] || {
        echo "remote release tag must peel to build commit" >&2
        exit 1
    }
}

build_source_preflight
if [[ "$preflight_only" == true ]]; then
    printf 'upstream_source_repo=%s\nupstream_source_commit=%s\nbuild_repo=%s\nbuild_commit=%s\nbuild_tag=%s\n' \
        "$upstream_source_repo" "$upstream_source_commit" "$build_repo" "$build_commit" "$build_tag"
    exit 0
fi

xcode_version="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
[[ -n "$xcode_version" ]] || {
    echo "unable to determine Xcode version" >&2
    exit 1
}

hash_tree() {
    local path="$1"
    (
        cd "$path"
        find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
            shasum -a 256 "$file"
        done
    ) | shasum -a 256 | awk '{print $1}'
}

plugin_root="$repo_root/godot_ios_plugin_iap"
[[ -x "$plugin_root/generate_static_library.sh" ]] || {
    echo "missing source build script" >&2
    exit 1
}

(
    cd "$plugin_root"
    ./generate_static_library.sh
)

release_framework="$plugin_root/bin/ios-in-app-purchase.release.xcframework"
debug_framework="$plugin_root/bin/ios-in-app-purchase.debug.xcframework"
[[ -d "$release_framework" && -d "$debug_framework" ]] || {
    echo "release and debug XCFrameworks were not produced" >&2
    exit 1
}

release_hash="$(hash_tree "$release_framework")"
debug_hash="$(hash_tree "$debug_framework")"
rm -rf "$output_dir"
mkdir -p "$output_dir/stage/ios/plugins" "$output_dir/stage/ios/framework"
cp -R "$release_framework" "$output_dir/stage/ios/plugins/"
cp -R "$debug_framework" "$output_dir/stage/ios/plugins/"
sed \
    -e "s#^DawnForgeIAPUpstreamSourceRepo=.*#DawnForgeIAPUpstreamSourceRepo=\"$upstream_source_repo\"#" \
    -e "s#^DawnForgeIAPUpstreamSourceCommit=.*#DawnForgeIAPUpstreamSourceCommit=\"$upstream_source_commit\"#" \
    -e "s#^DawnForgeIAPSourceCommit=.*#DawnForgeIAPSourceCommit=\"$upstream_source_commit\"#" \
    -e "s#^DawnForgeIAPBuildRepo=.*#DawnForgeIAPBuildRepo=\"$build_repo\"#" \
    -e "s#^DawnForgeIAPBuildCommit=.*#DawnForgeIAPBuildCommit=\"$build_commit\"#" \
    -e "s#^DawnForgeIAPBuildTag=.*#DawnForgeIAPBuildTag=\"$build_tag\"#" \
    -e "s#^DawnForgeIAPArtifactSHA256=.*#DawnForgeIAPArtifactSHA256=\"$release_hash\"#" \
    "$plugin_root/ios-in-app-purchase.gdip" > "$output_dir/stage/ios/plugins/ios-in-app-purchase.gdip"
sed \
    -e "s#^source_repo=.*#source_repo=$build_repo#" \
    -e "s#^source_commit=.*#source_commit=$upstream_source_commit#" \
    -e "s#^release_tag=.*#release_tag=$release_tag#" \
    -e "s#^upstream_source_repo=.*#upstream_source_repo=$upstream_source_repo#" \
    -e "s#^upstream_source_commit=.*#upstream_source_commit=$upstream_source_commit#" \
    -e "s#^build_repo=.*#build_repo=$build_repo#" \
    -e "s#^build_commit=.*#build_commit=$build_commit#" \
    -e "s#^build_tag=.*#build_tag=$build_tag#" \
    -e "s#^toolchain=.*#toolchain=Godot-$godot_version;Xcode-$xcode_version#" \
    -e "s#^binary_sha256=.*#binary_sha256=$release_hash#" \
    -e "s#^release_binary=.*#release_binary=ios-in-app-purchase.release.xcframework#" \
    -e "s#^release_binary_sha256=.*#release_binary_sha256=$release_hash#" \
    -e "s#^debug_binary=.*#debug_binary=ios-in-app-purchase.debug.xcframework#" \
    -e "s#^debug_binary_sha256=.*#debug_binary_sha256=$debug_hash#" \
    -e "s#^zip_sha256=.*#zip_sha256=DETACHED#" \
    "$plugin_root/ios-in-app-purchase.contract.template" > "$output_dir/stage/ios/plugins/ios-in-app-purchase.contract"

release_zip="$output_dir/ios-in-app-purchase.zip"
(
    cd "$output_dir/stage"
    find . -print | LC_ALL=C sort | zip -X -q -@ "$release_zip"
)
zip_hash="$(shasum -a 256 "$release_zip" | awk '{print $1}')"
cat > "$output_dir/release-manifest.txt" <<EOF
source_repo=$build_repo
source_commit=$upstream_source_commit
release_tag=$release_tag
upstream_source_repo=$upstream_source_repo
upstream_source_commit=$upstream_source_commit
build_repo=$build_repo
build_commit=$build_commit
build_tag=$build_tag
toolchain=Godot-$godot_version;Xcode-$xcode_version
contract_version=1
transaction_id=transactionID
verification_field=verified
finish_request=finishTransaction
auto_finish=false
deferred_finish=true
verified_transaction_ids=true
unfinished_replay=true
release_binary=ios-in-app-purchase.release.xcframework
release_binary_sha256=$release_hash
debug_binary=ios-in-app-purchase.debug.xcframework
debug_binary_sha256=$debug_hash
zip_sha256=$zip_hash
EOF
printf '%s  %s\n' "$zip_hash" "$(basename "$release_zip")" > "$release_zip.sha256"
rm -rf "$output_dir/stage"
printf 'release_zip=%s\nrelease_manifest=%s\nzip_sha256=%s\n' "$release_zip" "$output_dir/release-manifest.txt" "$zip_hash"
