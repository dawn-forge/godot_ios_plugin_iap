#!/usr/bin/env bash
set -euo pipefail

archive="${1:?usage: verify_release.sh <release.zip> <manifest>}"
manifest="${2:?usage: verify_release.sh <release.zip> <manifest>}"
[[ -f "$archive" && -f "$manifest" ]] || { echo "archive and manifest are required" >&2; exit 1; }
manifest_value() {
    awk -F= -v key="$1" '$1 == key { print substr($0, length(key) + 2); exit }' "$manifest"
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
expected_zip_sha="$(awk -F= '/^zip_sha256=/{print $2; exit}' "$manifest")"
actual_zip_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
[[ "$expected_zip_sha" == "$actual_zip_sha" ]] || { echo "zip SHA-256 mismatch" >&2; exit 1; }
required_keys=(source_repo source_commit release_tag toolchain contract_version transaction_id verification_field finish_request auto_finish deferred_finish verified_transaction_ids unfinished_replay release_binary release_binary_sha256 debug_binary debug_binary_sha256 zip_sha256)
for key in "${required_keys[@]}"; do
    grep -Eq "^${key}=.+$" "$manifest" || { echo "manifest missing $key" >&2; exit 1; }
done
[[ "$(awk -F= '/^auto_finish=/{print $2; exit}' "$manifest")" == "false" ]] || { echo "auto_finish must be false" >&2; exit 1; }
tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT
unzip -q "$archive" -d "$tmp_dir"
descriptor="$tmp_dir/ios/plugins/ios-in-app-purchase.gdip"
contract="$tmp_dir/ios/plugins/ios-in-app-purchase.contract"
[[ -f "$descriptor" && -f "$contract" ]] || { echo "descriptor or contract missing" >&2; exit 1; }
grep -Fq 'name="IOSInAppPurchase"' "$descriptor" || { echo "unexpected descriptor" >&2; exit 1; }
grep -Fxq 'auto_finish=false' "$contract" || { echo "contract auto-finish marker missing" >&2; exit 1; }
grep -Fxq 'transaction_id=transactionID' "$contract" || { echo "contract transaction marker missing" >&2; exit 1; }
grep -Fxq 'finish_request=finishTransaction' "$contract" || { echo "contract finish marker missing" >&2; exit 1; }
release_binary="$(manifest_value release_binary)"
release_hash="$(manifest_value release_binary_sha256)"
debug_binary="$(manifest_value debug_binary)"
debug_hash="$(manifest_value debug_binary_sha256)"
for key in source_repo source_commit release_tag toolchain release_binary release_binary_sha256 debug_binary debug_binary_sha256; do
    value="$(manifest_value "$key")"
    grep -Fxq "$key=$value" "$contract" || { echo "contract $key mismatch" >&2; exit 1; }
done
release_path="$tmp_dir/ios/plugins/$release_binary"
debug_path="$tmp_dir/ios/plugins/$debug_binary"
[[ -d "$release_path" ]] || { echo "release framework missing" >&2; exit 1; }
[[ -d "$debug_path" ]] || { echo "debug framework missing" >&2; exit 1; }
[[ "$(hash_tree "$release_path")" == "$release_hash" ]] || { echo "release framework SHA-256 mismatch" >&2; exit 1; }
[[ "$(hash_tree "$debug_path")" == "$debug_hash" ]] || { echo "debug framework SHA-256 mismatch" >&2; exit 1; }
grep -Fxq "DawnForgeIAPArtifactSHA256=$release_hash" "$descriptor" || { echo "descriptor artifact SHA-256 mismatch" >&2; exit 1; }
grep -Fxq "binary_sha256=$release_hash" "$contract" || { echo "contract binary SHA-256 mismatch" >&2; exit 1; }
printf 'release verified: %s\n' "$archive"
