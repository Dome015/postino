#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swiftc -O -swift-version 5 -module-cache-path .build/ModuleCache -I build/modules -L build/Postino.app/Contents/Frameworks -lRelayCore -Xlinker -rpath -Xlinker "$PWD/build/Postino.app/Contents/Frameworks" scripts/tree-checks.swift -o build/tree-checks
build/tree-checks
