#!/bin/zsh
# Spitball installer: builds from source, signs, drops it in ~/Applications, launches it.
set -e
cd "$(dirname "$0")"

# The main Applications folder (what Finder, Launchpad and Spotlight show).
if [ -w /Applications ]; then APP="/Applications/Spitball.app"; else APP="$HOME/Applications/Spitball.app"; fi
BUILD=".build/Spitball.app"

echo "→ Building (first build takes a few minutes)…"
swift build -c release --product Spitball 2>&1 | grep -E "error|warning: unre|Compiling Spitball|Build complete" || true
BIN=$(swift build -c release --show-bin-path)/Spitball
[ -x "$BIN" ] || { echo "Build failed"; exit 1; }

rm -rf "$BUILD" && mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources"
cp "$BIN" "$BUILD/Contents/MacOS/Spitball"
cp Info.plist "$BUILD/Contents/Info.plist"
# App icon: the Icon Composer file (Liquid Glass, drawn full-size by macOS 26+), compiled by
# actool into Assets.car, with the classic .icns as a fallback for older tools.
cp Resources/AppIcon.icns "$BUILD/Contents/Resources/AppIcon.icns"
ICONTMP=$(mktemp -d)
if xcrun actool Resources/AppIcon.icon --compile "$ICONTMP" --platform macosx --minimum-deployment-target 26.0 \
     --app-icon AppIcon --output-partial-info-plist "$ICONTMP/partial.plist" >/dev/null 2>&1 && [ -f "$ICONTMP/Assets.car" ]; then
  cp "$ICONTMP/Assets.car" "$BUILD/Contents/Resources/Assets.car"
fi
rm -rf "${ICONTMP:?}"
cp -R Resources/Fonts "$BUILD/Contents/Resources/Fonts"
cp -R Resources/Sounds "$BUILD/Contents/Resources/Sounds"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$BUILD/Contents/Resources/"
# Sparkle (auto-updates) goes in Contents/Frameworks.
mkdir -p "$BUILD/Contents/Frameworks"
cp -R "$(dirname "$BIN")/Sparkle.framework" "$BUILD/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BUILD/Contents/MacOS/Spitball" 2>/dev/null || true
# Copy any SwiftPM resource bundles next to the binary.
for b in $(dirname "$BIN")/*.bundle(N); do cp -R "$b" "$BUILD/Contents/Resources/"; done

# Sign with your Apple Development identity if you have one, so macOS keeps
# Microphone + Accessibility permissions across rebuilds. Otherwise ad-hoc.
ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')
codesign --force --deep --sign "${ID:--}" "$BUILD" >/dev/null 2>&1

[ -n "$SPITBALL_NO_INSTALL" ] && { echo "built $BUILD"; exit 0; }
pkill -x Spitball 2>/dev/null && sleep 1 || true
mkdir -p "$(dirname "$APP")"
rm -rf "$APP" && cp -R "$BUILD" "$APP"
open "$APP"
echo "✓ Spitball is running. Look for the waveform in your menu bar."
echo "  Double-tap ⌘ to talk, tap ⌘ once to finish."
