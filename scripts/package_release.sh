#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_commit="f5b3747efb066c00ea3e206ff9b4f732ade5ed37"
godot_version="4.7.0"
release_tag="dawnforge-deferred-finish-v2"
output_dir="$repo_root/dist"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-commit) source_commit="$2"; shift 2 ;;
        --godot-version) godot_version="$2"; shift 2 ;;
        --output-dir) output_dir="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ "$source_commit" == "f5b3747efb066c00ea3e206ff9b4f732ade5ed37" ]] || {
    echo "source commit must remain pinned to f5b3747efb066c00ea3e206ff9b4f732ade5ed37" >&2
    exit 1
}

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
awk -v hash="$release_hash" '{ if ($0 == "DawnForgeIAPArtifactSHA256=GENERATED_AFTER_BUILD") print "DawnForgeIAPArtifactSHA256=" hash; else print }' \
    "$plugin_root/ios-in-app-purchase.gdip" > "$output_dir/stage/ios/plugins/ios-in-app-purchase.gdip"
sed \
    -e "s#^source_commit=.*#source_commit=$source_commit#" \
    -e "s#^release_tag=.*#release_tag=$release_tag#" \
    -e "s#^toolchain=.*#toolchain=Godot-$godot_version;Xcode-$xcode_version#" \
    -e "s#^binary_sha256=.*#binary_sha256=$release_hash#" \
    -e "s#^zip_sha256=.*#zip_sha256=DETACHED#" \
    "$plugin_root/ios-in-app-purchase.contract.template" > "$output_dir/stage/ios/plugins/ios-in-app-purchase.contract"

release_zip="$output_dir/ios-in-app-purchase.zip"
(
    cd "$output_dir/stage"
    find . -print | LC_ALL=C sort | zip -X -q -@ "$release_zip"
)
zip_hash="$(shasum -a 256 "$release_zip" | awk '{print $1}')"
cat > "$output_dir/release-manifest.txt" <<EOF
source_repo=https://github.com/dawn-forge/godot_ios_plugin_iap
source_commit=$source_commit
release_tag=$release_tag
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
