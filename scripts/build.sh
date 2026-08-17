#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
build_root="$project_root/build"
app_bundle="$build_root/InputStatus.app"
extension_bundle="$app_bundle/Contents/PlugIns/InputStatusWidgetExtension.appex"
app_executable="$app_bundle/Contents/MacOS/InputStatus"
extension_executable="$extension_bundle/Contents/MacOS/InputStatusWidgetExtension"
icon_file="$project_root/InputStatus/Resources/AppIcon.icns"
arch_build_root="$build_root/Architectures"
module_cache_root="$build_root/ModuleCache"
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
sdk_version=$(xcrun --sdk macosx --show-sdk-version)
sdk_build=$(xcrun --sdk macosx --show-sdk-build-version)
os_build=$(sw_vers -buildVersion)
deployment_target="14.0"
target_arches=(arm64 x86_64)

for required_tool in swiftc codesign lipo plutil xcrun; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        print -u2 "Missing required tool: $required_tool"
        exit 1
    fi
done

if [[ ! -f "$icon_file" ]]; then
    "$script_dir/generate-icon.sh"
fi

if [[ "$app_bundle" != "$project_root/build/InputStatus.app" ]]; then
    print -u2 "Refusing to clean an unexpected build path: $app_bundle"
    exit 1
fi
if [[ "$arch_build_root" != "$project_root/build/Architectures" ]]; then
    print -u2 "Refusing to clean an unexpected architecture path: $arch_build_root"
    exit 1
fi

rm -rf "$app_bundle" "$arch_build_root"
mkdir -p \
    "$app_bundle/Contents/MacOS" \
    "$app_bundle/Contents/Resources" \
    "$extension_bundle/Contents/MacOS" \
    "$extension_bundle/Contents/Resources" \
    "$arch_build_root" \
    "$module_cache_root"

shared_sources=("$project_root"/InputStatus/Shared/*.swift)
app_sources=("$project_root"/InputStatus/App/*.swift)
widget_sources=("$project_root"/InputStatus/Widget/*.swift)

for target_arch in "${target_arches[@]}"; do
    arch_root="$arch_build_root/$target_arch"
    module_cache="$module_cache_root/$target_arch"
    arch_app_executable="$arch_root/InputStatus"
    arch_extension_executable="$arch_root/InputStatusWidgetExtension"
    mkdir -p "$arch_root" "$module_cache"

    common_flags=(
        -O
        -warnings-as-errors
        -swift-version 5
        -target "$target_arch-apple-macosx$deployment_target"
        -sdk "$sdk_path"
        -Xlinker -dead_strip
    )

    print "Building InputStatus.app ($target_arch)"
    SWIFT_MODULECACHE_PATH="$module_cache" \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    swiftc \
        "${common_flags[@]}" \
        -module-name InputStatus \
        -o "$arch_app_executable" \
        "${shared_sources[@]}" \
        "${app_sources[@]}"

    print "Building InputStatusWidgetExtension.appex ($target_arch)"
    SWIFT_MODULECACHE_PATH="$module_cache" \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    swiftc \
        "${common_flags[@]}" \
        -application-extension \
        -module-name InputStatusWidgetExtension \
        -o "$arch_extension_executable" \
        "${shared_sources[@]}" \
        "${widget_sources[@]}"
done

print "Creating Universal 2 executables"
lipo -create \
    "$arch_build_root/arm64/InputStatus" \
    "$arch_build_root/x86_64/InputStatus" \
    -output "$app_executable"
lipo -create \
    "$arch_build_root/arm64/InputStatusWidgetExtension" \
    "$arch_build_root/x86_64/InputStatusWidgetExtension" \
    -output "$extension_executable"
lipo "$app_executable" -verify_arch arm64 x86_64
lipo "$extension_executable" -verify_arch arm64 x86_64

cp \
    "$project_root/InputStatus/Resources/InputStatus-Info.plist" \
    "$app_bundle/Contents/Info.plist"
cp \
    "$project_root/InputStatus/Resources/InputStatusWidget-Info.plist" \
    "$extension_bundle/Contents/Info.plist"
cp "$icon_file" "$app_bundle/Contents/Resources/AppIcon.icns"
cp "$icon_file" "$extension_bundle/Contents/Resources/AppIcon.icns"

for info_plist in \
    "$app_bundle/Contents/Info.plist" \
    "$extension_bundle/Contents/Info.plist"; do
    plutil -replace BuildMachineOSBuild -string "$os_build" "$info_plist"
    plutil -replace DTCompiler -string "com.apple.compilers.llvm.clang.1_0" "$info_plist"
    plutil -replace DTPlatformBuild -string "" "$info_plist"
    plutil -replace DTPlatformName -string "macosx" "$info_plist"
    plutil -replace DTPlatformVersion -string "$sdk_version" "$info_plist"
    plutil -replace DTSDKBuild -string "$sdk_build" "$info_plist"
    plutil -replace DTSDKName -string "macosx$sdk_version" "$info_plist"
done

# Make the extension explicitly eligible for WidgetKit discovery on newer macOS releases.
plutil -replace CHSDisableImplicitWidgetDiscovery -bool false \
    "$extension_bundle/Contents/Info.plist"

plutil -lint "$app_bundle/Contents/Info.plist" >/dev/null
plutil -lint "$extension_bundle/Contents/Info.plist" >/dev/null

print "Signing bundles for local use"
codesign \
    --force \
    --sign - \
    --timestamp=none \
    --entitlements "$project_root/InputStatus/Resources/InputStatusWidget.entitlements" \
    "$extension_bundle"
codesign \
    --force \
    --sign - \
    --timestamp=none \
    --entitlements "$project_root/InputStatus/Resources/InputStatus.entitlements" \
    "$app_bundle"

codesign --verify --deep --strict --verbose=2 "$app_bundle"

print "Built: $app_bundle"
