#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="$repo_root/scripts/verify_release.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ios-iap-v4-tests.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
failures=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

pass() {
    printf 'PASS: %s\n' "$1"
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

replace_key() {
    local file="$1" key="$2" value="$3"
    awk -F= -v key="$key" -v value="$value" '
        $1 == key { print key "=" value; next }
        { print }
    ' "$file" > "$file.next"
    mv "$file.next" "$file"
}

remove_line() {
    local file="$1" line="$2"
    awk -v line="$line" '$0 != line { print }' "$file" > "$file.next"
    mv "$file.next" "$file"
}

write_manifest() {
    local file="$1" zip_hash="$2" release_hash="$3" debug_hash="$4"
    cat > "$file" <<EOF
source_repo=https://github.com/dawn-forge/godot_ios_plugin_iap
source_commit=f5b3747efb066c00ea3e206ff9b4f732ade5ed37
release_tag=dawnforge-deferred-finish-v6
upstream_source_repo=https://github.com/hrk4649/godot_ios_plugin_iap
upstream_source_commit=f5b3747efb066c00ea3e206ff9b4f732ade5ed37
build_repo=https://github.com/dawn-forge/godot_ios_plugin_iap
build_commit=0123456789abcdef0123456789abcdef01234567
build_tag=dawnforge-deferred-finish-v6
toolchain=Godot-4.7.0;Xcode-26.6
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
}

write_contract() {
    local file="$1" release_hash="$2" debug_hash="$3"
    cat > "$file" <<EOF
source_repo=https://github.com/dawn-forge/godot_ios_plugin_iap
source_commit=f5b3747efb066c00ea3e206ff9b4f732ade5ed37
release_tag=dawnforge-deferred-finish-v6
upstream_source_repo=https://github.com/hrk4649/godot_ios_plugin_iap
upstream_source_commit=f5b3747efb066c00ea3e206ff9b4f732ade5ed37
build_repo=https://github.com/dawn-forge/godot_ios_plugin_iap
build_commit=0123456789abcdef0123456789abcdef01234567
build_tag=dawnforge-deferred-finish-v6
toolchain=Godot-4.7.0;Xcode-26.6
contract_version=1
transaction_id=transactionID
verification_field=verified
finish_request=finishTransaction
auto_finish=false
deferred_finish=true
verified_transaction_ids=true
unfinished_replay=true
binary_sha256=$release_hash
release_binary=ios-in-app-purchase.release.xcframework
release_binary_sha256=$release_hash
debug_binary=ios-in-app-purchase.debug.xcframework
debug_binary_sha256=$debug_hash
zip_sha256=DETACHED
EOF
}

make_fixture() {
    local destination="$1"
    mkdir -p "$destination/ios/plugins/ios-in-app-purchase.release.xcframework"
    mkdir -p "$destination/ios/plugins/ios-in-app-purchase.debug.xcframework"
    printf 'release fixture\n' > "$destination/ios/plugins/ios-in-app-purchase.release.xcframework/Info.plist"
    printf 'debug fixture\n' > "$destination/ios/plugins/ios-in-app-purchase.debug.xcframework/Info.plist"

    local release_hash debug_hash
    release_hash="$(hash_tree "$destination/ios/plugins/ios-in-app-purchase.release.xcframework")"
    debug_hash="$(hash_tree "$destination/ios/plugins/ios-in-app-purchase.debug.xcframework")"
    cat > "$destination/ios/plugins/ios-in-app-purchase.gdip" <<EOF
[config]
name="IOSInAppPurchase"
binary="ios-in-app-purchase.xcframework"
initialization="ios_in_app_purchase_init"
deinitialization="ios_in_app_purchase_deinit"

[plist]
DawnForgeIAPContractVersion=1
DawnForgeIAPUpstreamSourceRepo=https://github.com/hrk4649/godot_ios_plugin_iap
DawnForgeIAPUpstreamSourceCommit=f5b3747efb066c00ea3e206ff9b4f732ade5ed37
DawnForgeIAPSourceCommit=f5b3747efb066c00ea3e206ff9b4f732ade5ed37
DawnForgeIAPBuildRepo=https://github.com/dawn-forge/godot_ios_plugin_iap
DawnForgeIAPBuildCommit=0123456789abcdef0123456789abcdef01234567
DawnForgeIAPBuildTag=dawnforge-deferred-finish-v6
DawnForgeIAPArtifactSHA256=$release_hash
EOF
    write_contract "$destination/ios/plugins/ios-in-app-purchase.contract" "$release_hash" "$debug_hash"
}

pack_fixture() {
    local stage="$1" name="$2"
    artifact_zip="$tmp_dir/$name.zip"
    artifact_manifest="$tmp_dir/$name-manifest.txt"
    (
        cd "$stage"
        find . \( -type f -o -type l \) -print | LC_ALL=C sort | zip -X -y -q "$artifact_zip" -@
    )
    local release_hash debug_hash zip_hash
    release_hash="$(hash_tree "$stage/ios/plugins/ios-in-app-purchase.release.xcframework")"
    debug_hash="$(hash_tree "$stage/ios/plugins/ios-in-app-purchase.debug.xcframework")"
    zip_hash="$(shasum -a 256 "$artifact_zip" | awk '{print $1}')"
    write_manifest "$artifact_manifest" "$zip_hash" "$release_hash" "$debug_hash"
}

expect_rejected() {
    local name="$1" zip="$2" manifest="$3"
    if "$verifier" "$zip" "$manifest" >/dev/null 2>&1; then
        fail "$name was accepted"
    else
        pass "$name was rejected"
    fi
}

valid_stage="$tmp_dir/valid"
make_fixture "$valid_stage"
pack_fixture "$valid_stage" valid
if "$verifier" "$artifact_zip" "$artifact_manifest" >/dev/null; then
    pass 'valid canonical fixture'
else
    fail 'valid canonical fixture was rejected'
fi

capability_keys=(contract_version transaction_id verification_field finish_request auto_finish deferred_finish verified_transaction_ids unfinished_replay)
capability_values=(2 unexpected_id unverified unexpected_finish true false false false)
for index in "${!capability_keys[@]}"; do
    name="contract-${capability_keys[$index]}-mismatch"
    stage="$tmp_dir/$name"
    cp -R "$valid_stage" "$stage"
    replace_key "$stage/ios/plugins/ios-in-app-purchase.contract" "${capability_keys[$index]}" "${capability_values[$index]}"
    pack_fixture "$stage" "$name"
    expect_rejected "$name" "$artifact_zip" "$artifact_manifest"
done

descriptor_stage="$tmp_dir/descriptor-binary-layout"
cp -R "$valid_stage" "$descriptor_stage"
sed 's#^binary=".*"#binary="ios-in-app-purchase.release.xcframework"#' \
    "$descriptor_stage/ios/plugins/ios-in-app-purchase.gdip" > "$descriptor_stage/ios/plugins/ios-in-app-purchase.gdip.next"
mv "$descriptor_stage/ios/plugins/ios-in-app-purchase.gdip.next" "$descriptor_stage/ios/plugins/ios-in-app-purchase.gdip"
pack_fixture "$descriptor_stage" descriptor-binary-layout
expect_rejected 'descriptor binary must use canonical unsuffixed layout' "$artifact_zip" "$artifact_manifest"

marker_stage="$tmp_dir/descriptor-contract-version"
cp -R "$valid_stage" "$marker_stage"
remove_line "$marker_stage/ios/plugins/ios-in-app-purchase.gdip" 'DawnForgeIAPContractVersion=1'
pack_fixture "$marker_stage" descriptor-contract-version
expect_rejected 'descriptor contract version marker must match the manifest' "$artifact_zip" "$artifact_manifest"

escape_stage="$tmp_dir/binary-path-escape"
cp -R "$valid_stage" "$escape_stage"
cp -R "$escape_stage/ios/plugins/ios-in-app-purchase.release.xcframework" "$escape_stage/evil-release.xcframework"
cp -R "$escape_stage/ios/plugins/ios-in-app-purchase.debug.xcframework" "$escape_stage/evil-debug.xcframework"
for file in "$escape_stage/ios/plugins/ios-in-app-purchase.contract"; do
    replace_key "$file" release_binary ../../evil-release.xcframework
    replace_key "$file" debug_binary ../../evil-debug.xcframework
done
pack_fixture "$escape_stage" binary-path-escape
replace_key "$artifact_manifest" release_binary ../../evil-release.xcframework
replace_key "$artifact_manifest" debug_binary ../../evil-debug.xcframework
expect_rejected 'binary paths must not escape ios/plugins' "$artifact_zip" "$artifact_manifest"

symlink_stage="$tmp_dir/framework-symlink-escape"
cp -R "$valid_stage" "$symlink_stage"
mv "$symlink_stage/ios/plugins/ios-in-app-purchase.release.xcframework" "$symlink_stage/escape-release.xcframework"
ln -s ../../escape-release.xcframework "$symlink_stage/ios/plugins/ios-in-app-purchase.release.xcframework"
pack_fixture "$symlink_stage" framework-symlink-escape
symlink_extract="$tmp_dir/framework-symlink-extract"
unzip -q "$artifact_zip" -d "$symlink_extract"
if test -L "$symlink_extract/ios/plugins/ios-in-app-purchase.release.xcframework"; then
    pass 'archive preserves canonical framework symlink fixture'
else
    fail 'archive did not preserve canonical framework symlink fixture'
fi
expect_rejected 'canonical framework symlink must not escape ios/plugins' "$artifact_zip" "$artifact_manifest"

preflight_repo="$tmp_dir/preflight-repo"
mkdir -p "$preflight_repo/scripts"
cp "$repo_root/scripts/package_release.sh" "$preflight_repo/scripts/package_release.sh"
git -C "$preflight_repo" init -q
git -C "$preflight_repo" config user.email test@example.invalid
git -C "$preflight_repo" config user.name 'V4 Test'
git -C "$preflight_repo" remote add origin https://github.com/dawn-forge/godot_ios_plugin_iap.git
git -C "$preflight_repo" add scripts/package_release.sh
git -C "$preflight_repo" commit -qm 'fixture'
git -C "$preflight_repo" tag -a dawnforge-deferred-finish-v6 -m fixture

mock_bin="$tmp_dir/mock-bin"
mkdir -p "$mock_bin"
real_git="$(command -v git)"
cat > "$mock_bin/git" <<EOF
#!/bin/sh
for argument in "\$@"; do
    if [ "\$argument" = ls-remote ]; then
        case "\${IOS_IAP_TEST_REMOTE_MODE:-annotated}" in
            annotated)
                printf '%040d\trefs/tags/dawnforge-deferred-finish-v6\n' 1
                printf '%s\trefs/tags/dawnforge-deferred-finish-v6^{}\n' "\$IOS_IAP_TEST_BUILD_COMMIT"
                ;;
            noisy)
                printf '%040d\trefs/tags/dawnforge-deferred-finish-v6\n' 1
                count=0
                while [ "\$count" -lt 20000 ]; do
                    printf '%040d\trefs/tags/noise-%s\n' 3 "\$count"
                    count=\$((count + 1))
                done
                printf '%s\trefs/tags/dawnforge-deferred-finish-v6^{}\n' "\$IOS_IAP_TEST_BUILD_COMMIT"
                ;;
            lightweight)
                printf '%s\trefs/tags/dawnforge-deferred-finish-v6\n' "\$IOS_IAP_TEST_BUILD_COMMIT"
                ;;
            mismatch)
                printf '%040d\trefs/tags/dawnforge-deferred-finish-v6\n' 1
                printf '%040d\trefs/tags/dawnforge-deferred-finish-v6^{}\n' 2
                ;;
        esac
        exit 0
    fi
