#!/bin/zsh
# Cut a release: build, ad-hoc sign, zip + DMG, Sparkle-sign, update the appcast, publish on GitHub.
#   scripts/release.sh 2.1.0 "One-line summary"
#   SPITBALL_NO_PUBLISH=1 scripts/release.sh 2.1.0   # build into dist/ only
set -e
cd "$(dirname "$0")/.."
VERSION="$1"; SUMMARY="${2:-Bug fixes and polish.}"
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh <version> [summary]"; exit 1; }
SPITBALL_NO_INSTALL=1 ./install.sh >/dev/null
OUT="$PWD/dist"; mkdir -p "$OUT"; rm -f "$OUT"/Spitball.zip "$OUT"/Spitball.dmg
R=$(mktemp -d); S=""
trap 'rm -rf "${R:?}" ${S:+"${S:?}"}' EXIT          # never leave old app copies lying around
cp -R .build/Spitball.app "$R/"
codesign --force --deep --sign - "$R/Spitball.app" >/dev/null 2>&1     # ad-hoc: no personal identity in public builds
(cd "$R" && ditto -c -k --keepParent Spitball.app "$OUT/Spitball.zip")

# DMG: the app, an Applications shortcut, a background with an arrow, and the window opens on mount.
S=$(mktemp -d); mkdir -p "$S/.background"
cp -R "$R/Spitball.app" "$S/"; ln -s /Applications "$S/Applications"
cp scripts/dmg-background.tiff "$S/.background/background.tiff"
RW="$R/rw.dmg"
hdiutil create -quiet -volname Spitball -srcfolder "$S" -fs HFS+ -format UDRW -size 200m "$RW"
MNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -o '/Volumes/.*$' | head -1)
osascript <<EOF
tell application "Finder"
  tell disk "Spitball"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 568}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Spitball.app" of container window to {170, 210}
    set position of item "Applications" of container window to {490, 210}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
bless --folder "$MNT" --openfolder "$MNT" 2>/dev/null || true      # pop the window open when mounted
sync; hdiutil detach -quiet "$MNT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT/Spitball.dmg"

SIG=$(.build/artifacts/sparkle/Sparkle/bin/sign_update --account spitball "$OUT/Spitball.zip")
BUILDNUM=$(defaults read "$PWD/Info.plist" CFBundleVersion)
URL="https://github.com/itsnicksimpson/spitball/releases/download/v$VERSION/Spitball.zip"
python3 - "$VERSION" "$BUILDNUM" "$URL" "$SIG" "$SUMMARY" <<'PY'
import sys, email.utils, os, re
v, b, url, sig, summary = sys.argv[1:]
item = f"""    <item>
      <title>Spitball {v}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{b}</sparkle:version>
      <sparkle:shortVersionString>{v}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>{summary}</p>]]></description>
      <enclosure url="{url}" {sig} type="application/octet-stream"/>
    </item>
"""
p = 'docs/appcast.xml'
head = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Spitball</title>
    <link>https://itsnicksimpson.github.io/spitball/appcast.xml</link>
    <description>Spitball updates</description>
"""
body = open(p).read().split('<!-- items -->')[1].split('<!-- /items -->')[0] if os.path.exists(p) else ''
body = ''.join(i for i in re.findall(r'    <item>.*?</item>\n', body, re.S) if f'/v{v}/' not in i)   # replace a re-cut version
open(p, 'w').write(head + '<!-- items -->\n' + item + body + '<!-- /items -->\n  </channel>\n</rss>\n')
PY
echo "✓ Built dist/Spitball.zip and dist/Spitball.dmg"
[ -n "$SPITBALL_NO_PUBLISH" ] && exit 0
gh release create "v$VERSION" "$OUT/Spitball.dmg" "$OUT/Spitball.zip" --title "Spitball $VERSION" --notes "$SUMMARY" -R itsnicksimpson/spitball
echo "✓ v$VERSION released. Commit docs/appcast.xml so installed apps see it."
