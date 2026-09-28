#!/usr/bin/env bash
# TestFlight へビルドをアップロードする (docs/RELEASE.md)。
#
#   ./script/upload-testflight.sh            # ビルド番号を +1 してアップロード
#   ./script/upload-testflight.sh --build 7  # 番号を指定
#
# App Store Connect の内部グループ "Internal" は自動配信なので、処理が終われば
# TestFlight アプリに届く。Info.plist の ITSAppUsesNonExemptEncryption=false により
# 暗号化の手動回答は不要。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_OPTIONS="$ROOT_DIR/script/ExportOptions-upload.plist"
cd "$ROOT_DIR"

if ! grep -qE "^DEVELOPMENT_TEAM *= *[A-Z0-9]{10}" Config/Local.xcconfig 2>/dev/null; then
  echo "Config/Local.xcconfig に DEVELOPMENT_TEAM がありません (Config/Local.example.xcconfig を参照)" >&2
  exit 1
fi

current=$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"([0-9]+)".*/\1/p' project.yml | head -1)
[[ -n "$current" ]] || { echo "project.yml の CURRENT_PROJECT_VERSION を読めませんでした" >&2; exit 1; }
build=$((current + 1))
if [[ "${1:-}" == "--build" && -n "${2:-}" ]]; then build="$2"; fi

# テストが落ちているビルドは上げない。
swift test --package-path Packages/MerutoKit --quiet

sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*\")[0-9]+(\")/\1$build\2/" project.yml
echo "==> Build $build をアーカイブします"
xcodegen generate --spec project.yml --quiet

stamp=$(date +%Y%m%d-%H%M%S)
archive="$ROOT_DIR/.build/archives/Meruto-$build-$stamp.xcarchive"
export_dir="$ROOT_DIR/.build/archives/Meruto-$build-$stamp-export"
xcodebuild -project Meruto.xcodeproj -scheme Meruto -configuration Release \
  -destination generic/platform=iOS -archivePath "$archive" archive -allowProvisioningUpdates

app="$archive/Products/Applications/Meruto.app"
encryption=$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$app/Info.plist" 2>/dev/null || echo missing)
if [[ "$encryption" != "false" ]]; then
  echo "ITSAppUsesNonExemptEncryption が false ではありません ($encryption)" >&2
  exit 1
fi
if sips -g hasAlpha "$ROOT_DIR/Meruto/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" | grep -q "hasAlpha: yes"; then
  echo "アプリアイコンにアルファチャンネルがあります (App Store は受け付けない)" >&2
  exit 1
fi

xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$export_dir" -allowProvisioningUpdates

echo "==> Build $build を TestFlight へアップロードしました"
echo "    project.yml のビルド番号を $build に更新済みです (コミットしてください)"
