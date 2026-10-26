#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

if (( $# > 2 )); then
    print -u2 "Usage: $0 [SmartDPI.app] [output-directory]"
    exit 2
fi

task_app_dir="${1:-$PWD/dist/SmartDPI.app}"
task_output_dir="${2:-$PWD/dist/releases}"
task_app_dir="${task_app_dir:A}"
task_output_dir="${task_output_dir:A}"
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
task_min_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"

[[ "$task_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || {
    print -u2 "Invalid release version: $task_version"
    exit 1
}
[[ -d "$task_app_dir" && "${task_app_dir:t}" == "SmartDPI.app" ]] || {
    print -u2 "Expected an existing SmartDPI.app. Build it with ./scripts/build-app.sh first."
    exit 1
}

task_check_app() {
    local task_check_dir="$1"
    local task_bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_check_dir/Contents/Info.plist")"
    local task_bundle_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$task_check_dir/Contents/Info.plist")"
    local task_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$task_check_dir/Contents/Info.plist")"
    [[ "$task_bundle_version" == "$task_version" ]] || {
        print -u2 "App version does not match source: $task_bundle_version / $task_version"
        return 1
    }
    [[ "$task_bundle_min" == "$task_min_os" && "$task_bundle_id" == "local.smartdpi.app" ]] || {
        print -u2 "Unexpected minimum system version or bundle identifier."
        return 1
    }
    [[ "$(/usr/bin/lipo -archs "$task_check_dir/Contents/MacOS/SmartDPI")" == "arm64" ]] || {
        print -u2 "Expected an Apple Silicon arm64 executable."
        return 1
    }
    /usr/bin/plutil -lint "$task_check_dir/Contents/Info.plist" >/dev/null
    /usr/bin/codesign --verify --deep --strict "$task_check_dir"
}

task_check_app "$task_app_dir"
[[ -f docs/INSTALLATION.html ]] || {
    print -u2 "Missing docs/INSTALLATION.html; the release must include the first-open guide."
    exit 1
}
mkdir -p "$task_output_dir"
task_stage="$(mktemp -d "$task_output_dir/.package.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT HUP INT TERM
task_archive="SmartDPI-$task_version-macOS-arm64.zip"
task_disk_image="SmartDPI-$task_version-macOS-arm64.dmg"

# Read the existing app without rebuilding, resigning, or touching a running bundle.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_app_dir" "$task_stage/$task_archive"
cp docs/INSTALLATION.html "$task_stage/INSTALLATION.html"
./scripts/create-dmg.sh "$task_app_dir" "$task_stage/$task_disk_image" "$task_stage/INSTALLATION.html"
cat > "$task_stage/INSTALL.txt" <<EOF
SmartDPI $task_version — macOS 安装与使用

系统要求
- Apple Silicon（M1 及后续 M 系列）；macOS $task_min_os 或更新版本。
- 可用分辨率、HiDPI 与刷新率取决于芯片、系统、显示器和连接。

安装
1. 推荐下载并打开 $task_disk_image。
2. 将 SmartDPI.app 拖入右侧“应用程序”，从“应用程序”打开。
   若使用 ZIP：解压 $task_archive，再将 App 拖入“应用程序”。
3. 点击顶部菜单栏的显示器图标，选择目标显示器。
4. 在统一列表中选择“1920 × 1080 · HiDPI 开”等模式，点击立即生效。
5. 刷新率可选“自动”，或选择该模式实际提供的频率。
6. 安装完成后，可在 Finder 边栏推出 SmartDPI 安装磁盘。

首次打开
此发布包仅使用临时（ad-hoc）签名，尚无 Apple Developer ID 签名或公证。
DMG 提供安装引导，不能代替 Apple 签名或公证。
若看到“无法验证开发者”“已损坏”或“移到废纸篓”等提示，先查看安装磁盘内
“安装说明.html”，或单独下载 INSTALLATION.html，按实际提示核对和处理。
仅在确认来源可信、校验正确，且系统提供对应入口时，在“系统设置 → 隐私与安全性”
选择“仍要打开”。若提示恶意软件、出现校验失败或没有允许入口，请停止安装。
组织管理的 Mac 可能限制此操作，请遵循设备管理策略。

使用与恢复
- 分辨率表示桌面“看起来像”的尺寸，不会增加显示器的物理像素。
- 2560 × 1440 面板选择 1920 × 1080 HiDPI 时，可能使用 3840 × 2160
  中间画布再缩放；显示器的物理像素仍然是 2560 × 1440。
- 优先使用系统已有模式。补充缺失 HiDPI 时使用实验性虚拟屏幕与系统镜像，
  因此系统设置中会出现 SmartDPI HiDPI；这时需要保持 App 运行。
- 不满意时点击“恢复原设置”。退出 App 会释放本工具的虚拟屏幕；
  已成功应用的普通系统模式不会仅因退出 App 自动撤销。
- 虚拟显示依赖未公开接口，系统更新可能影响可用性；无法保证每台 M 系列
  设备提供相同的分辨率或刷新率。若切换失败，请使用恢复入口。

校验下载
将 DMG、ZIP、INSTALL.txt、INSTALLATION.html 和 SHA256SUMS.txt 放在同一文件夹，运行：
    shasum -a 256 -c SHA256SUMS.txt
四个文件均显示 OK 后，说明下载内容与发布校验值一致。
只下载了 DMG 时，可运行 shasum -a 256 "$task_disk_image"，
与 SHA256SUMS.txt 中相同文件名对应的值逐字核对。
EOF

mkdir "$task_stage/check"
/usr/bin/ditto -x -k "$task_stage/$task_archive" "$task_stage/check"
task_check_app "$task_stage/check/SmartDPI.app"
(
    cd "$task_stage"
    /usr/bin/shasum -a 256 "$task_archive" "$task_disk_image" INSTALL.txt INSTALLATION.html > SHA256SUMS.txt
    /usr/bin/shasum -a 256 -c SHA256SUMS.txt
)

for task_file in "$task_archive" "$task_disk_image" INSTALL.txt INSTALLATION.html SHA256SUMS.txt; do
    mv -f "$task_stage/$task_file" "$task_output_dir/$task_file"
done
print "Release package ready: $task_output_dir/$task_archive"
print "Recommended guided installer: $task_output_dir/$task_disk_image"
cat "$task_output_dir/SHA256SUMS.txt"
