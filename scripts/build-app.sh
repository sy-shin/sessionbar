#!/bin/bash
set -euo pipefail
sessionbar_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$sessionbar_root"
sessionbar_install_requested=false
sessionbar_arch="$(uname -m)"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install) sessionbar_install_requested=true; shift ;;
        --arch) [[ $# -ge 2 ]] || { echo 'Missing architecture' >&2; exit 2; }; sessionbar_arch="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done
case "$sessionbar_arch" in arm64|x86_64|universal) ;; *) echo 'Architecture must be arm64, x86_64, or universal' >&2; exit 2 ;; esac
[[ -f AGENTS.md && -f README.md && -f LICENSE ]] || { echo 'AGENTS.md, README.md, and LICENSE are required' >&2; exit 1; }
sessionbar_app="$sessionbar_root/build/sessionbar.app"
# Rebuild a clean bundle; no local preferences or existing user files are copied.
rm -rf "$sessionbar_app"
mkdir -p "$sessionbar_app/Contents/MacOS" "$sessionbar_app/Contents/Resources"
sessionbar_arches=("$sessionbar_arch")
if [[ "$sessionbar_arch" == universal ]]; then sessionbar_arches=(arm64 x86_64); fi
sessionbar_binaries=()
sessionbar_source_flags=(-Xswiftc -debug-prefix-map -Xswiftc "$sessionbar_root=/source/sessionbar" -Xswiftc -file-prefix-map -Xswiftc "$sessionbar_root=/source/sessionbar")
for sessionbar_target in "${sessionbar_arches[@]}"; do
    sessionbar_triple="$sessionbar_target-apple-macosx14.0"
    sessionbar_scratch="$sessionbar_root/.build/distribution/$sessionbar_target"
    ./scripts/swift.sh build -c release --triple "$sessionbar_triple" --scratch-path "$sessionbar_scratch" "${sessionbar_source_flags[@]}"
    sessionbar_bin_dir="$(./scripts/swift.sh build -c release --triple "$sessionbar_triple" --scratch-path "$sessionbar_scratch" "${sessionbar_source_flags[@]}" --show-bin-path)"
    sessionbar_binaries+=("$sessionbar_bin_dir/sessionbar")
done
if [[ "$sessionbar_arch" == universal ]]; then
    lipo -create "${sessionbar_binaries[@]}" -output "$sessionbar_app/Contents/MacOS/sessionbar"
else
    cp "${sessionbar_binaries[0]}" "$sessionbar_app/Contents/MacOS/sessionbar"
fi
# Remove linker debug records, which otherwise contain absolute object-file paths.
xcrun strip -S "$sessionbar_app/Contents/MacOS/sessionbar"
cp Packaging/Info.plist "$sessionbar_app/Contents/Info.plist"
iconutil -c icns Packaging/AppIcon.iconset -o "$sessionbar_app/Contents/Resources/AppIcon.icns"
ditto Packaging/Resources "$sessionbar_app/Contents/Resources"
cp LICENSE "$sessionbar_app/Contents/Resources/LICENSE"
codesign --force --sign - "$sessionbar_app"
codesign --verify --deep --strict "$sessionbar_app"
if [[ "$sessionbar_install_requested" == true ]]; then
    sessionbar_install="$HOME/Applications/sessionbar.app"
    mkdir -p "$HOME/Applications"
    ditto "$sessionbar_app" "$sessionbar_install"
    open "$sessionbar_install"
else
    printf 'App: %s\n' "$sessionbar_app"
fi
