#!/bin/bash
# 배포용 zip 을 만든다: dist/CatTeam-<버전>.zip
#   bash desktop/release.sh 1.0.0
set -euo pipefail
VER="${1:?버전을 적어 주세요. 예: bash desktop/release.sh 1.0.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
ZIP="$ROOT/dist/CatTeam-$VER.zip"

VERSION="$VER" bash "$HERE/build.sh"
mkdir -p "$ROOT/dist"
rm -f "$ZIP"
(cd "$ROOT" && ditto -c -k --keepParent 고양이팀.app "$ZIP")
echo "만들었어요: $ZIP"
echo
echo "올리려면 (릴리스 노트를 notes.md 에 쓰고):"
echo "  gh release create v$VER \"$ZIP\" --title \"고양이 팀 $VER\" --notes-file notes.md"
