#!/bin/bash
# 고양이팀.app 을 프로젝트 폴더(이 스크립트의 한 단계 위)에 만든다.
#   bash desktop/build.sh            (버전은 VERSION=1.2.0 bash desktop/build.sh)
# 웹 파일과 팀.example.json 을 번들에 넣어, 앱만 따로 옮겨도 돈다 (arm64 + x86_64).
set -euo pipefail
VERSION="${VERSION:-1.0.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
APP="$ROOT/고양이팀.app"

# 실행 중이면 먼저 정상 종료시키고 (최대 3초) 사라질 때까지 기다린다
osascript -e 'quit app id "local.catteam"' >/dev/null 2>&1 || true
for _ in $(seq 30); do
  pgrep -x CatTeam >/dev/null || break
  sleep 0.1
done
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos14.0" \
    "$HERE"/*.swift -o "$TMP/CatTeam-$arch" \
    -framework Cocoa -framework WebKit -framework SwiftUI -framework ServiceManagement
done
lipo -create "$TMP/CatTeam-arm64" "$TMP/CatTeam-x86_64" -o "$APP/Contents/MacOS/CatTeam"

# 웹 파일: desktop.html 과 그 페이지가 읽는 css·js
WEB="$APP/Contents/Resources/web"
mkdir -p "$WEB"
cp "$ROOT/desktop.html" "$ROOT/desktop.css" "$WEB/"
for js in $(sed -n 's/.*<script src="\([^"]*\)".*/\1/p' "$ROOT/desktop.html"); do
  cp "$ROOT/$js" "$WEB/"
done
cp "$ROOT/팀.example.json" "$APP/Contents/Resources/"
# 메뉴의 "Claude Code 에 고양이 추가 명령 설치" 가 ~/.claude/skills 로 복사하는 스킬
mkdir -p "$APP/Contents/Resources/skills/cat-add"
cp "$ROOT/skills/cat-add/SKILL.md" "$APP/Contents/Resources/skills/cat-add/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>고양이팀</string>
  <key>CFBundleDisplayName</key><string>고양이 팀</string>
  <key>CFBundleIdentifier</key><string>local.catteam</string>
  <key>CFBundleExecutable</key><string>CatTeam</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>고양이가 바탕화면의 파일과 폴더 옆에서 놀 수 있도록 아이콘 위치를 읽어요.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null                 # 리소스를 다 넣은 뒤에 서명한다
echo "만들었어요: $APP ($VERSION)"
