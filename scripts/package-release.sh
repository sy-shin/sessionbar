#!/bin/bash
set -euo pipefail
sessionbar_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$sessionbar_root"
sessionbar_tag="${1:-v0.2.0-beta.3}"
[[ "$sessionbar_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]] || { echo 'Invalid release tag' >&2; exit 2; }
if [[ "${2:-}" != --skip-build ]]; then ./scripts/build-app.sh --arch universal; fi
sessionbar_app="$sessionbar_root/build/sessionbar.app"
codesign --verify --deep --strict "$sessionbar_app"
lipo "$sessionbar_app/Contents/MacOS/sessionbar" -verify_arch arm64 x86_64
sessionbar_version="${sessionbar_tag#v}"
sessionbar_out="$sessionbar_root/build/releases/$sessionbar_tag"
sessionbar_stage="$sessionbar_root/.build/release-stage/$sessionbar_tag"
mkdir -p "$sessionbar_out"
# Only known distribution files enter the archive or disk image.
rm -rf "$sessionbar_stage"
mkdir -p "$sessionbar_stage"
ditto "$sessionbar_app" "$sessionbar_stage/sessionbar.app"
cp docs/000_설치및업데이트.md "$sessionbar_stage/000_설치및업데이트.md"
cmp LICENSE "$sessionbar_app/Contents/Resources/LICENSE"
cp LICENSE "$sessionbar_stage/LICENSE"
cp LICENSE "$sessionbar_out/LICENSE"
ln -sfn /Applications "$sessionbar_stage/Applications"
sessionbar_base="sessionbar-$sessionbar_version-macos-universal"
ditto -c -k --sequesterRsrc --keepParent "$sessionbar_app" "$sessionbar_out/$sessionbar_base.zip"
hdiutil create -volname "sessionbar $sessionbar_version" -srcfolder "$sessionbar_stage" -ov -format UDZO "$sessionbar_out/$sessionbar_base.dmg"
python3 - "$sessionbar_out" <<'PY'
from pathlib import Path
import hashlib,sys
root = Path(sys.argv[1])
files = sorted([*root.glob('*.zip'), *root.glob('*.dmg'), root/'LICENSE'])
(root/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in files))
PY
hdiutil verify "$sessionbar_out/$sessionbar_base.dmg"
./scripts/verify-release.sh "$sessionbar_out"
printf 'Release files: %s\n' "$sessionbar_out"
