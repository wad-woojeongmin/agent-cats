#!/bin/bash
# 고양이팀.app 을 프로젝트 폴더(이 스크립트의 한 단계 위)에 만든다.
#   bash desktop/build.sh
set -euo pipefail
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
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  "$HERE"/*.swift -o "$APP/Contents/MacOS/CatTeam" \
  -framework Cocoa -framework WebKit -framework SwiftUI -framework ServiceManagement

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
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>고양이가 바탕화면의 파일과 폴더 옆에서 놀 수 있도록 아이콘 위치를 읽어요.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "만들었어요: $APP"