done
exec "$real_git" "\$@"
EOF
chmod +x "$mock_bin/git"
build_commit="$(git -C "$preflight_repo" rev-parse HEAD)"
run_preflight() {
    IOS_IAP_TEST_REMOTE_MODE="$1" IOS_IAP_TEST_BUILD_COMMIT="$build_commit" PATH="$mock_bin:$PATH" \
        "$preflight_repo/scripts/package_release.sh" --preflight
}

if run_preflight annotated > "$tmp_dir/preflight-clean.txt" 2>&1 \
    && grep -Fxq 'build_tag=dawnforge-deferred-finish-v6' "$tmp_dir/preflight-clean.txt" \
    && grep -Eq '^build_commit=[0-9a-f]{40}$' "$tmp_dir/preflight-clean.txt" \
    && grep -Fxq 'upstream_source_commit=f5b3747efb066c00ea3e206ff9b4f732ade5ed37' "$tmp_dir/preflight-clean.txt"; then
    pass 'clean tagged build source preflight'
else
    fail 'clean tagged build source preflight'
fi

if run_preflight noisy > "$tmp_dir/preflight-remote-noisy.txt" 2>&1; then
    pass 'remote tag preflight tolerates additional refs'
else
    fail 'remote tag preflight failed with additional refs'
fi

