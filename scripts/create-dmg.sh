#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

if (( $# < 2 || $# > 3 )); then
    print -u2 "Usage: $0 SmartDPI.app output.dmg [installation-guide.html]"
    exit 2
fi

task_app_dir="${1:A}"
task_output="${2:A}"
task_guide="${3:-$PWD/docs/INSTALLATION.html}"
task_guide="${task_guide:A}"
[[ -d "$task_app_dir" && "${task_app_dir:t}" == "SmartDPI.app" ]] || {
    print -u2 "Expected an existing SmartDPI.app."
    exit 1
}
[[ -f "$task_guide" && "$task_output" == *.dmg ]] || {
    print -u2 "Expected an HTML installation guide and a .dmg output path."
    exit 1
}
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app_dir/Contents/Info.plist")"
[[ "$task_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || {
    print -u2 "Invalid app version: $task_version"
    exit 1
}
/usr/bin/codesign --verify --deep --strict "$task_app_dir"
mkdir -p "${task_output:h}"
task_stage="$(mktemp -d "${TMPDIR:-/tmp}/smartdpi-dmg.XXXXXX")"
task_mount="$task_stage/mount"
task_mounted=0
task_cleanup() {
    if (( task_mounted )); then
        /usr/bin/hdiutil detach "$task_mount" -quiet || /usr/bin/hdiutil detach "$task_mount" -force -quiet || true
    fi
    rm -rf "$task_stage"
}
trap task_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

mkdir "$task_mount"
/usr/bin/hdiutil create -size 128m -fs HFS+ -volname "SmartDPI $task_version" \
    -type UDIF "$task_stage/edit.dmg" -quiet
/usr/bin/hdiutil attach "$task_stage/edit.dmg" -mountpoint "$task_mount" \
    -nobrowse -noautoopen -quiet
task_mounted=1
/usr/bin/ditto "$task_app_dir" "$task_mount/SmartDPI.app"
ln -s /Applications "$task_mount/Applications"
cp "$task_guide" "$task_mount/安装说明.html"
mkdir "$task_mount/.background"
mkdir -p "$PWD/.build/ModuleCache"
/usr/bin/xcrun swiftc -target arm64-apple-macos13.0 -module-cache-path "$PWD/.build/ModuleCache" \
    scripts/render-installer-background.swift -o "$task_stage/render-background"
"$task_stage/render-background" "$task_mount/.background/background.png"

# Configure only this newly mounted volume's window. Do not change global Finder preferences.
/usr/bin/osascript - "$task_mount" <<'APPLESCRIPT'
on run arguments
    set installationDisk to (POSIX file (item 1 of arguments)) as alias
    tell application "Finder"
        set installationDisk to folder installationDisk
        open installationDisk
        tell container window of installationDisk
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {160, 100, 840, 635}
        end tell
        set windowOptions to icon view options of container window of installationDisk
        set arrangement of windowOptions to not arranged
        set icon size of windowOptions to 96
        set text size of windowOptions to 13
        set background picture of windowOptions to file ".background:background.png" of installationDisk
        set position of item "SmartDPI.app" of installationDisk to {170, 180}
        set position of item "Applications" of installationDisk to {510, 180}
        set position of item "安装说明.html" of installationDisk to {340, 390}
        update installationDisk without registering applications
        delay 1
        close container window of installationDisk
    end tell
end run
APPLESCRIPT

[[ -s "$task_mount/.DS_Store" ]] || {
    print -u2 "Finder did not save the installation window layout."
    exit 1
}
/usr/bin/codesign --verify --deep --strict "$task_mount/SmartDPI.app"
/bin/sync
/usr/bin/hdiutil detach "$task_mount" -quiet
task_mounted=0
/usr/bin/hdiutil convert "$task_stage/edit.dmg" -format UDZO -imagekey zlib-level=9 \
    -o "$task_stage/final.dmg" -quiet
/usr/bin/hdiutil verify "$task_stage/final.dmg" -quiet

# Reopen the finished read-only image, validating what a downloader receives.
/usr/bin/hdiutil attach "$task_stage/final.dmg" -readonly -mountpoint "$task_mount" \
    -nobrowse -noautoopen -quiet
task_mounted=1
[[ "$(readlink "$task_mount/Applications")" == /Applications ]]
cmp -s "$task_guide" "$task_mount/安装说明.html"
[[ -s "$task_mount/.DS_Store" && -s "$task_mount/.background/background.png" ]]
/usr/bin/codesign --verify --deep --strict "$task_mount/SmartDPI.app"
/usr/bin/hdiutil detach "$task_mount" -quiet
task_mounted=0
mv -f "$task_stage/final.dmg" "$task_output"
print "Guided disk image ready: $task_output"
