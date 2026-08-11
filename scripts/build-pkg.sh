#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
version="$(tr -d '[:space:]' < "$repo_dir/VERSION")"
app_dir="$repo_dir/dist/Claude Usage.app"
release_dir="$repo_dir/release"
pkg_path="$release_dir/ClaudeUsage-$version.pkg"
installer_sign_identity="${INSTALLER_SIGN_IDENTITY:-}"
staging_dir="$(mktemp -d /tmp/claude-usage-pkg.XXXXXX)"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "VERSION must use semantic versioning, for example 0.0.1" >&2
    exit 1
fi

cd "$repo_dir"
"$repo_dir/scripts/build-app.sh" release
mkdir -p "$release_dir"
mkdir -p "$staging_dir/Applications"
ditto --norsrc --noextattr --noqtn "$app_dir" "$staging_dir/Applications/Claude Usage.app"
xattr -cr "$staging_dir"

pkg_arguments=(
    --root "$staging_dir"
    --component-plist "$repo_dir/scripts/Component.plist"
    --install-location /
    --identifier com.local.ClaudeUsage.pkg
    --version "$version"
)

if [[ -n "$installer_sign_identity" ]]; then
    pkg_arguments+=(--sign "$installer_sign_identity")
fi

pkgbuild "${pkg_arguments[@]}" "$pkg_path"
pkgutil --check-signature "$pkg_path"

echo "$pkg_path"
