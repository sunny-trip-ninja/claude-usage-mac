#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
build_dir="$repo_dir/.build/$configuration"
app_dir="$repo_dir/dist/Claude Usage.app"
version="$(tr -d '[:space:]' < "$repo_dir/VERSION")"
app_sign_identity="${APP_SIGN_IDENTITY:--}"

if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "VERSION must use semantic versioning, for example 0.0.1" >&2
    exit 1
fi

cd "$repo_dir"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/claude-usage-clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/claude-usage-swift-cache}"
swift build -c "$configuration" --disable-sandbox

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$build_dir/ClaudeUsage" "$app_dir/Contents/MacOS/ClaudeUsage"
sed "s/@VERSION@/$version/g" "$repo_dir/scripts/Info.plist.template" > "$app_dir/Contents/Info.plist"

if [[ "$app_sign_identity" == "-" ]]; then
    codesign --force --deep --sign - "$app_dir"
else
    codesign --force --deep --options runtime --timestamp --sign "$app_sign_identity" "$app_dir"
fi

echo "$app_dir"
