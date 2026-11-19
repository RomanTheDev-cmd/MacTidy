#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
# File providers can add Finder metadata to a bundle while it is being built.
local_temp=$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)
clamav_stage=$(/usr/bin/mktemp -d "${local_temp%/}/MacSpace-build.XXXXXX")
trap 'rm -rf "$clamav_stage"' EXIT
app="$clamav_stage/MacSpace.app"
project_dir=$(pwd -P)
output_dir="${MACTIDY_BUILD_OUTPUT_DIR:-$project_dir}"
project_link=""
if [[ -z "${MACTIDY_BUILD_OUTPUT_DIR:-}" && "$project_dir" == "$HOME/Library/Mobile Documents/"* ]]; then
    project_hash=$(print -rn -- "$project_dir" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
    output_dir="$HOME/Library/Caches/MacSpace/Builds/$project_hash"
    project_link="$project_dir/MacSpace.app"
    mkdir -p "$output_dir"
fi
destination="$output_dir/MacSpace.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -X Source/Info.plist "$app/Contents/Info.plist"
cp -X Source/PrivacyInfo.xcprivacy "$app/Contents/Resources/PrivacyInfo.xcprivacy"
cp -RX Localization "$app/Contents/Resources/"
clamav_version=1.5.4
clamav_sha256=df7fa753e2f9f67f3bc99b2a40a3be7ef559088c68ad6bdf66b4b5764e965bd6
clamav_url="https://github.com/Cisco-Talos/clamav/releases/download/clamav-$clamav_version/clamav-$clamav_version.macos.universal.pkg"
clamav_cache="${TMPDIR:-/tmp}/MacSpace-clamav-$clamav_version.macos.universal.pkg"
actual_sha256=""
if [[ -f "$clamav_cache" ]]; then actual_sha256=$(/usr/bin/shasum -a 256 "$clamav_cache" | /usr/bin/awk '{print $1}'); fi
if [[ "$actual_sha256" != "$clamav_sha256" ]]; then
    /usr/bin/curl --fail --location --retry 3 --output "$clamav_cache" "$clamav_url"
    actual_sha256=$(/usr/bin/shasum -a 256 "$clamav_cache" | /usr/bin/awk '{print $1}')
    if [[ "$actual_sha256" != "$clamav_sha256" ]]; then
        /bin/rm -f "$clamav_cache"
        print -u2 "ClamAV package checksum mismatch."
        exit 1
    fi
fi
/usr/sbin/pkgutil --expand-full "$clamav_cache" "$clamav_stage/expanded"
clamav_scanner=$(/usr/bin/find "$clamav_stage/expanded" -type f -path '*/bin/clamscan' -print -quit)
if [[ -z "$clamav_scanner" ]]; then print -u2 "ClamAV package does not contain clamscan."; exit 1; fi
clamav_prefix="${clamav_scanner%/bin/clamscan}"
if [[ ! -x "$clamav_prefix/bin/freshclam" ]]; then print -u2 "ClamAV package does not contain freshclam."; exit 1; fi
clamav_library=$(/usr/bin/find "$clamav_stage/expanded" -type f -path '*/lib/libclamav.*.dylib' -print -quit)
if [[ -z "$clamav_library" ]]; then print -u2 "ClamAV package does not contain libclamav."; exit 1; fi
clamav_library_prefix="${clamav_library%/lib/*}"
clamav_bundle="$app/Contents/Resources/ClamAV"
/bin/mkdir -p "$clamav_bundle/bin" "$clamav_bundle/lib" "$clamav_bundle/etc"
# Ship the two tools MacSpace runs, their runtime libraries, and CVD trust
# certificates. The upstream package also contains development archives and
# utilities that would add substantial size without helping users.
/bin/cp -Xp "$clamav_prefix/bin/clamscan" "$clamav_prefix/bin/freshclam" "$clamav_bundle/bin/"
if [[ ! -d "$clamav_prefix/etc/certs" ]]; then print -u2 "ClamAV package does not contain CVD certificates."; exit 1; fi
/usr/bin/ditto --noextattr --norsrc "$clamav_prefix/etc/certs" "$clamav_bundle/etc/certs"
for library in "$clamav_library_prefix"/lib/*.dylib; do
    [[ -e "$library" ]] || continue
    if [[ -L "$library" ]]; then
        /bin/ln -s "$(/usr/bin/readlink "$library")" "$clamav_bundle/lib/$(/usr/bin/basename "$library")"
    elif [[ -f "$library" ]]; then
        /bin/cp -Xp "$library" "$clamav_bundle/lib/"
    fi
done
# Cisco Talos builds these binaries with an absolute /usr/local/clamav/lib
# rpath. Replace it with bundle-relative rpaths so the embedded engine loads only its own dylibs.
for binary in "$clamav_bundle"/bin/*; do
    [[ -f "$binary" && ! -L "$binary" ]] || continue
    if /usr/bin/file "$binary" | /usr/bin/grep -q 'Mach-O'; then
        if /usr/bin/lipo -info "$binary" | /usr/bin/grep -q 'Architectures in the fat file'; then
            /usr/bin/lipo "$binary" -thin "$(uname -m)" -output "$binary.thin"
            /bin/mv "$binary.thin" "$binary"
        fi
        # Drop the upstream rpath so a separately installed ClamAV is never loaded.
        while /usr/bin/otool -l "$binary" | /usr/bin/grep -Fq 'path /usr/local/clamav/lib '; do
            /usr/bin/install_name_tool -delete_rpath '/usr/local/clamav/lib' "$binary"
        done
        if ! /usr/bin/otool -l "$binary" | /usr/bin/grep -Fq 'path @executable_path/../lib'; then
            /usr/bin/install_name_tool -add_rpath '@executable_path/../lib' "$binary"
        fi
        /usr/bin/codesign --force --sign - "$binary"
    fi
done
for library in "$clamav_bundle"/lib/*.dylib; do
    [[ -f "$library" && ! -L "$library" ]] || continue
    if /usr/bin/file "$library" | /usr/bin/grep -q 'Mach-O'; then
        if /usr/bin/lipo -info "$library" | /usr/bin/grep -q 'Architectures in the fat file'; then
            /usr/bin/lipo "$library" -thin "$(uname -m)" -output "$library.thin"
            /bin/mv "$library.thin" "$library"
        fi
        while /usr/bin/otool -l "$library" | /usr/bin/grep -Fq 'path /usr/local/clamav/lib '; do
            /usr/bin/install_name_tool -delete_rpath '/usr/local/clamav/lib' "$library"
        done
        if ! /usr/bin/otool -l "$library" | /usr/bin/grep -Fq 'path @loader_path'; then
            /usr/bin/install_name_tool -add_rpath '@loader_path' "$library"
        fi
        /usr/bin/codesign --force --sign - "$library"
    fi
done
/bin/cp -X ThirdParty/ClamAV/COPYING.txt ThirdParty/ClamAV/NOTICE.md "$app/Contents/Resources/"
swiftc -O -swift-version 5 -parse-as-library Source/Localization.swift Source/Core.swift Source/Weekly.swift Source/Audit.swift Source/Applications.swift Source/Storage.swift Source/DiskAudit.swift Source/DiskAuditView.swift Source/CloudLocal.swift Source/CloudLocalView.swift Source/PermissionGuide.swift Source/Antivirus.swift Source/AntivirusView.swift Source/StorageView.swift Source/Updates.swift Source/TranslationSupport.swift Source/ApplicationsView.swift Source/MacTidy.swift -o "$app/Contents/MacOS/MacSpace" -framework SwiftUI -framework AppKit -framework CoreServices -Xlinker -weak_framework -Xlinker Translation -target "$(uname -m)-apple-macosx13.0"
cp -X Assets/MacSpace.icns "$app/Contents/Resources/MacSpaceIcon.icns"
helper="$app/Contents/Library/LoginItems/MacTidyHelper.app"
mkdir -p "$helper/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library Source/Localization.swift Source/Core.swift Source/Weekly.swift Source/WeeklyMain.swift -o "$helper/Contents/MacOS/MacTidyHelper" -framework Foundation -target "$(uname -m)-apple-macosx13.0"
mkdir -p "$helper/Contents/Resources"
cp -RX Localization "$helper/Contents/Resources/"
cp -X Source/HelperInfo.plist "$helper/Contents/Info.plist"
cp -X Source/PrivacyInfo.xcprivacy "$helper/Contents/Resources/PrivacyInfo.xcprivacy"
for locale in Source/*.lproj; do
    cp -RX "$locale" "$app/Contents/Resources/"
    cp -RX "$locale" "$helper/Contents/Resources/"
    printf '\n"CFBundleDisplayName" = "MacSpace Helper";\n"CFBundleName" = "MacSpace Helper";\n' >> "$helper/Contents/Resources/$(basename "$locale")/InfoPlist.strings"
done
# The PKG installs the app as root. Files that only their owner can read (for example a source file
# saved with mode 600) would leave MacSpace unable to read its own texts and Info.plist.
/bin/chmod -R u+rwX,go+rX-w "$app"
unreadable=$(/usr/bin/find "$app" ! -perm -o=r -print)
if [[ -n "$unreadable" ]]; then print -u2 "Files not readable by everyone:\n$unreadable"; exit 1; fi
codesign --force --sign - "$helper"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"

# Keep the previous local build recoverable if publishing the new bundle fails.
backup_build() {
    local backup
    backup=$(/usr/bin/mktemp -d "$HOME/.Trash/MacSpace-build.XXXXXX") || return 1
    /bin/mv "$1" "$backup/MacSpace.app" || return 1
    print -r -- "$backup/MacSpace.app"
}
previous_app=""
if [[ -e "$destination" || -L "$destination" ]]; then
    previous_app=$(backup_build "$destination")
fi
if ! /bin/mv "$app" "$destination"; then
    if [[ -n "$previous_app" ]]; then /bin/mv "$previous_app" "$destination"; fi
    exit 1
fi
if ! codesign --verify --deep --strict "$destination"; then
    /bin/mv "$destination" "$app"
    if [[ -n "$previous_app" ]]; then /bin/mv "$previous_app" "$destination"; fi
    exit 1
fi
if [[ -n "$project_link" && "$(/usr/bin/readlink "$project_link" 2>/dev/null || true)" != "$destination" ]]; then
    previous_link=""
    if [[ -e "$project_link" || -L "$project_link" ]]; then
        previous_link=$(backup_build "$project_link")
    fi
    if ! /bin/ln -s "$destination" "$project_link"; then
        if [[ -n "$previous_link" ]]; then /bin/mv "$previous_link" "$project_link"; fi
        exit 1
    fi
fi
print -r -- "${project_link:-$destination}"
