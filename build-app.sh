#!/bin/bash
# Builds a universal (Apple silicon + Intel) Twinee.app and packages it for download.
#
#   ./build-app.sh                      ad-hoc signed app, DMG and ZIP in dist/
#   VERSION=1.2.0 ./build-app.sh        set the version shown in Finder and the About box
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./build-app.sh
#   NOTARY_PROFILE=twinee ./build-app.sh   also notarize and staple (needs SIGN_IDENTITY)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${VERSION:-4.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Twinee.app"
DMG_PATH="$DIST_DIR/Twinee-$VERSION.dmg"
ZIP_PATH="$DIST_DIR/Twinee-$VERSION.zip"

if [ ! -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    echo "Generating the app icon..."
    (cd "$ROOT_DIR" && swift scripts/make-icon.swift)
fi

echo "Building universal binary..."
swift build --package-path "$ROOT_DIR" --configuration release --arch arm64 --arch x86_64
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --configuration release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Twinee" "$APP_DIR/Contents/MacOS/Twinee"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE.txt"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Twinee</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.twinee.knowledge</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Twinee</string>
    <key>CFBundleDisplayName</key>
    <string>Twinee</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © $(date +%Y) Debadarshana Parida.</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "Signing with: $([ "$SIGN_IDENTITY" = "-" ] && echo "ad-hoc signature" || echo "$SIGN_IDENTITY")"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

echo "Creating disk image..."
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_DIR" "$STAGE/Twinee.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG_PATH" "$ZIP_PATH"
hdiutil create -volname "Twinee" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    if [ "$SIGN_IDENTITY" = "-" ]; then
        echo "NOTARY_PROFILE needs SIGN_IDENTITY set to a Developer ID certificate." >&2
        exit 1
    fi
    echo "Notarizing..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler staple "$APP_DIR"
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
fi

echo
echo "Architectures: $(lipo -archs "$APP_DIR/Contents/MacOS/Twinee")"
echo "App: $APP_DIR"
echo "DMG: $DMG_PATH"
echo "ZIP: $ZIP_PATH"
shasum -a 256 "$DMG_PATH" "$ZIP_PATH"
