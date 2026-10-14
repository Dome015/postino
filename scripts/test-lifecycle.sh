#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain-versions.sh
SDK_PATH=$(xcrun --sdk "macosx${POSTINO_SDK_VERSION}" --show-sdk-path)
SWIFTC=$(xcrun --find swiftc)
CHECK_APP="$PWD/build/lifecycle-checks/run/Postino Lifecycle Checks.app"
mkdir -p "$CHECK_APP/Contents/MacOS"
cp Info.plist "$CHECK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.postino.lifecyclechecks" "$CHECK_APP/Contents/Info.plist"
APP_SOURCES=(Sources/Postino/*.swift)
APP_SOURCES=(${APP_SOURCES:#Sources/Postino/main.swift})
"$SWIFTC" -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx13.0" -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$POSTINO_SDK_VERSION" -swift-version 5 -module-cache-path .build/ModuleCache -I build/modules -L build/Postino.app/Contents/Frameworks -lRelayCore -Xlinker -rpath -Xlinker "$PWD/build/Postino.app/Contents/Frameworks" $APP_SOURCES scripts/lifecycle-checks.swift -o "$CHECK_APP/Contents/MacOS/Postino"
for scenario in no-request-window no-request-quit clean-window save-window discard-window cancel-window save-quit discard-quit cancel-quit cancel-update multiple-save multiple-cancel large-window environment-window tree-shortcuts; do
    # This dedicated demo workspace is disposable; each process starts clean.
    rm -f "$PWD/build/lifecycle-checks/.demo/workspace.json"
    "$CHECK_APP/Contents/MacOS/Postino" --demo "$scenario"
done
