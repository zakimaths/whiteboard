#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift-cache"
swift build -c release --product Whiteboard --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
mkdir -p build
stage=$(mktemp -d /private/tmp/whiteboard-build.XXXXXX)
mkdir -p "$stage/Whiteboard.app/Contents/MacOS" "$stage/Whiteboard.app/Contents/Resources"
cp .build/release/Whiteboard "$stage/Whiteboard.app/Contents/MacOS/Whiteboard"
cp Resources/Info.plist "$stage/Whiteboard.app/Contents/Info.plist"
cp Resources/AppIcon.icns "$stage/Whiteboard.app/Contents/Resources/AppIcon.icns"
# Academic assets belong to GitHub sample tools, never the installed app.
codesign --force --sign - "$stage/Whiteboard.app"
codesign --verify --deep --strict "$stage/Whiteboard.app"
if [ -d build/Whiteboard.app ]; then
    previous=$(mktemp -d build/previous-app.XXXXXX)
    mv build/Whiteboard.app "$previous/Whiteboard.app"
fi
ditto --norsrc --noextattr "$stage/Whiteboard.app" build/Whiteboard.app
