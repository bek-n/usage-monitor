#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/../.."
version=$(sed -nE 's/^version: *([^+]+).*/\1/p' pubspec.yaml)
app="build/macos/Build/Products/Release/Usage Monitor.app"
icons="macos/Runner/Assets.xcassets/AppIcon.appiconset"
out="dist/Usage Monitor $version.dmg"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

flutter build macos --release

tiffutil -cathidpicheck macos/packaging/dmg-background.png macos/packaging/dmg-background@2x.png \
  -out "$work/background.tiff" >/dev/null

iconset="$work/VolumeIcon.iconset"
mkdir "$iconset"
cp "$icons/app_icon_16.png" "$iconset/icon_16x16.png"
cp "$icons/app_icon_32.png" "$iconset/icon_16x16@2x.png"
cp "$icons/app_icon_32.png" "$iconset/icon_32x32.png"
cp "$icons/app_icon_64.png" "$iconset/icon_32x32@2x.png"
cp "$icons/app_icon_128.png" "$iconset/icon_128x128.png"
cp "$icons/app_icon_256.png" "$iconset/icon_128x128@2x.png"
cp "$icons/app_icon_256.png" "$iconset/icon_256x256.png"
cp "$icons/app_icon_512.png" "$iconset/icon_256x256@2x.png"
cp "$icons/app_icon_512.png" "$iconset/icon_512x512.png"
cp "$icons/app_icon_1024.png" "$iconset/icon_512x512@2x.png"
iconutil -c icns "$iconset" -o "$work/VolumeIcon.icns"

mkdir -p dist
"${DMGBUILD:-dmgbuild}" -s macos/packaging/dmg_settings.py \
  -D app="$app" -D background="$work/background.tiff" -D icon="$work/VolumeIcon.icns" \
  "Usage Monitor" "$out"

echo "$out"
