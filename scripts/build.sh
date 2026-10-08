#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/build/Postino.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" build/modules .build/ModuleCache
# Direct compilation also works on Command Line Tools installations with a mismatched SPM manifest library.
ARCH=$(uname -m)
swiftc -O -swift-version 5 -target "$ARCH-apple-macosx13.0" -module-cache-path .build/ModuleCache -emit-library -emit-module -enable-testing -module-name RelayCore Sources/RelayCore/*.swift -emit-module-path build/modules/RelayCore.swiftmodule -Xlinker -install_name -Xlinker @rpath/libRelayCore.dylib -o "$APP/Contents/Frameworks/libRelayCore.dylib"
swiftc -O -swift-version 5 -target "$ARCH-apple-macosx13.0" -module-cache-path .build/ModuleCache -I build/modules -L "$APP/Contents/Frameworks" -lRelayCore -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/Postino/*.swift -o "$APP/Contents/MacOS/Postino"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/Logo.png ]]; then cp Resources/Logo.png "$APP/Contents/Resources/"; fi
if [[ -f Resources/DockIcon.png ]]; then cp Resources/DockIcon.png "$APP/Contents/Resources/"; fi
if [[ -f Resources/PostinoFace.icns ]]; then cp Resources/PostinoFace.icns "$APP/Contents/Resources/"; fi
rm -f "$APP/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/PostinoIcon.icns" "$APP/Contents/Resources/PostinoMacIcon.icns" "$APP/Contents/Resources/PostinoDock.icns"
codesign --force --sign - "$APP/Contents/Frameworks/libRelayCore.dylib"
codesign --force --sign - "$APP"
# A separate release path avoids development icon-services cache entries.
RELEASE_APP="$PWD/build/Release/Postino.app"
mkdir -p "$PWD/build/Release"
rm -rf "$RELEASE_APP"
ditto "$APP" "$RELEASE_APP"
print "Built $APP and $RELEASE_APP"
