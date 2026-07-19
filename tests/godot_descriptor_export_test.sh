#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
v7_release_url="https://github.com/dawn-forge/godot_ios_plugin_iap/releases/download/dawnforge-deferred-finish-v7/ios-in-app-purchase.zip"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ios-iap-godot-export.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

command -v "$godot_bin" >/dev/null || fail "Godot executable not found: $godot_bin"
"$godot_bin" --version | grep -Eq '^4\.7\.' || fail 'Godot 4.7 is required'
ios_template="$HOME/Library/Application Support/Godot/export_templates/4.7.stable/ios.zip"
[[ -f "$ios_template" ]] || fail "Godot iOS 4.7 export template not found: $ios_template"

project_dir="$tmp_dir/project"
release_zip="$tmp_dir/ios-in-app-purchase-v7.zip"
mkdir -p "$project_dir"
curl -fsSL "$v7_release_url" -o "$release_zip"
unzip -q "$release_zip" -d "$project_dir"
cp "$repo_root/godot_ios_plugin_iap/ios-in-app-purchase.gdip" "$project_dir/ios/plugins/ios-in-app-purchase.gdip"

cat > "$project_dir/project.godot" <<'EOF'
; Engine configuration file.
; It is best edited using the editor and not directly,
; since the parameters that go here are not all obvious.
;
; Format:
;   [section] ; section goes between []
;   param=value ; assign values to parameters

config_version=5

[application]

config/name="IAP Descriptor Export Regression"
config/icon="res://icon.png"
run/main_scene="res://main.tscn"

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
EOF

cat > "$project_dir/main.tscn" <<'EOF'
[gd_scene format=3]

[node name="Main" type="Node"]
EOF

unzip -p "$ios_template" godot_apple_embedded/Images.xcassets/SplashImage.imageset/splash@2x.png > "$project_dir/icon.png"

cat > "$project_dir/export_presets.cfg" <<'EOF'
[preset.0]

name="iOS Project Only"
platform="iOS"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="build/ios/fixture.ipa"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2
script_encryption_key=""

[preset.0.options]

custom_template/debug=""
custom_template/release="[IOS_TEMPLATE_PATH]"
architectures/arm64=true
application/export_method_debug=1
application/export_method_release=0
application/app_store_team_id="8FWLVX7D6X"
application/code_sign_identity_debug="Apple Development"
application/provisioning_profile_specifier_debug=""
application/code_sign_identity_release="Apple Distribution"
application/provisioning_profile_specifier_release=""
application/bundle_identifier="org.dawnforge.iapdescriptorregression"
application/short_version="1.0"
application/version="1"
application/additional_plist_content=""
application/export_project_only=true
plugins/IOSInAppPurchase=true
plugins/AdMob=false
plugins/UserMessagingPlatform=false
plugins_plist/GADApplicationIdentifier=""
privacy/tracking_enabled=false
privacy/tracking_domains=PackedStringArray()
EOF

perl -0pi -e "s#\[IOS_TEMPLATE_PATH\]#$ios_template#g" "$project_dir/export_presets.cfg"

export_root="$tmp_dir/export"
if ! "$godot_bin" --headless --path "$project_dir" --import --quit > "$tmp_dir/import.log" 2>&1; then
    sed -n '1,220p' "$tmp_dir/import.log" >&2
    fail 'Godot must import the project before the project-only export'
fi
if ! "$godot_bin" --headless --verbose --path "$project_dir" --export-release "iOS Project Only" "$export_root" > "$tmp_dir/export.log" 2>&1; then
    sed -n '1,220p' "$tmp_dir/export.log" >&2
    fail 'Godot project-only iOS export must parse the descriptor'
fi

info_plist="$(find "$export_root" -type f -name '*-Info.plist' -print -quit)"
[[ -n "$info_plist" ]] || fail 'project-only export must produce an app Info.plist'

assert_plist_value() {
    local key="$1" expected="$2" actual
    actual="$(plutil -extract "$key" raw -o - "$info_plist" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] || fail "$key must equal $expected in exported Info.plist; got ${actual:-<missing>}"
}

assert_plist_value DawnForgeIAPContractVersion 1
assert_plist_value DawnForgeIAPSourceCommit f5b3747efb066c00ea3e206ff9b4f732ade5ed37
assert_plist_value DawnForgeIAPArtifactSHA256 GENERATED_AFTER_BUILD

printf 'PASS: Godot 4.7 project-only export parses descriptor and writes DawnForge IAP plist markers\n'
