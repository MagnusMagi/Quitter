#!/bin/bash
# Builds Quitter.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Quitter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/AppIcon.icns "$APP/Contents/Resources/"
cp .build/release/Quitter "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/Quitter.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/Quitter.app"
