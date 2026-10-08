#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/DockIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" Resources/DockIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
# Pack PNG representations directly; no Xcode asset compiler is required.
python3 - <<'PY'
from pathlib import Path
import struct
root = Path('build/AppIcon.iconset')
representations = [('icp4','icon_16x16.png'),('icp5','icon_32x32.png'),('ic07','icon_128x128.png'),('ic08','icon_256x256.png'),('ic09','icon_512x512.png'),('ic10','icon_512x512@2x.png'),('ic11','icon_16x16@2x.png'),('ic12','icon_32x32@2x.png'),('ic13','icon_128x128@2x.png'),('ic14','icon_256x256@2x.png')]
chunks = []
for kind, name in representations:
    payload = (root / name).read_bytes()
    chunks.append(kind.encode() + struct.pack('>I', len(payload) + 8) + payload)
content = b''.join(chunks)
Path('Resources/PostinoFace.icns').write_bytes(b'icns' + struct.pack('>I', len(content) + 8) + content)
PY
