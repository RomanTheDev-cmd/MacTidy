#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swift_options=(-swift-version 5 -parse-as-library -target "$(uname -m)-apple-macosx13.0")
app_sources=(
    Source/Localization.swift Source/Core.swift Source/Weekly.swift Source/Audit.swift
    Source/Applications.swift Source/Storage.swift Source/DiskAudit.swift Source/DiskAuditView.swift
    Source/CloudLocal.swift Source/CloudLocalView.swift Source/PermissionGuide.swift
    Source/Antivirus.swift Source/AntivirusView.swift Source/StorageView.swift Source/Updates.swift
    Source/TranslationSupport.swift Source/ApplicationsView.swift Source/MacTidy.swift
)
swiftc -typecheck "${swift_options[@]}" "${app_sources[@]}"
swiftc -typecheck "${swift_options[@]}" Source/Localization.swift Source/Core.swift Source/Weekly.swift Source/WeeklyMain.swift
print 'Application and helper pass the Swift type check'
swiftc -D TESTING "${swift_options[@]}" "${app_sources[@]}" Source/ScannerTests.swift -o "$test_dir/tests" \
    -framework SwiftUI -framework AppKit -framework CoreServices -Xlinker -weak_framework -Xlinker Translation
MACTIDY_LOCALIZATION_DIR="$PWD/Localization" "$test_dir/tests"
