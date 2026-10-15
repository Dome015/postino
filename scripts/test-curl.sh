#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain-versions.sh
SDK_PATH=$(xcrun --sdk "macosx${POSTINO_SDK_VERSION}" --show-sdk-path)
xcrun swiftc -parse-as-library -sdk "$SDK_PATH" -swift-version 5 -module-cache-path .build/ModuleCache -I build/modules -L build/Postino.app/Contents/Frameworks -lRelayCore -Xlinker -rpath -Xlinker "$PWD/build/Postino.app/Contents/Frameworks" scripts/curl-checks.swift -o build/curl-checks
fixture_dir=$(mktemp -d "$PWD/build/curl-fixture.XXXXXX")
python3 -u scripts/curl-fixture.py "$fixture_dir/port" >"$fixture_dir/server.log" 2>&1 &
fixture_pid=$!
trap '/bin/kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; /bin/rm -rf "$fixture_dir"' EXIT
fixture_failed() {
    print -u2 -- "$1"
    cat "$fixture_dir/server.log" >&2
    exit 1
}
for attempt in {1..300}; do
    [[ -s "$fixture_dir/port" ]] && break
    /bin/kill -0 "$fixture_pid" 2>/dev/null || fixture_failed "cURL fixture exited before publishing its port."
    /bin/sleep 0.1
done
[[ -s "$fixture_dir/port" ]] || fixture_failed "Timed out after 30 seconds waiting for the cURL fixture port."
/bin/kill -0 "$fixture_pid" 2>/dev/null || fixture_failed "cURL fixture exited during startup."
fixture_port="$(<"$fixture_dir/port")"
[[ "$fixture_port" == <1-65535> ]] || fixture_failed "cURL fixture published an invalid port: $fixture_port"
build/curl-checks "$fixture_port"
