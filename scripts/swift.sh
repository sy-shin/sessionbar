#!/bin/bash
set -euo pipefail
sessionbar_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$sessionbar_root/scripts/build-paths.sh"
sessionbar_compiler="$(xcrun --find swiftc)"
sessionbar_swift="$(xcrun --find swift)"
sessionbar_developer="$(xcode-select -p)"
sessionbar_tools="$sessionbar_build_root/toolchain"

# Isolate stale files left by an incomplete Command Line Tools upgrade.
# Healthy toolchains use the normal compiler and manifest library directly.
python3 - "$sessionbar_tools" "$sessionbar_developer" "$sessionbar_compiler" <<'PY'
import json, pathlib, platform, shutil, sys
root, developer, compiler = map(pathlib.Path, sys.argv[1:])
installed = developer / 'usr/lib/swift/pm/ManifestAPI'
architecture = platform.machine()
public = installed / f'PackageDescription.swiftmodule/{architecture}-apple-macos.swiftinterface'
private = installed / f'PackageDescription.swiftmodule/{architecture}-apple-macos.private.swiftinterface'
old_map = developer / 'usr/include/swift/module.modulemap'
new_map = developer / 'usr/include/swift/bridging.modulemap'
stale = public.exists() and private.exists() and 'enum SwiftLanguageMode' in public.read_text() and 'enum SwiftVersion' in private.read_text()
duplicate = old_map.exists() and new_map.exists() and 'module SwiftBridging' in old_map.read_text() and 'module SwiftBridging' in new_map.read_text()
root.mkdir(parents=True, exist_ok=True)
(root / 'use-custom-libs').unlink(missing_ok=True)
(root / 'use-overlay').unlink(missing_ok=True)
if stale:
    module = root / 'ManifestAPI/PackageDescription.swiftmodule'
    module.mkdir(parents=True, exist_ok=True)
    shutil.copy2(installed / 'libPackageDescription.dylib', root / 'ManifestAPI')
    shutil.copy2(public, module / public.name)
    shutil.copy2(public, module / private.name)
    (root / 'use-custom-libs').touch()
if duplicate:
    empty = root / 'empty.modulemap'
    empty.write_text('')
    (root / 'overlay.json').write_text(json.dumps({'version':0,'case-sensitive':False,'roots':[{'type':'file','name':str(old_map),'external-contents':str(empty)}]}))
    (root / 'use-overlay').touch()
if stale or duplicate:
    import shlex
    command = '#!/bin/sh\nexec ' + shlex.quote(str(compiler)) + ' "$@"'
    if duplicate: command += ' -vfsoverlay ' + shlex.quote(str(root / 'overlay.json'))
    if stale: command += f' -target {architecture}-apple-macosx14.0'
    wrapper = root / 'manifest-swiftc'
    wrapper.write_text(command + '\n'); wrapper.chmod(0o755)
PY
sessionbar_flags=()
if [[ -f "$sessionbar_tools/use-custom-libs" ]]; then
    export SWIFTPM_CUSTOM_LIBS_DIR="$sessionbar_tools"
fi
if [[ -f "$sessionbar_tools/use-overlay" ]]; then
    sessionbar_flags=(-Xswiftc -vfsoverlay -Xswiftc "$sessionbar_tools/overlay.json")
fi
if [[ -f "$sessionbar_tools/use-custom-libs" || -f "$sessionbar_tools/use-overlay" ]]; then
    export SWIFT_EXEC_MANIFEST="$sessionbar_tools/manifest-swiftc"
fi
if [[ "${1:-}" == "test" ]]; then
    sessionbar_has_scratch=false
    for sessionbar_argument in "$@"; do
        case "$sessionbar_argument" in --scratch-path|--scratch-path=*) sessionbar_has_scratch=true ;; esac
    done
    if [[ "$sessionbar_has_scratch" == false ]]; then
        sessionbar_flags+=(--scratch-path "$sessionbar_build_root/tests")
    fi
    # This repository uses Swift Testing exclusively, including executable-target tests.
    sessionbar_flags+=(--disable-xctest)
    if [[ -d "$sessionbar_developer/Library/Developer/Frameworks/Testing.framework" ]]; then
        sessionbar_flags+=(-Xswiftc -F -Xswiftc "$sessionbar_developer/Library/Developer/Frameworks")
        sessionbar_flags+=(-Xlinker -rpath -Xlinker "$sessionbar_developer/Library/Developer/Frameworks")
        if [[ ! -d "$sessionbar_developer/Library/Developer/Frameworks/_Testing_Foundation.framework/Modules/_Testing_Foundation.swiftmodule" ]]; then
            # Some CLT distributions declare this overlay but omit its module.
            sessionbar_flags+=(-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays)
        fi
    fi
fi
cd "$sessionbar_root"
# Bash 3 treats an empty array as unset with nounset enabled.
exec "$sessionbar_swift" "$@" ${sessionbar_flags[@]+"${sessionbar_flags[@]}"}
