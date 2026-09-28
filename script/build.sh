#!/usr/bin/env bash
# Meruto の共通ビルド経路。
#   ./script/build.sh            … XcodeGen でプロジェクトを作り、シミュレータ向けにビルド
#   ./script/build.sh --device   … 実機 (generic iOS) 向けに署名なしでコンパイルだけ確認
#   ./script/build.sh --test     … MerutoKit のロジックテスト (swift test)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
MODE="${1:-simulator}"

if [[ "$MODE" == "--test" ]]; then
  swift test --package-path "$ROOT_DIR/Packages/MerutoKit"
  exit 0
fi

xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR" --quiet

if [[ "$MODE" == "--device" ]]; then
  xcodebuild -project "$ROOT_DIR/Meruto.xcodeproj" -scheme Meruto -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO build
  exit 0
fi

xcodebuild -project "$ROOT_DIR/Meruto.xcodeproj" -scheme Meruto -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED_DATA" build
