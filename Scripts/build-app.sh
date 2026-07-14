#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

app_path="$root/dist/Drag Timer.app"
executable="$app_path/Contents/MacOS/DragTimer"
build_root="$root/.build/universal-release"
architectures=(arm64 x86_64)
declare -a slices

rm -rf "$app_path" "$build_root"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

for architecture in "${architectures[@]}"; do
    scratch_path="$build_root/$architecture"
    triple="${architecture}-apple-macosx14.0"
    swift build \
        -c release \
        --product DragTimer \
        --triple "$triple" \
        --scratch-path "$scratch_path"
    bin_path="$(swift build \
        -c release \
        --product DragTimer \
        --triple "$triple" \
        --scratch-path "$scratch_path" \
        --show-bin-path)"
    slices+=("$bin_path/DragTimer")
done

lipo -create "${slices[@]}" -output "$executable"
cp "$root/Packaging/Info.plist" "$app_path/Contents/Info.plist"
cp "$root/Packaging/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"

actual_architectures="$(lipo -archs "$executable" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
expected_architectures="arm64 x86_64"
if [[ "$actual_architectures" != "$expected_architectures" ]]; then
    echo "Expected exactly [$expected_architectures], got [$actual_architectures]" >&2
    exit 1
fi

minimum_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_path/Contents/Info.plist")"
if [[ "$minimum_system" != "14.0" ]]; then
    echo "LSMinimumSystemVersion must match Package.swift macOS 14 support, got $minimum_system" >&2
    exit 1
fi

# Apply an ad-hoc signature only after the executable and resources are final.
# Releases are not Developer ID signed or notarized.
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"

echo "Built universal ad-hoc signed app at $app_path ($actual_architectures)"
