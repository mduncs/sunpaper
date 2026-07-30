#!/bin/bash

set -euo pipefail

usage() {
    cat <<'USAGE'
Create a signed, notarized Sunpaper DMG.

Requirements:
  - An Apple Developer Program membership
  - A "Developer ID Application" certificate installed in Keychain
  - A notarytool Keychain profile (see below)

Environment:
  TEAM_ID          Apple Developer Team ID
  NOTARY_PROFILE   notarytool Keychain profile name

One-time notary setup:
  xcrun notarytool store-credentials sunpaper-notary \
    --apple-id "you@example.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "APP_SPECIFIC_PASSWORD"

Release:
  TEAM_ID=YOUR_TEAM_ID NOTARY_PROFILE=sunpaper-notary scripts/release.sh

For packaging verification only (never upload this build):
  scripts/release.sh --unsigned
USAGE
}

unsigned=false
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
elif [[ "${1:-}" == "--unsigned" ]]; then
    unsigned=true
elif [[ $# -ne 0 ]]; then
    usage
    exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
project="$repo_root/Sunpaper.xcodeproj"
scheme="Sunpaper"
configuration="Release"
build_root="$repo_root/build/release"
archive_path="$build_root/Sunpaper.xcarchive"
export_path="$build_root/export"
staging_path="$build_root/dmg"
dist_path="$repo_root/dist"
export_options="$build_root/ExportOptions.plist"

version="$(
    xcodebuild -project "$project" -scheme "$scheme" \
        -configuration "$configuration" \
        -destination "generic/platform=macOS" \
        -showBuildSettings |
        awk '/MARKETING_VERSION =/ { print $3; exit }'
)"

if [[ -z "$version" ]]; then
    echo "Could not read MARKETING_VERSION from the Xcode project." >&2
    exit 1
fi

if [[ "$unsigned" == false ]]; then
    : "${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID.}"
    : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile.}"

    if ! security find-identity -v -p codesigning |
        grep -q '"Developer ID Application:'; then
        echo "No Developer ID Application certificate is installed." >&2
        echo "Create one at developer.apple.com, install it, and try again." >&2
        exit 1
    fi
fi

rm -rf "$build_root"
mkdir -p "$build_root" "$dist_path"

archive_arguments=(
    -project "$project"
    -scheme "$scheme"
    -configuration "$configuration"
    -destination "generic/platform=macOS"
    -archivePath "$archive_path"
    archive
)

if [[ "$unsigned" == true ]]; then
    xcodebuild "${archive_arguments[@]}" CODE_SIGNING_ALLOWED=NO
    mkdir -p "$export_path"
    cp -R "$archive_path/Products/Applications/Sunpaper.app" "$export_path/"
    artifact_name="Sunpaper-$version-unsigned"
else
    xcodebuild "${archive_arguments[@]}" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Automatic \
        -allowProvisioningUpdates

    cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
</dict>
</plist>
PLIST

    xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$export_options" \
        -allowProvisioningUpdates
    artifact_name="Sunpaper-$version"
fi

app_path="$export_path/Sunpaper.app"
if [[ ! -d "$app_path" ]]; then
    echo "The exported app was not found at $app_path." >&2
    exit 1
fi

rm -rf "$staging_path"
mkdir -p "$staging_path"
ditto "$app_path" "$staging_path/Sunpaper.app"
ln -s /Applications "$staging_path/Applications"

dmg_path="$dist_path/$artifact_name.dmg"
rm -f "$dmg_path"
hdiutil create \
    -volname "Sunpaper" \
    -srcfolder "$staging_path" \
    -ov \
    -format UDZO \
    "$dmg_path"

if [[ "$unsigned" == false ]]; then
    codesign --force --sign "Developer ID Application" \
        --timestamp "$dmg_path"
    xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
    spctl --assess --type open --context context:primary-signature -vv "$dmg_path"
fi

(
    cd "$dist_path"
    shasum -a 256 "$(basename "$dmg_path")" |
        tee "$(basename "$dmg_path").sha256"
)
echo
echo "Created $dmg_path"
if [[ "$unsigned" == true ]]; then
    echo "This unsigned DMG is for local packaging verification only."
else
    echo "Upload the DMG and its SHA-256 file to the matching GitHub release."
fi
