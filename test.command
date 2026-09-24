#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -D TESTING -swift-version 5 -parse-as-library Source/Localization.swift Source/Core.swift Source/Weekly.swift Source/Audit.swift Source/Applications.swift Source/Updates.swift Source/TranslationSupport.swift Source/ApplicationsView.swift Source/MacTidy.swift Source/ScannerTests.swift -o "$test_dir/tests" -framework SwiftUI -framework AppKit -framework CoreServices -Xlinker -weak_framework -Xlinker Translation -target "$(uname -m)-apple-macosx13.0"
MACTIDY_LOCALIZATION_DIR="$PWD/Localization" "$test_dir/tests"
