#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
CHECK_APP="$PWD/build/sidebar-checks/run/Postino Sidebar Checks.app"
mkdir -p "$CHECK_APP/Contents/MacOS"
cp Info.plist "$CHECK_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.postauomo.sidebarchecks" "$CHECK_APP/Contents/Info.plist"
APP_SOURCES=(Sources/Postino/*.swift)
APP_SOURCES=(${APP_SOURCES:#Sources/Postino/main.swift})
swiftc -swift-version 5 -module-cache-path .build/ModuleCache -I build/modules -L build/Postino.app/Contents/Frameworks -lRelayCore -Xlinker -rpath -Xlinker "$PWD/build/Postino.app/Contents/Frameworks" $APP_SOURCES scripts/sidebar-checks.swift -o "$CHECK_APP/Contents/MacOS/Postino"
"$CHECK_APP/Contents/MacOS/Postino" --demo
