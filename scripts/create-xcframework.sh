#!/usr/bin/env bash
#
# Builds a static ThreadTrace.xcframework with iOS device, iOS simulator and
# macOS slices. Requires Xcode and the ThreadTrace package scheme.
#
# The library is pure Swift, so each slice bundles its .swiftmodule next to the
# static library. BUILD_LIBRARY_FOR_DISTRIBUTION emits .swiftinterface files so
# clients built with a compatible compiler can import the module.
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

stage() {
    local product="$1"
    local destination="$2"

    mkdir -p "$destination/Headers"
    libtool -static -o "$destination/lib$NAME.a" "$product/$NAME.o"
    cp -R "$product/$NAME.swiftmodule" "$destination/Headers/"
}

build 'generic/platform=iOS' 'arm64' ios
build 'generic/platform=iOS Simulator' 'arm64 x86_64' ios-sim
build 'generic/platform=macOS' 'arm64 x86_64' macos

stage "$BUILD/ios/Build/Products/Release-iphoneos" "$STAGE/ios"
stage "$BUILD/ios-sim/Build/Products/Release-iphonesimulator" "$STAGE/ios-sim"
stage "$BUILD/macos/Build/Products/Release" "$STAGE/macos"

xcodebuild -create-xcframework \
    -library "$STAGE/ios/lib$NAME.a" -headers "$STAGE/ios/Headers" \
    -library "$STAGE/ios-sim/lib$NAME.a" -headers "$STAGE/ios-sim/Headers" \
    -library "$STAGE/macos/lib$NAME.a" -headers "$STAGE/macos/Headers" \
    -output "$XCF"

echo "Created $XCF"
