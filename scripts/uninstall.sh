#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
install_root=${INPUT_STATUS_INSTALL_DIR:-"/Applications"}
installed_bundle="$install_root/InputStatus.app"
installed_extension="$installed_bundle/Contents/PlugIns/InputStatusWidgetExtension.appex"
legacy_bundle="$HOME/Applications/InputStatus.app"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
launch_agent="$HOME/Library/LaunchAgents/com.inputstatus.desktop.plist"
launch_domain="gui/$(id -u)"

if [[ "$installed_bundle" != */InputStatus.app || "$installed_bundle" == "/InputStatus.app" ]]; then
    print -u2 "Refusing to uninstall an unexpected path: $installed_bundle"
    exit 1
fi

pkill -x InputStatus >/dev/null 2>&1 || true
launchctl bootout "$launch_domain" "$launch_agent" >/dev/null 2>&1 || true
if [[ -f "$launch_agent" ]]; then
    rm -f "$launch_agent"
fi
if [[ -d "$installed_extension" ]]; then
    pluginkit -r "$installed_extension" >/dev/null 2>&1 || true
fi
if [[ -d "$installed_bundle" ]]; then
    "$launch_services" -u "$installed_bundle" >/dev/null 2>&1 || true
    rm -rf "$installed_bundle"
fi
if [[ "$legacy_bundle" != "$installed_bundle" && -d "$legacy_bundle" ]]; then
    "$launch_services" -u "$legacy_bundle" >/dev/null 2>&1 || true
    rm -rf "$legacy_bundle"
fi

print "Uninstalled: $installed_bundle"
