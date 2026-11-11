#!/bin/bash
# Builds a universal, Developer ID-signed, notarized and stapled build/Quitter-<version>.zip.
# One-time setup: a "Developer ID Application" certificate in the keychain, and
#   xcrun notarytool store-credentials quitter-notary --apple-id <id> --team-id <team>
set -euo pipefail
cd "$(dirname "$0")"

PROFILE=${NOTARY_PROFILE:-quitter-notary}
IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
[ -n "$IDENTITY" ] || { echo "No 'Developer ID Application' certificate in the keychain." >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Quitter"

APP=build/Quitter.app
ZIP=build/Quitter-$VERSION.zip
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --options runtime --timestamp --entitlements Quitter.entitlements --sign "$IDENTITY" "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP" # re-zip so the download carries the stapled ticket
spctl --assess --type execute --verbose "$APP"
echo "Ready: $ZIP"
