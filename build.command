#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p MacTidy.app/Contents/MacOS MacTidy.app/Contents/Resources
cp Source/Info.plist MacTidy.app/Contents/Info.plist
cp -R Localization MacTidy.app/Contents/Resources/
swiftc -O -swift-version 5 -parse-as-library Source/Localization.swift Source/Core.swift Source/Weekly.swift Source/Audit.swift Source/Applications.swift Source/Storage.swift Source/StorageView.swift Source/Updates.swift Source/TranslationSupport.swift Source/ApplicationsView.swift Source/MacTidy.swift -o MacTidy.app/Contents/MacOS/MacTidy -framework SwiftUI -framework AppKit -framework CoreServices -Xlinker -weak_framework -Xlinker Translation -target "$(uname -m)-apple-macosx13.0"
mkdir -p MacTidy.app/Contents/Resources
rm -f MacTidy.app/Contents/Resources/MacTidyGraphite.icns MacTidy.app/Contents/Resources/MacTidy.icns
cp Assets/MacTidy.icns MacTidy.app/Contents/Resources/MacTidyBlueSilver.icns
helper="MacTidy.app/Contents/Library/LoginItems/MacTidyHelper.app"
mkdir -p "$helper/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library Source/Localization.swift Source/Core.swift Source/Weekly.swift Source/WeeklyMain.swift -o "$helper/Contents/MacOS/MacTidyHelper" -framework Foundation -target "$(uname -m)-apple-macosx13.0"
mkdir -p "$helper/Contents/Resources"
cp -R Localization "$helper/Contents/Resources/"
cp Source/HelperInfo.plist "$helper/Contents/Info.plist"
for locale in Source/*.lproj; do
    cp -R "$locale" MacTidy.app/Contents/Resources/
    cp -R "$locale" "$helper/Contents/Resources/"
done
codesign --force --sign - "$helper"
codesign --force --sign - MacTidy.app
