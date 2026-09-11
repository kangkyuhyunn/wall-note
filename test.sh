#!/bin/zsh
set -euo pipefail
task_root="${0:A:h}"
task_build="$(mktemp -d "${TMPDIR:-/tmp/}wallnote-tests.XXXXXX")"
trap 'rm -rf "$task_build"' EXIT
xcrun swiftc -module-cache-path "$task_build/ModuleCache" \
    "$task_root/Source/Models.swift" "$task_root/Source/StorageTests.swift" -o "$task_build/storage-tests"
"$task_build/storage-tests"
xcrun swiftc -module-cache-path "$task_build/ModuleCache" \
    "$task_root/Source/Models.swift" "$task_root/Source/MemoStore.swift" "$task_root/Source/StoreTests.swift" -o "$task_build/store-tests"
"$task_build/store-tests"
xcrun swiftc -module-cache-path "$task_build/ModuleCache" \
    "$task_root/Source/Models.swift" "$task_root/Source/PanelPlacement.swift" "$task_root/Source/PanelPlacementTests.swift" -o "$task_build/placement-tests"
"$task_build/placement-tests"
xcrun swiftc -module-cache-path "$task_build/ModuleCache" \
    "$task_root/Source/Models.swift" "$task_root/Source/MemoStore.swift" "$task_root/Source/PanelPlacement.swift" \
    "$task_root/Source/SidebarLayout.swift" "$task_root/Source/SidebarLayoutTests.swift" -o "$task_build/layout-tests"
"$task_build/layout-tests"
