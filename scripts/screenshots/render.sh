#!/bin/bash
# Render the real SwiftUI views offscreen; never launch or change the desktop.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
output_dir="${1:-$repo_root/screenshots}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/sunpaper-screenshots.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$output_dir"

xcrun swiftc -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macos14.0" \
    "$repo_root"/Sunpaper/Models/*.swift \
    "$repo_root"/Sunpaper/Services/*.swift \
    "$repo_root"/Sunpaper/Views/*.swift \
    "$repo_root/scripts/screenshots/Render.swift" \
    -o "$build_dir/render"
"$build_dir/render" "$output_dir"
