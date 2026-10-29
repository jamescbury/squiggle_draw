#!/bin/sh
set -eu
cd "$(dirname "$0")"
. ./version.env
mkdir -p .build/clang-cache dist
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" swift build -c release --disable-sandbox --product SquiggleDraw
stage=$(mktemp -d "$PWD/dist/.package.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
bundle="$stage/Squiggle Draw.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp .build/release/SquiggleDraw "$bundle/Contents/MacOS/SquiggleDraw"
cp -R .build/release/SquiggleDraw_SquiggleDraw.bundle "$bundle/Contents/Resources/"
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SquiggleDraw</string>
<key>CFBundleIdentifier</key><string>art.squiggle.draw</string>
<key>CFBundleName</key><string>Squiggle Draw</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSLocalNetworkUsageDescription</key><string>Share selected sketches with Squiggle on your BOOX over your local Wi-Fi network.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$bundle" "$stage/Squiggle-Draw-Mac.zip"
if [ -d 'dist/Squiggle Draw.app' ]; then mv 'dist/Squiggle Draw.app' "$stage/previous.app"; fi
mv "$bundle" dist/
mv "$stage/Squiggle-Draw-Mac.zip" dist/
printf 'Built Squiggle Draw %s (build %s)\n' "$VERSION" "$BUILD_NUMBER"
