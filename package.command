#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
./build.command
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Source/Info.plist)
arch=$(uname -m)
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/root/Applications" dist
/usr/bin/ditto --noextattr --norsrc MacSpace.app "$staging/root/Applications/MacSpace.app"
mkdir -p "$staging/scripts"
cat > "$staging/scripts/postinstall" <<'SH'
#!/bin/sh
set -eu
apps="${3:-/}/Applications"
new="$apps/MacSpace.app"
old="$apps/MacTidy.app"
plist=/usr/libexec/PlistBuddy
if [ -d "$new" ] && [ "$("$plist" -c 'Print CFBundleIdentifier' "$new/Contents/Info.plist" 2>/dev/null || true)" = 'local.mactidy.cleaner' ]; then
    if [ -d "$old" ] && [ ! -L "$old" ] && [ "$("$plist" -c 'Print CFBundleIdentifier' "$old/Contents/Info.plist" 2>/dev/null || true)" = 'local.mactidy.cleaner' ]; then
        /bin/rm -rf "$old"
    fi
    if [ ! -e "$old" ] && [ ! -L "$old" ]; then
        /bin/ln -s MacSpace.app "$old"
    fi
    if [ -L "$old" ] && [ "$(/usr/bin/readlink "$old")" = 'MacSpace.app' ]; then
        /usr/bin/chflags -h hidden "$old" || true
    fi
fi
exit 0
SH
/bin/chmod 755 "$staging/scripts/postinstall"
# A fixed destination avoids installing into a previously registered build folder.
/usr/bin/pkgbuild --analyze --root "$staging/root" "$staging/components.plist"
/usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$staging/components.plist"
/usr/bin/pkgbuild --root "$staging/root" --scripts "$staging/scripts" --component-plist "$staging/components.plist" --identifier local.mactidy.cleaner.pkg --version "$version" --install-location / "$staging/MacTidy-component.pkg"
cat > "$staging/Distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>MacSpace $version</title>
  <options customize="never" require-scripts="false" hostArchitectures="$arch"/>
  <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
  <volume-check><allowed-os-versions><os-version min="13.0"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="default"/></choices-outline>
  <choice id="default" visible="false" title="MacSpace"><pkg-ref id="local.mactidy.cleaner.pkg"/></choice>
  <pkg-ref id="local.mactidy.cleaner.pkg" version="$version" onConclusion="none">MacTidy-component.pkg</pkg-ref>
</installer-gui-script>
XML
/usr/bin/productbuild --distribution "$staging/Distribution.xml" --package-path "$staging" "dist/MacSpace-$version-$arch.pkg"
(cd dist && /usr/bin/shasum -a 256 "MacSpace-$version-$arch.pkg" > "MacSpace-$version-$arch.pkg.sha256")
# Older installations look for the original asset name. Publish the same package
# under that name as well so their built-in updater can migrate to MacSpace.
/bin/cp "dist/MacSpace-$version-$arch.pkg" "dist/MacTidy-$version-$arch.pkg"
(cd dist && /usr/bin/shasum -a 256 "MacTidy-$version-$arch.pkg" > "MacTidy-$version-$arch.pkg.sha256")

if [[ -n "${MACTIDY_SIGNING_KEY:-}" ]]; then
    swift Tools/sign-release.swift "$MACTIDY_SIGNING_KEY" "dist/MacSpace-$version-$arch.pkg" "dist/MacSpace-$version-$arch.pkg.sig"
    /bin/cp "dist/MacSpace-$version-$arch.pkg.sig" "dist/MacTidy-$version-$arch.pkg.sig"
fi
