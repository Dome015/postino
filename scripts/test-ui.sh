#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain-versions.sh
SDK_PATH=$(xcrun --sdk "macosx${POSTINO_SDK_VERSION}" --show-sdk-path)
SWIFTC=$(xcrun --find swiftc)
CHECK_APP="$PWD/build/ui-checks/run/Postino UI Checks.app"
mkdir -p "$CHECK_APP/Contents/MacOS"
cp Info.plist "$CHECK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.postauomo.uichecks" "$CHECK_APP/Contents/Info.plist"
APP_SOURCES=(Sources/Postino/*.swift)
APP_SOURCES=(${APP_SOURCES:#Sources/Postino/main.swift})
"$SWIFTC" -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx13.0" -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$POSTINO_SDK_VERSION" -swift-version 5 -module-cache-path .build/ModuleCache -I build/modules -L build/Postino.app/Contents/Frameworks -lRelayCore -Xlinker -rpath -Xlinker "$PWD/build/Postino.app/Contents/Frameworks" $APP_SOURCES scripts/ui-checks.swift -o "$CHECK_APP/Contents/MacOS/Postino"
"$CHECK_APP/Contents/MacOS/Postino" --demo