if run_preflight lightweight > "$tmp_dir/preflight-remote-lightweight.txt" 2>&1; then
    fail 'remote lightweight release tag preflight was accepted'
elif grep -Fxq 'remote release tag must be annotated' "$tmp_dir/preflight-remote-lightweight.txt"; then
    pass 'remote lightweight release tag preflight was rejected'
else
    fail 'remote lightweight release tag failed for the wrong reason'
fi

if run_preflight mismatch > "$tmp_dir/preflight-remote-mismatch.txt" 2>&1; then
    fail 'remote mismatched release tag preflight was accepted'
elif grep -Fxq 'remote release tag must peel to build commit' "$tmp_dir/preflight-remote-mismatch.txt"; then
    pass 'remote mismatched release tag preflight was rejected'
else
    fail 'remote mismatched release tag failed for the wrong reason'
fi

git -C "$preflight_repo" tag -d dawnforge-deferred-finish-v6 >/dev/null
git -C "$preflight_repo" tag dawnforge-deferred-finish-v6
if run_preflight annotated > "$tmp_dir/preflight-local-lightweight.txt" 2>&1; then
    fail 'local lightweight release tag preflight was accepted'
elif grep -Fxq 'local release tag must be annotated' "$tmp_dir/preflight-local-lightweight.txt"; then
    pass 'local lightweight release tag preflight was rejected'
else
    fail 'local lightweight release tag failed for the wrong reason'
fi

git -C "$preflight_repo" tag -d dawnforge-deferred-finish-v6 >/dev/null
git -C "$preflight_repo" tag -a dawnforge-deferred-finish-v6 -m fixture
printf 'dirty\n' > "$preflight_repo/dirty.txt"
if run_preflight annotated > "$tmp_dir/preflight-dirty.txt" 2>&1; then
    fail 'dirty build source preflight was accepted'
elif grep -Fxq 'build source must be clean' "$tmp_dir/preflight-dirty.txt"; then
    pass 'dirty build source preflight was rejected'
else
    fail 'dirty build source preflight failed for the wrong reason'
fi

if (( failures > 0 )); then
    printf '%s verifier regression test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all verifier regression tests passed\n'
