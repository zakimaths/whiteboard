#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift-cache"
swift run -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security WhiteboardSamples "${1:-build/Sample Ideas}" "${2:-build/Sample Exports}"
