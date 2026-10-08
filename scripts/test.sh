#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ -f build/Postino.app/Contents/MacOS/Postino ]] || scripts/build.sh
swiftc -O -swift-version 5 -module-cache-path .build/ModuleCache -I build/modules -L build/Postino.app/Contents/Frameworks -lRelayCore -Xlinker -rpath -Xlinker "$PWD/build/Postino.app/Contents/Frameworks" scripts/checks.swift -o build/relay-checks
build/relay-checks
