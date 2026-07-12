#!/usr/bin/env bash
set -euo pipefail

archive="${1:?usage: verify_release.sh <release.zip> <manifest>}"
manifest="${2:?usage: verify_release.sh <release.zip> <manifest>}"
[[ -f "$archive" && -f "$manifest" ]] || { echo "archive and manifest are required" >&2; exit 1; }

field_value() {
    local file="$1" key="$2"
    awk -F= -v key="$key" '
        $1 == key {
            if (found++) {
                exit 2
            }
            value = substr($0, length(key) + 2)
        }
        END {
            if (found != 1 || value == "") {
                exit 1
            }
            print value
        }
    ' "$file"
}

manifest_value() {
    field_value "$manifest" "$1"
}

contract_value() {
    field_value "$contract" "$1"
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

require_manifest_value() {
    local key="$1"
    if ! manifest_field="$(manifest_value "$key")"; then
        echo "manifest missing or duplicate $key" >&2
        exit 1
    fi
}

require_contract_value() {
    local key="$1"
    if ! contract_field="$(contract_value "$key")"; then
        echo "contract missing or duplicate $key" >&2
        exit 1
    fi
}

expected_zip_sha="$(manifest_value zip_sha256)" || { echo "manifest missing or duplicate zip_sha256" >&2; exit 1; }
actual_zip_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$expected_zip_sha" == "$actual_zip_sha" ]] || { echo "zip SHA-256 mismatch" >&2; exit 1; }

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT
unzip -q "$archive" -d "$tmp_dir"
plugins_dir="$tmp_dir/ios/plugins"
descriptor="$plugins_dir/ios-in-app-purchase.gdip"
contract="$plugins_dir/ios-in-app-purchase.contract"
[[ -f "$descriptor" && -f "$contract" ]] || { echo "descriptor or contract missing" >&2; exit 1; }

shared_keys=(
    source_repo source_commit release_tag
    upstream_source_repo upstream_source_commit
    build_repo build_commit build_tag
    toolchain contract_version transaction_id verification_field finish_request
    auto_finish deferred_finish verified_transaction_ids unfinished_replay
    release_binary release_binary_sha256 debug_binary debug_binary_sha256
)
for key in "${shared_keys[@]}"; do
    require_manifest_value "$key"
    manifest_value_for_key="$manifest_field"
    require_contract_value "$key"
    [[ "$manifest_value_for_key" == "$contract_field" ]] || { echo "contract $key mismatch" >&2; exit 1; }
done

for key in binary_sha256 zip_sha256; do
    require_contract_value "$key"
done
[[ "$contract_field" == DETACHED ]] || { echo "contract zip SHA-256 must be detached" >&2; exit 1; }

expect_manifest_value() {
    local key="$1" expected="$2"
    require_manifest_value "$key"
    [[ "$manifest_field" == "$expected" ]] || { echo "manifest $key must be $expected" >&2; exit 1; }
}

expect_manifest_value contract_version 1
expect_manifest_value transaction_id transactionID
expect_manifest_value verification_field verified
expect_manifest_value finish_request finishTransaction
expect_manifest_value auto_finish false
expect_manifest_value deferred_finish true
expect_manifest_value verified_transaction_ids true
expect_manifest_value unfinished_replay true

legacy_source_repo="$(manifest_value source_repo)"
legacy_source_commit="$(manifest_value source_commit)"
release_tag="$(manifest_value release_tag)"
upstream_source_repo="$(manifest_value upstream_source_repo)"
upstream_source_commit="$(manifest_value upstream_source_commit)"
build_repo="$(manifest_value build_repo)"
build_commit="$(manifest_value build_commit)"
build_tag="$(manifest_value build_tag)"
[[ "$legacy_source_repo" == "$build_repo" ]] || { echo "legacy source_repo must identify the build repository" >&2; exit 1; }
[[ "$legacy_source_commit" == "$upstream_source_commit" ]] || { echo "legacy source_commit must identify the upstream pin" >&2; exit 1; }
[[ "$release_tag" == "$build_tag" ]] || { echo "release tag must match build tag" >&2; exit 1; }
[[ "$build_commit" =~ ^[0-9a-f]{40}$ ]] || { echo "build commit must be a full SHA-1" >&2; exit 1; }

for descriptor_line in \
    'name="IOSInAppPurchase"' \
    'binary="ios-in-app-purchase.xcframework"' \
    'initialization="ios_in_app_purchase_init"' \
    'deinitialization="ios_in_app_purchase_deinit"'; do
    grep -Fxq "$descriptor_line" "$descriptor" || { echo "unexpected descriptor layout" >&2; exit 1; }
done

grep -Fxq "DawnForgeIAPUpstreamSourceRepo=$upstream_source_repo" "$descriptor" || { echo "descriptor upstream repository mismatch" >&2; exit 1; }
grep -Fxq "DawnForgeIAPUpstreamSourceCommit=$upstream_source_commit" "$descriptor" || { echo "descriptor upstream commit mismatch" >&2; exit 1; }
grep -Fxq "DawnForgeIAPSourceCommit=$upstream_source_commit" "$descriptor" || { echo "descriptor legacy upstream commit mismatch" >&2; exit 1; }
grep -Fxq "DawnForgeIAPBuildRepo=$build_repo" "$descriptor" || { echo "descriptor build repository mismatch" >&2; exit 1; }
grep -Fxq "DawnForgeIAPBuildCommit=$build_commit" "$descriptor" || { echo "descriptor build commit mismatch" >&2; exit 1; }
grep -Fxq "DawnForgeIAPBuildTag=$build_tag" "$descriptor" || { echo "descriptor build tag mismatch" >&2; exit 1; }

descriptor_binary="ios-in-app-purchase.xcframework"
descriptor_stem="${descriptor_binary%.xcframework}"
release_binary="$(manifest_value release_binary)"
debug_binary="$(manifest_value debug_binary)"
release_hash="$(manifest_value release_binary_sha256)"
debug_hash="$(manifest_value debug_binary_sha256)"
[[ "$release_binary" == "$descriptor_stem.release.xcframework" ]] || { echo "release binary must be descriptor-derived" >&2; exit 1; }
[[ "$debug_binary" == "$descriptor_stem.debug.xcframework" ]] || { echo "debug binary must be descriptor-derived" >&2; exit 1; }
release_path="$plugins_dir/$release_binary"
debug_path="$plugins_dir/$debug_binary"
[[ -d "$release_path" ]] || { echo "release framework missing" >&2; exit 1; }
[[ -d "$debug_path" ]] || { echo "debug framework missing" >&2; exit 1; }
[[ "$(hash_tree "$release_path")" == "$release_hash" ]] || { echo "release framework SHA-256 mismatch" >&2; exit 1; }
[[ "$(hash_tree "$debug_path")" == "$debug_hash" ]] || { echo "debug framework SHA-256 mismatch" >&2; exit 1; }
grep -Fxq "DawnForgeIAPArtifactSHA256=$release_hash" "$descriptor" || { echo "descriptor artifact SHA-256 mismatch" >&2; exit 1; }
[[ "$(contract_value binary_sha256)" == "$release_hash" ]] || { echo "contract binary SHA-256 mismatch" >&2; exit 1; }
printf 'release verified: %s\n' "$archive"
