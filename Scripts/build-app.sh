#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

swift build -c release --product DragTimer
bin_path="$(swift build -c release --show-bin-path)"
app_path="$root/dist/Drag Timer.app"

# Recreate the bundle so a previous ad-hoc signature or stale resource cannot
# be carried into an unsigned public release.
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources"
cp "$bin_path/DragTimer" "$app_path/Contents/MacOS/DragTimer"
cp "$root/Packaging/Info.plist" "$app_path/Contents/Info.plist"

# Releases are intentionally unsigned. Swift toolchains can sometimes produce
# a signed executable, so remove that signature before packaging the bundle.
if command -v codesign >/dev/null 2>&1 && codesign --display --verbose=0 "$app_path/Contents/MacOS/DragTimer" >/dev/null 2>&1; then
    codesign --remove-signature "$app_path/Contents/MacOS/DragTimer"
fi

echo "Built unsigned app at $app_path"
