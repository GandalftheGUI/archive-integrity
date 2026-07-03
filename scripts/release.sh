#!/bin/bash
# Builds, signs, notarizes, and packages Archive Integrity into a DMG, then creates
# a tagged GitHub release with it attached.
#
# One-time prerequisites (already done on this machine as of this writing):
#   - A "Developer ID Application" certificate for team PT2MXQ2Q6D in the login keychain.
#   - notarytool credentials stored under the keychain profile "notarytool-profile"
#     (xcrun notarytool store-credentials "notarytool-profile" --apple-id ... --team-id ... --password ...)
#   - create-dmg installed (brew install create-dmg)
#
# Usage:
#   scripts/release.sh vX.Y.Z ["release notes here"]
#
# If notes are omitted, you'll be dropped into $EDITOR to write them (same as `gh release create`
# with no --notes), or you can edit the release afterward on GitHub.

set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh vX.Y.Z [\"release notes\"]}"
NOTES="${2:-}"

TEAM_ID="PT2MXQ2Q6D"
SIGNING_IDENTITY="Developer ID Application: Ian Remillard ($TEAM_ID)"
KEYCHAIN_PROFILE="notarytool-profile"
APP_NAME="Archive Integrity"
SCHEME="Archive Integrity"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Archive Integrity/Archive Integrity.xcodeproj"
ICONSET_SRC="$ROOT_DIR/Archive Integrity/Archive Integrity/Assets.xcassets/AppIcon.appiconset"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ARCHIVE_PATH="$WORK_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$WORK_DIR/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
APP_ZIP="$WORK_DIR/$APP_NAME.zip"
ICONSET_DIR="$WORK_DIR/icon.iconset"
ICNS_PATH="$WORK_DIR/AppIcon.icns"
DMG_PATH="$HOME/Downloads/$APP_NAME.dmg"

echo "==> Archiving ($SCHEME, Release)"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH"

echo "==> Exporting (Developer ID)"
EXPORT_OPTIONS="$WORK_DIR/exportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

echo "==> Notarizing the app"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$APP_PATH"

echo "==> Building DMG"
mkdir -p "$ICONSET_DIR"
for size in 16x16 16x16@2x 32x32 32x32@2x 128x128 128x128@2x 256x256 256x256@2x 512x512 512x512@2x; do
  cp "$ICONSET_SRC/icon_${size}.png" "$ICONSET_DIR/icon_${size}.png"
done
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

rm -f "$DMG_PATH"
create-dmg \
  --volname "$APP_NAME" \
  --volicon "$ICNS_PATH" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 150 190 \
  --app-drop-link 450 190 \
  --hide-extension "$APP_NAME.app" \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"

echo "==> Signing DMG"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

echo "==> Verifying"
spctl -a -vv --type open --context context:primary-signature "$DMG_PATH"

echo "==> Tagging and pushing $VERSION"
cd "$ROOT_DIR"
git tag "$VERSION"
git push origin "$VERSION"

echo "==> Creating GitHub release"
if [ -n "$NOTES" ]; then
  gh release create "$VERSION" --title "$APP_NAME $VERSION" --notes "$NOTES" "$DMG_PATH"
else
  gh release create "$VERSION" --title "$APP_NAME $VERSION" "$DMG_PATH"
fi

echo "==> Done: $DMG_PATH"
