#!/bin/bash
set -euo pipefail
sessionbar_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$sessionbar_root"
sessionbar_out="${1:?Release directory required}"
python3 - "$sessionbar_out" <<'PY'
from pathlib import Path
import hashlib,sys,zipfile,plistlib
root=Path(sys.argv[1])
for line in (root/'SHA256SUMS.txt').read_text().splitlines():
    expected,name=line.split('  ',1)
    assert Path(name).name == name
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected, name
for path in root.glob('*.zip'):
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            assert name.startswith(('sessionbar.app/','__MACOSX/')), name
            assert not any(part in name.split('/') for part in ['.git','.codex','.DS_Store','auth.json','.build']), name
            assert not name.endswith(('.jsonl','.log')), name
        info=plistlib.loads(z.read('sessionbar.app/Contents/Info.plist'))
        assert info['CFBundleIdentifier']=='io.sessionbar.app'
        assert info['LSMinimumSystemVersion']=='14.0'
        binary=z.read('sessionbar.app/Contents/MacOS/sessionbar')
        assert binary[:4] in [bytes.fromhex('cafebabe'),bytes.fromhex('cafebabf')], 'Not a Universal binary'
        assert b'/Users/' not in binary and b'/Volumes/SSD/' not in binary, 'Build path leaked into executable'
        assert b'example-session-' not in binary, 'Demo fixture leaked into executable'
print('Release checksums and ZIP contents: OK')
PY
