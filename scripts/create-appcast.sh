#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
build_root="$project_root/build"
dist_root="$project_root/dist"
appcast_staging="$build_root/appcast-staging"
info_plist="$project_root/InputStatus/Resources/InputStatus-Info.plist"
version=$(plutil -extract CFBundleShortVersionString raw "$info_plist")
dmg_name="InputStatus-$version-universal.dmg"
dmg_file="$dist_root/$dmg_name"
appcast_file="$dist_root/appcast.xml"
release_notes=${1:-"$project_root/release-notes/v$version.md"}
sparkle_account="com.inputstatus.desktop"
download_prefix="https://github.com/Houtx/Project-Input-Status/releases/download/v$version/"

for required_tool in ditto plutil rg xmllint; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        print -u2 "Missing required tool: $required_tool"
        exit 1
    fi
done

if [[ ! -f "$dmg_file" ]]; then
    print -u2 "Missing release image: $dmg_file"
    exit 1
fi
if [[ "$appcast_staging" != "$project_root/build/appcast-staging" ]]; then
    print -u2 "Refusing to clean an unexpected appcast path: $appcast_staging"
    exit 1
fi

sparkle_root=$("$script_dir/bootstrap-sparkle.sh")
generate_appcast="$sparkle_root/bin/generate_appcast"
if [[ ! -x "$generate_appcast" ]]; then
    print -u2 "Missing Sparkle appcast generator: $generate_appcast"
    exit 1
fi

rm -rf "$appcast_staging"
mkdir -p "$appcast_staging" "$dist_root"
ditto "$dmg_file" "$appcast_staging/$dmg_name"

staged_notes="$appcast_staging/${dmg_name%.dmg}.md"
if [[ -f "$release_notes" ]]; then
    ditto "$release_notes" "$staged_notes"
else
    print -r -- "Input Status $version update." > "$staged_notes"
fi

"$generate_appcast" \
    --account "$sparkle_account" \
    --download-url-prefix "$download_prefix" \
    --embed-release-notes \
    --link "https://github.com/Houtx/Project-Input-Status" \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    -o "$appcast_file" \
    "$appcast_staging"

xmllint --noout "$appcast_file"
if ! rg -q 'sparkle:edSignature=' "$appcast_file"; then
    print -u2 "Generated appcast does not contain an Ed25519 signature."
    exit 1
fi
if ! rg -q "$download_prefix$dmg_name" "$appcast_file"; then
    print -u2 "Generated appcast does not reference the expected GitHub release asset."
    exit 1
fi

print "Created: $appcast_file"
