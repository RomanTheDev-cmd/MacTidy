#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p MacSpace.app/Contents/MacOS MacSpace.app/Contents/Resources
cp Source/Info.plist MacSpace.app/Contents/Info.plist
cp Source/PrivacyInfo.xcprivacy MacSpace.app/Contents/Resources/PrivacyInfo.xcprivacy
cp -R Localization MacSpace.app/Contents/Resources/
swiftc -O -swift-version 5 -parse-as-library Source/Localization.swift Source/Core.swift Source/Weekly.swift Source/Audit.swift Source/Applications.swift Source/Storage.swift Source/DiskAudit.swift Source/DiskAuditView.swift Source/CloudLocal.swift Source/CloudLocalView.swift Source/PermissionGuide.swift Source/StorageView.swift Source/Updates.swift Source/TranslationSupport.swift Source/ApplicationsView.swift Source/MacTidy.swift -o MacSpace.app/Contents/MacOS/MacSpace -framework SwiftUI -framework AppKit -framework CoreServices -Xlinker -weak_framework -Xlinker Translation -target "$(uname -m)-apple-macosx13.0"
mkdir -p MacSpace.app/Contents/Resources
rm -f MacSpace.app/Contents/Resources/MacTidyGraphite.icns MacSpace.app/Contents/Resources/MacTidy.icns
cp Assets/MacTidy.icns MacSpace.app/Contents/Resources/MacTidyBlueSilver.icns
helper="MacSpace.app/Contents/Library/LoginItems/MacTidyHelper.app"
mkdir -p "$helper/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library Source/Localization.swift Source/Core.swift Source/Weekly.swift Source/WeeklyMain.swift -o "$helper/Contents/MacOS/MacTidyHelper" -framework Foundation -target "$(uname -m)-apple-macosx13.0"
mkdir -p "$helper/Contents/Resources"
cp -R Localization "$helper/Contents/Resources/"
cp Source/HelperInfo.plist "$helper/Contents/Info.plist"
cp Source/PrivacyInfo.xcprivacy "$helper/Contents/Resources/PrivacyInfo.xcprivacy"
for locale in Source/*.lproj; do
    cp -R "$locale" MacSpace.app/Contents/Resources/
    cp -R "$locale" "$helper/Contents/Resources/"
    printf '\n"CFBundleDisplayName" = "MacSpace Helper";\n"CFBundleName" = "MacSpace Helper";\n' >> "$helper/Contents/Resources/$(basename "$locale")/InfoPlist.strings"
done
codesign --force --sign - "$helper"
codesign --force --sign - MacSpace.app
