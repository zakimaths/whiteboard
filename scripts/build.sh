#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift-cache"
swift build -c release --product Whiteboard --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
mkdir -p build/Whiteboard.app/Contents/MacOS build/Whiteboard.app/Contents/Resources
cp .build/release/Whiteboard build/Whiteboard.app/Contents/MacOS/Whiteboard
cp Resources/Info.plist build/Whiteboard.app/Contents/Info.plist
cp Resources/AppIcon.icns build/Whiteboard.app/Contents/Resources/AppIcon.icns
# Finder can attach layout metadata after a development launch; codesign rejects it.
xattr -dr com.apple.FinderInfo build/Whiteboard.app 2>/dev/null || true
codesign --force --sign - build/Whiteboard.app
