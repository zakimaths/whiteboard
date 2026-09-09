#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift-cache"
swift build --target WhiteboardCore --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
mkdir -p build
swiftc -I .build/debug -I .build/debug/Modules -module-cache-path .build/swift-cache \
    Sources/WhiteboardApp/CanvasView.swift Sources/WhiteboardApp/Services.swift \
    Sources/WhiteboardApp/TeXEditor.swift Sources/WhiteboardApp/AppController.swift \
    Tests/WhiteboardNativeChecks/main.swift .build/debug/WhiteboardCore.build/*.swift.o \
    -o build/WhiteboardNativeChecks
build/WhiteboardNativeChecks
