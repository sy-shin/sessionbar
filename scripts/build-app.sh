#!/bin/bash
set -euo pipefail
sessionbar_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$sessionbar_root"
./scripts/swift.sh build -c release
sessionbar_binary="$(./scripts/swift.sh build -c release --show-bin-path)/sessionbar"
sessionbar_app="$sessionbar_root/build/sessionbar.app"
mkdir -p "$sessionbar_app/Contents/MacOS" "$sessionbar_app/Contents/Resources"
cp "$sessionbar_binary" "$sessionbar_app/Contents/MacOS/sessionbar"
cp "$sessionbar_root/Packaging/Info.plist" "$sessionbar_app/Contents/Info.plist"
if [[ -d "$sessionbar_root/Packaging/AppIcon.iconset" ]]; then
    iconutil -c icns "$sessionbar_root/Packaging/AppIcon.iconset" -o "$sessionbar_app/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$sessionbar_app"
if [[ "${1:-}" == "--install" ]]; then
    sessionbar_install="$HOME/Applications/sessionbar.app"
    mkdir -p "$HOME/Applications"
    ditto "$sessionbar_app" "$sessionbar_install"
    open "$sessionbar_install"
else
    printf 'App: %s\n' "$sessionbar_app"
fi
