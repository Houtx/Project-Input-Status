#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
resources_dir="$project_root/InputStatus/Resources"
source_png="$resources_dir/AppIcon-1024.png"
iconset_dir="$resources_dir/AppIcon.iconset"
output_icns="$resources_dir/AppIcon.icns"

for required_tool in swift sips iconutil; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        print -u2 "Missing required tool: $required_tool"
        exit 1
    fi
done

swift "$script_dir/generate-icon.swift" "$source_png"

rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_png" \
        --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$source_png" \
        --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$iconset_dir" -o "$output_icns"
rm -rf "$iconset_dir"

print "Generated: $source_png"
print "Generated: $output_icns"
