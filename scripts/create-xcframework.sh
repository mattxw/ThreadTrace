#!/usr/bin/env bash
#
# Builds a static ThreadTrace.xcframework with iOS device, iOS simulator and
# macOS slices. Requires Xcode and the ThreadTrace package scheme.
#
# Each slice is packaged as a static .framework. A pure Swift module has to live
# in the framework's Modules directory: Xcode and SwiftPM do not resolve a Swift
# module from a -library XCFramework slice's Headers, so a bare .a is not
# importable even though it contains the symbols.
#
# BUILD_LIBRARY_FOR_DISTRIBUTION emits .swiftinterface files so clients built
# with a compatible compiler can import the module.
#
# Usage: scripts/create-xcframework.sh [output-directory]
#
set -euo pipefail

NAME="ThreadTrace"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/build"}"
BUILD="$OUT/xcodebuild"
STAGE="$OUT/stage"
XCF="$OUT/$NAME.xcframework"
IOS_FAMILY='<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>'

cd "$ROOT"

rm -rf "$BUILD" "$STAGE" "$XCF"
mkdir -p "$BUILD" "$STAGE"

build() {
    local destination="$1"
    local archs="$2"
    local directory="$3"

    echo "Building $directory..."
    xcodebuild \
        -quiet \
        -scheme "$NAME" \
        -configuration Release \
        -destination "$destination" \
        -derivedDataPath "$BUILD/$directory" \
        ARCHS="$archs" \
        ONLY_ACTIVE_ARCH=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        build
}

write_info_plist() {
    local path="$1"
    local platform="$2"
    local minimum_os="$3"
    local family="$4"

    cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>org.threadtrace.$NAME</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
    <key>MinimumOSVersion</key><string>$minimum_os</string>
    $family
</dict>
</plist>
EOF
}

stage() {
    local slice="$1"
    local platform="$2"
    local minimum_os="$3"
    local family="$4"
    local product="$5"
    local framework="$STAGE/$slice/$NAME.framework"

    mkdir -p "$framework/Headers" "$framework/Modules"
    libtool -static -o "$framework/$NAME" "$product/$NAME.o"
    cp -R "$product/$NAME.swiftmodule" "$framework/Modules/"
    write_info_plist "$framework/Info.plist" "$platform" "$minimum_os" "$family"
}

build 'generic/platform=iOS' 'arm64' ios
build 'generic/platform=iOS Simulator' 'arm64 x86_64' ios-sim
build 'generic/platform=macOS' 'arm64 x86_64' macos

stage ios-arm64 iPhoneOS 15.0 "$IOS_FAMILY" "$BUILD/ios/Build/Products/Release-iphoneos"
stage ios-arm64_x86_64-simulator iPhoneSimulator 15.0 "$IOS_FAMILY" \
    "$BUILD/ios-sim/Build/Products/Release-iphonesimulator"
stage macos-arm64_x86_64 MacOSX 12.0 '' "$BUILD/macos/Build/Products/Release"

xcodebuild -create-xcframework \
    -framework "$STAGE/ios-arm64/$NAME.framework" \
    -framework "$STAGE/ios-arm64_x86_64-simulator/$NAME.framework" \
    -framework "$STAGE/macos-arm64_x86_64/$NAME.framework" \
    -output "$XCF"

echo "Created $XCF"
