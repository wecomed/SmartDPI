#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
task_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
task_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
task_min_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
export SDKROOT="$task_sdk_path"
# Generic arm64 supports the M family without tuning code to the build machine.
# Explicit SDK selection enables current native UI while retaining macOS 13 deployment.
task_build_flags=(--arch arm64 --sdk "$task_sdk_path" --disable-sandbox --cache-path "$PWD/.build/cache")
# Some SwiftPM/CLT combinations use the deployment version for both linker fields.
# Supply the actual SDK at link time, leaving the minimum runtime unchanged.
swift build -c release -debug-info-format none "${task_build_flags[@]}" \
    -Xlinker -syslibroot -Xlinker "$task_sdk_path" \
    -Xlinker -platform_version -Xlinker macos -Xlinker "$task_min_os" -Xlinker "$task_sdk_version"
task_bin_dir="$(swift build -c release --show-bin-path "${task_build_flags[@]}")"
task_app_dir="${SMARTDPI_APP_OUTPUT:-$PWD/dist/SmartDPI.app}"
mkdir -p "$task_app_dir/Contents/MacOS" "$task_app_dir/Contents/Resources"
cp "$task_bin_dir/SmartDPI" "$task_app_dir/Contents/MacOS/SmartDPI"
cp Resources/Info.plist "$task_app_dir/Contents/Info.plist"
cp docs/INSTALLATION.html "$task_app_dir/Contents/Resources/INSTALLATION.html"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string macosx$task_sdk_version" "$task_app_dir/Contents/Info.plist"
"$task_bin_dir/SmartDPI" --render-icon "$task_app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$task_app_dir"
task_archs="$(lipo -archs "$task_app_dir/Contents/MacOS/SmartDPI")"
[[ "$task_archs" == "arm64" ]] || { print -u2 "构建架构错误：$task_archs"; exit 1; }
task_linked_sdk="$(xcrun vtool -show-build "$task_app_dir/Contents/MacOS/SmartDPI" | awk '$1 == "sdk" {print $2; exit}')"
[[ "$task_linked_sdk" == "$task_sdk_version" ]] || { print -u2 "构建 SDK 不匹配：$task_linked_sdk / $task_sdk_version"; exit 1; }
print "已生成：$task_app_dir"
