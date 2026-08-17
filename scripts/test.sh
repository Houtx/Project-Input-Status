#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
test_root="$project_root/build/Tests"
test_executable="$test_root/StatusCoreTests"

for required_tool in plutil swiftc xcrun; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        print -u2 "Missing required tool: $required_tool"
        exit 1
    fi
done

if [[ "$test_root" != "$project_root/build/Tests" ]]; then
    print -u2 "Refusing to clean an unexpected test path: $test_root"
    exit 1
fi

target_arch=$(uname -m)
if [[ "$target_arch" != "arm64" && "$target_arch" != "x86_64" ]]; then
    print -u2 "Unsupported test architecture: $target_arch"
    exit 1
fi

sdk_path=$(xcrun --sdk macosx --show-sdk-path)
rm -rf "$test_root"
mkdir -p "$test_root"

swiftc \
    -warnings-as-errors \
    -swift-version 5 \
    -target "$target_arch-apple-macosx14.0" \
    -sdk "$sdk_path" \
    -o "$test_executable" \
    "$project_root/InputStatus/Shared/StatusModels.swift" \
    "$project_root/InputStatus/Shared/StatusAPI.swift" \
    "$project_root/Tests/StatusCoreTests.swift"

"$test_executable"

for script_file in "$project_root"/scripts/*.sh; do
    zsh -n "$script_file"
done
plutil -lint \
    "$project_root"/InputStatus/Resources/*.plist \
    "$project_root"/InputStatus/Resources/*.entitlements >/dev/null

print "Script and plist checks passed"
