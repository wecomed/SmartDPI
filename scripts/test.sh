#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

# Some Command Line Tools releases omit Swift Testing's plugin from discovery.
task_swiftc="$(xcrun --find swiftc)"
task_plugin="${task_swiftc:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
task_plugin_flags=()
if [[ -f "$task_plugin" ]]; then
    task_plugin_flags=(-Xswiftc -load-plugin-library -Xswiftc "$task_plugin")
fi
swift test --disable-sandbox --disable-xctest --cache-path "$PWD/.build/cache" "${task_plugin_flags[@]}"
