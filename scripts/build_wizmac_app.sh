#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build_wizmac_app.sh [--output-dir PATH] [--version VALUE] [--codesign-identity IDENTITY] [--no-zip]

Builds a local Wizmac.app bundle from SwiftPM release products and, by default,
creates a Wizmac.zip archive next to it for Homebrew cask distribution.
EOF
}

output_dir=".build/package"
version="0.0.0"
create_zip=1
codesign_identity="-"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      output_dir="${2:?missing value for --output-dir}"
      shift 2
      ;;
    --version)
      version="${2:?missing value for --version}"
      shift 2
      ;;
    --codesign-identity)
      codesign_identity="${2:?missing value for --codesign-identity}"
      shift 2
      ;;
    --no-zip)
      create_zip=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/.build/release"
if [[ "$output_dir" = /* ]]; then
  output_root="$output_dir"
else
  output_root="$repo_root/$output_dir"
fi
staging_root="$(mktemp -d "${TMPDIR:-/tmp}/wizmac-package.XXXXXX")"
trap 'rm -rf "$staging_root"' EXIT

staging_app_dir="$staging_root/Wizmac.app"
contents_dir="$staging_app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
cli_dir="$resources_dir/bin"
info_plist="$contents_dir/Info.plist"
output_app_dir="$output_root/Wizmac.app"
zip_path="$output_root/Wizmac.zip"

mkdir -p "$output_root"

for product in WizmacMenuBarApp WizmacService wizmac; do
  (cd "$repo_root" && swift build --configuration release --product "$product")
done

rm -rf "$output_app_dir" "$zip_path" "$staging_app_dir"
mkdir -p "$macos_dir" "$resources_dir" "$cli_dir"

cat >"$info_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Wizmac</string>
  <key>CFBundleExecutable</key>
  <string>Wizmac</string>
  <key>CFBundleIdentifier</key>
  <string>com.tanmayg1502.wizmac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Wizmac</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${version}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

install -m 755 "$build_dir/WizmacMenuBarApp" "$macos_dir/Wizmac"
install -m 755 "$build_dir/WizmacService" "$macos_dir/WizmacService"
install -m 755 "$build_dir/wizmac" "$cli_dir/wizmac"
xattr -cr "$staging_app_dir"

if command -v codesign >/dev/null 2>&1; then
  sign_args=(--force --sign "$codesign_identity")
  if [[ "$codesign_identity" = "-" ]]; then
    sign_args+=(--timestamp=none)
  else
    sign_args+=(--options runtime --timestamp)
  fi

  codesign "${sign_args[@]}" "$macos_dir/Wizmac"
  codesign "${sign_args[@]}" "$macos_dir/WizmacService"
  codesign "${sign_args[@]}" "$cli_dir/wizmac"
  codesign "${sign_args[@]}" "$staging_app_dir"
  codesign --verify --deep --strict "$staging_app_dir"
fi

ditto "$staging_app_dir" "$output_app_dir"

if [[ "$create_zip" -eq 1 ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$staging_app_dir" "$zip_path"
fi

printf 'Built %s\n' "$output_app_dir"
printf 'Embedded CLI at %s\n' "$output_app_dir/Contents/Resources/bin/wizmac"
if [[ "$create_zip" -eq 1 ]]; then
  printf 'Built %s\n' "$zip_path"
fi
