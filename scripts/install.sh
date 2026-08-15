#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
source_bundle="$project_root/build/InputStatus.app"
install_root=${INPUT_STATUS_INSTALL_DIR:-"/Applications"}
installed_bundle="$install_root/InputStatus.app"
installed_extension="$installed_bundle/Contents/PlugIns/InputStatusWidgetExtension.appex"
legacy_bundle="$HOME/Applications/InputStatus.app"
legacy_extension="$legacy_bundle/Contents/PlugIns/InputStatusWidgetExtension.appex"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
launch_agent="$HOME/Library/LaunchAgents/com.inputstatus.desktop.plist"
launch_domain="gui/$(id -u)"

"$script_dir/build.sh"

if [[ "$installed_bundle" != */InputStatus.app || "$installed_bundle" == "/InputStatus.app" ]]; then
    print -u2 "Refusing to install to an unexpected path: $installed_bundle"
    exit 1
fi

mkdir -p "$install_root"
pkill -x InputStatus >/dev/null 2>&1 || true

if [[ "$legacy_bundle" != "$installed_bundle" && -d "$legacy_bundle" ]]; then
    if [[ -d "$legacy_extension" ]]; then
        pluginkit -r "$legacy_extension" >/dev/null 2>&1 || true
    fi
    "$launch_services" -u "$legacy_bundle" >/dev/null 2>&1 || true
    rm -rf "$legacy_bundle"
fi

if [[ -d "$installed_extension" ]]; then
    pluginkit -r "$installed_extension" >/dev/null 2>&1 || true
fi
if [[ -d "$installed_bundle" ]]; then
    "$launch_services" -u "$installed_bundle" >/dev/null 2>&1 || true
    rm -rf "$installed_bundle"
fi

ditto "$source_bundle" "$installed_bundle"
codesign --verify --deep --strict --verbose=2 "$installed_bundle"
"$launch_services" -f "$installed_bundle"
pluginkit -a "$installed_extension"
pluginkit -e use -i com.inputstatus.desktop.widget >/dev/null 2>&1 || true
mkdir -p "$HOME/Library/LaunchAgents"
launchctl bootout "$launch_domain" "$launch_agent" >/dev/null 2>&1 || true
plutil -create xml1 "$launch_agent"
plutil -insert Label -string com.inputstatus.desktop "$launch_agent"
plutil -insert ProgramArguments -json \
    "[\"/usr/bin/open\",\"-g\",\"$installed_bundle\"]" \
    "$launch_agent"
plutil -insert RunAtLoad -bool true "$launch_agent"
launchctl bootstrap "$launch_domain" "$launch_agent"
killall chronod >/dev/null 2>&1 || true
killall NotificationCenter >/dev/null 2>&1 || true
killall WidgetConfigurationExtension >/dev/null 2>&1 || true

print "Installed: $installed_bundle"
print "The desktop widget starts automatically and will reopen after login."
