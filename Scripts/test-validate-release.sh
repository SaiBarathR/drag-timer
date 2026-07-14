#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
validator="$root/Scripts/validate-release.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

mkdir -p "$temp_dir/releases"
cp "$root/Packaging/Info.plist" "$temp_dir/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$temp_dir/Info.plist")"
matching_tag="v$version"
touch "$temp_dir/releases/$matching_tag.md"

run_validator() {
    INFO_PLIST_PATH="$temp_dir/Info.plist" \
        RELEASE_NOTES_DIR="$temp_dir/releases" \
        "$validator" "$@"
}

expect_failure() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "Expected failure: $description" >&2
        exit 1
    fi
}

[[ "$(run_validator "$matching_tag")" == "$version" ]]
expect_failure "mismatched tag" run_validator v999.999.999
expect_failure "tag without v prefix" run_validator 1.3.1
expect_failure "tag without patch" run_validator v1.3
expect_failure "tag with prerelease suffix" run_validator v1.3.1-beta.1

rm "$temp_dir/releases/$matching_tag.md"
expect_failure "missing release notes" run_validator "$matching_tag"
touch "$temp_dir/releases/$matching_tag.md"

for invalid_version in 0 -1 abc 1.5; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $invalid_version" "$temp_dir/Info.plist"
    expect_failure "invalid bundle version $invalid_version" run_validator "$matching_tag"
done

echo "Release validator tests passed"
