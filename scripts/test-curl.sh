#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain-versions.sh
SDK_PATH=$(xcrun --sdk "macosx${POSTINO_SDK_VERSION}" --show-sdk-path)
xcrun swiftc -parse-as-library -sdk "$SDK_PATH" -swift-version 5 -module-cache-path .build/ModuleCache -I build/modules -L build/Postino.app/Contents/Frameworks -lRelayCore -Xlinker -rpath -Xlinker "$PWD/build/Postino.app/Contents/Frameworks" scripts/curl-checks.swift -o build/curl-checks
fixture_dir=$(mktemp -d "$PWD/build/curl-fixture.XXXXXX")
python3 scripts/curl-fixture.py "$fixture_dir/port" &
fixture_pid=$!
trap '/bin/kill "$fixture_pid" 2>/dev/null || true; /bin/rm -rf "$fixture_dir"' EXIT
for attempt in {1..100}; do
    [[ -s "$fixture_dir/port" ]] && break
    /bin/sleep 0.05
done
build/curl-checks "$(cat "$fixture_dir/port")"
