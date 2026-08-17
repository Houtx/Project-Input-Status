#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
dependency_root="$project_root/build/dependencies"
sparkle_version="2.9.6"
sparkle_archive="Sparkle-$sparkle_version.tar.xz"
sparkle_sha256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
sparkle_url="https://github.com/sparkle-project/Sparkle/releases/download/$sparkle_version/$sparkle_archive"
archive_path="$dependency_root/$sparkle_archive"
sparkle_root="$dependency_root/Sparkle-$sparkle_version"
framework_path="$sparkle_root/Sparkle.framework"
generate_appcast_path="$sparkle_root/bin/generate_appcast"
license_path="$sparkle_root/LICENSE"

for required_tool in curl shasum tar; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        print -u2 "Missing required tool: $required_tool"
        exit 1
    fi
done

if [[ "$dependency_root" != "$project_root/build/dependencies" ]]; then
    print -u2 "Refusing to use an unexpected dependency path: $dependency_root"
    exit 1
fi

archive_is_valid() {
    [[ -f "$archive_path" ]] || return 1
    [[ "$(shasum -a 256 "$archive_path" | awk '{print $1}')" == "$sparkle_sha256" ]]
}

if [[ ! -d "$framework_path" || ! -x "$generate_appcast_path" || ! -f "$license_path" ]]; then
    mkdir -p "$dependency_root"

    if ! archive_is_valid; then
        temporary_archive="$archive_path.download"
        rm -f "$temporary_archive"
        print -u2 "Downloading Sparkle $sparkle_version"
        curl --fail --location --show-error --output "$temporary_archive" "$sparkle_url"

        actual_sha256=$(shasum -a 256 "$temporary_archive" | awk '{print $1}')
        if [[ "$actual_sha256" != "$sparkle_sha256" ]]; then
            rm -f "$temporary_archive"
            print -u2 "Sparkle checksum verification failed."
            exit 1
        fi
        mv "$temporary_archive" "$archive_path"
    fi

    temporary_root="$sparkle_root.extracting"
    rm -rf "$temporary_root"
    mkdir -p "$temporary_root"
    tar -xf "$archive_path" -C "$temporary_root"

    if [[ ! -d "$temporary_root/Sparkle.framework" ]]; then
        rm -rf "$temporary_root"
        print -u2 "Sparkle framework was not found in the downloaded archive."
        exit 1
    fi

    rm -rf "$sparkle_root"
    mv "$temporary_root" "$sparkle_root"
fi

print -r -- "$sparkle_root"
