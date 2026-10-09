#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/toolchain-versions.sh
# Do not inherit a runner's default SDK or a swiftc installed elsewhere on PATH.
SDK_PATH=$(xcrun --sdk "macosx${POSTINO_SDK_VERSION}" --show-sdk-path)
SDK_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :Version' "$SDK_PATH/SDKSettings.plist")
SWIFTC=$(xcrun --find swiftc)
SWIFT_VERSION=$("$SWIFTC" --version | sed -nE 's/.*Apple Swift version ([^ ]+).*/\1/p')
if [[ "$SDK_VERSION" != "$POSTINO_SDK_VERSION" || "$SWIFT_VERSION" != "$POSTINO_SWIFT_VERSION" ]]; then
    print -u2 "Postino requires macOS SDK $POSTINO_SDK_VERSION and Apple Swift $POSTINO_SWIFT_VERSION (Xcode $POSTINO_XCODE_VERSION or matching Command Line Tools)."
    print -u2 "Selected SDK: $SDK_VERSION; Swift: $SWIFT_VERSION. Set DEVELOPER_DIR to the matching toolchain."
    exit 1
fi
print "Building with macOS SDK $SDK_VERSION, Apple Swift $SWIFT_VERSION, compiler $SWIFTC"
APP="$PWD/build/Postino.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" build/modules .build/ModuleCache
# Direct compilation also works on Command Line Tools installations with a mismatched SPM manifest library.
ARCH=$(uname -m)
# Pass the real SDK to the linker too: some Command Line Tools drivers otherwise
# record the deployment target as the SDK version when -sdk is explicit.
BUILD_FLAGS=(-sdk "$SDK_PATH" -O -swift-version 5 -target "$ARCH-apple-macosx13.0" -module-cache-path .build/ModuleCache -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$SDK_VERSION")
"$SWIFTC" "${BUILD_FLAGS[@]}" -emit-library -emit-module -enable-testing -module-name RelayCore Sources/RelayCore/*.swift -emit-module-path build/modules/RelayCore.swiftmodule -Xlinker -install_name -Xlinker @rpath/libRelayCore.dylib -o "$APP/Contents/Frameworks/libRelayCore.dylib"
"$SWIFTC" "${BUILD_FLAGS[@]}" -I build/modules -L "$APP/Contents/Frameworks" -lRelayCore -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/Postino/*.swift -o "$APP/Contents/MacOS/Postino"
for binary in "$APP/Contents/MacOS/Postino" "$APP/Contents/Frameworks/libRelayCore.dylib"; do
    LINKED_SDK=$(xcrun vtool -show-build "$binary" | awk '$1 == "sdk" { print $2 }')
    MINIMUM_OS=$(xcrun vtool -show-build "$binary" | awk '$1 == "minos" { print $2 }')
    if [[ "$LINKED_SDK" != "$POSTINO_SDK_VERSION" || "$MINIMUM_OS" != "13.0" ]]; then
        print -u2 "Unexpected build metadata in $binary: SDK $LINKED_SDK, minimum macOS $MINIMUM_OS"
        exit 1
    fi
done
cp Info.plist "$APP/Contents/Info.plist"
printf '{"sdk":"%s","swift":"%s","architecture":"%s","deploymentTarget":"13.0"}\n' "$SDK_VERSION" "$SWIFT_VERSION" "$ARCH" > "$APP/Contents/Resources/BuildInfo.json"
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
