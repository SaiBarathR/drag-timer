#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

swift build -c release --product DragTimer
bin_path="$(swift build -c release --show-bin-path)"
app_path="$root/dist/Drag Timer.app"

# Recreate the bundle so a stale signature or resource from a previous build
# cannot be carried into the release.
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources"
cp "$bin_path/DragTimer" "$app_path/Contents/MacOS/DragTimer"
cp "$root/Packaging/Info.plist" "$app_path/Contents/Info.plist"

# Apple Silicon refuses to launch completely unsigned arm64 binaries, so apply
# an ad-hoc signature to the assembled bundle. Releases are still not signed
# with a Developer ID or notarized.
codesign --force --sign - "$app_path"

echo "Built ad-hoc signed app at $app_path"
