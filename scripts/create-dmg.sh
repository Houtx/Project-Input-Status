#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
build_root="$project_root/build"
dist_root="$project_root/dist"
app_bundle="$build_root/InputStatus.app"
icon_file="$project_root/InputStatus/Resources/AppIcon.icns"
background_file="$build_root/dmg-background.png"
staging_dir="$build_root/dmg-staging"
version=$(plutil -extract CFBundleShortVersionString raw \
    "$project_root/InputStatus/Resources/InputStatus-Info.plist")
dmg_file="$dist_root/InputStatus-$version-universal.dmg"
checksum_file="$dmg_file.sha256"
appcast_file="$dist_root/appcast.xml"

for required_tool in create-dmg ditto hdiutil plutil shasum swift; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        print -u2 "Missing required tool: $required_tool"
        if [[ "$required_tool" == "create-dmg" ]]; then
            print -u2 "Install it with: brew install create-dmg"
        fi
        exit 1
    fi
done

if [[ "$staging_dir" != "$project_root/build/dmg-staging" ]]; then
    print -u2 "Refusing to clean an unexpected staging path: $staging_dir"
    exit 1
fi
if [[ "$dist_root" != "$project_root/dist" ]]; then
    print -u2 "Refusing to write to an unexpected distribution path: $dist_root"
    exit 1
fi

"$script_dir/build.sh"
swift "$script_dir/generate-dmg-background.swift" "$icon_file" "$background_file"

rm -rf "$staging_dir"
mkdir -p "$staging_dir" "$dist_root"
ditto "$app_bundle" "$staging_dir/InputStatus.app"

create-dmg \
    --overwrite \
    --volname "Input Status $version" \
    --volicon "$icon_file" \
    --background "$background_file" \
    --window-pos 180 120 \
    --window-size 760 480 \
    --text-size 14 \
    --icon-size 112 \
    --icon "InputStatus.app" 180 230 \
    --hide-extension "InputStatus.app" \
    --app-drop-link 580 230 \
    --app-drop-link-name "应用程序" \
    --filesystem APFS \
    --no-internet-enable \
    "$dmg_file" \
    "$staging_dir"

hdiutil verify "$dmg_file"
(
    cd "$dist_root"
    shasum -a 256 "${dmg_file:t}" > "${checksum_file:t}"
)
"$script_dir/create-appcast.sh"

print "Created: $dmg_file"
print "Checksum: $checksum_file"
print "Appcast: $appcast_file"
