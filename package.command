#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
./build.command
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Source/Info.plist)
arch=$(uname -m)
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/root/Applications" dist
/usr/bin/ditto --noextattr --norsrc MacTidy.app "$staging/root/Applications/MacTidy.app"
# A fixed destination avoids installing into a previously registered build folder.
/usr/bin/pkgbuild --analyze --root "$staging/root" "$staging/components.plist"
/usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$staging/components.plist"
/usr/bin/pkgbuild --root "$staging/root" --component-plist "$staging/components.plist" --identifier local.mactidy.cleaner.pkg --version "$version" --install-location / "$staging/MacTidy-component.pkg"
cat > "$staging/Distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>MacTidy $version</title>
  <options customize="never" require-scripts="false" hostArchitectures="$arch"/>
  <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
  <volume-check><allowed-os-versions><os-version min="13.0"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" visible="false" title="MacTidy"><pkg-ref id="local.mactidy.cleaner.pkg"/></choice>
  <pkg-ref id="local.mactidy.cleaner.pkg" version="$version" onConclusion="none">MacTidy-component.pkg</pkg-ref>
</installer-gui-script>
XML
/usr/bin/productbuild --distribution "$staging/Distribution.xml" --package-path "$staging" "dist/MacTidy-$version-$arch.pkg"
(cd dist && /usr/bin/shasum -a 256 "MacTidy-$version-$arch.pkg" > "MacTidy-$version-$arch.pkg.sha256")
