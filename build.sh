#!/bin/zsh
set -euo pipefail
task_root="${0:A:h}"
task_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$task_root/Source/Info.plist")"
task_app="$task_root/Wall Note $task_version.app"
task_build="$(mktemp -d "${TMPDIR:-/tmp/}wallnote-build.XXXXXX")"
trap 'rm -rf "$task_build"' EXIT
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
xcrun swiftc -swift-version 5 -O -whole-module-optimization \
    -module-cache-path "$task_build/ModuleCache" \
    -target arm64-apple-macosx13.0 \
    -framework AppKit -framework SwiftUI -framework Carbon \
    "$task_root/Source/Models.swift" "$task_root/Source/MemoStore.swift" "$task_root/Source/PanelPlacement.swift" "$task_root/Source/SidebarLayout.swift" "$task_root/Source/WallNote.swift" \
    -o "$task_app/Contents/MacOS/WallNote"
cp "$task_root/Source/Info.plist" "$task_app/Contents/Info.plist"
xcrun swift -module-cache-path "$task_build/ModuleCache" "$task_root/Source/MakeIcon.swift" "$task_build/AppIcon.iconset" "$task_app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$task_app"
print "Built: $task_app"
