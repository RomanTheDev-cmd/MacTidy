# MacTidy

A native macOS app for finding large files, reviewing clutter, and moving selected items to Trash. A simple first screen with one Scan button, a separate window for reviewing rarely used applications, and an optional weekly Downloads cleanup.

[Русская документация](README.ru.md) · [Download installer](https://github.com/RomanTheDev-cmd/MacTidy/releases/latest)

## Install

1. Download **MacTidy-2.4.0-arm64.pkg** from [Releases](https://github.com/RomanTheDev-cmd/MacTidy/releases/latest).
2. Double-click the installer and follow the standard macOS installation steps.
3. Open **MacTidy** in **Applications**.

The standalone installer places the app in `/Applications`. It does not run a cleanup, enable a schedule, or require developer tools. Quit MacTidy before updating. Existing preferences and an enabled schedule are preserved.

The prebuilt installer requires **Apple Silicon (M1 or newer) and macOS 13+**. The app is ad-hoc signed; the installer is unsigned and the release is not Apple-notarized. macOS may block it. After attempting to open the downloaded installer, use **System Settings → Privacy & Security → Open Anyway** if available and you trust this release. Managed Macs may disallow this. No Developer ID certificate is included.

## What it does

- Reviews application caches, logs older than 30 days, downloaded installers and archives, old downloads, Xcode DerivedData, and large files in a chosen folder.
- Starts with one Scan button. After the scan, review a clean list, choose files, then confirm Move to Trash. Search, sorting, exclusions and Finder reveal remain available.
- Deduplicates overlapping results and rechecks files before moving them.
- The Applications window follows the same flow: scan first, then review apps unused for 30, 90, or 180 days using Spotlight history. Missing history is separate; running applications and MacTidy itself are protected. Only the app bundle is moved; documents and settings remain.
- The Storage by Type window estimates space used by photos, videos, audio, documents, installers, archives, apps, and other files. Select a category to review individual files, including installer packages, or open the dedicated app review. Up to three apps not opened for 90 days are suggested in the app category; none are selected automatically. Unknown files, system data, and protected folders are read-only.
- Optionally moves **everything in Downloads, including new files, hidden files, and whole folders**, to Trash every Sunday at 12:00 local time. This requires explicit opt-in. Trash is never emptied.
- Uses native glass on macOS 26+, standard materials on earlier versions, and the system appearance. The monochrome icon has a transparent background.

Cleanup always needs judgment: old or large files can still be valuable. Close relevant apps before clearing caches and close Xcode before clearing DerivedData. Disk space figures are estimates; APFS sharing, snapshots and cloud files affect actual reclaimed space.

## Updates

MacTidy checks the latest GitHub release when its main window opens. If a newer version is available, it downloads the matching Apple Silicon installer, checks GitHub's SHA-256 digest and verifies the release's Ed25519 signature against the public key built into the app. It then opens the macOS Installer once for that version. Complete the normal Installer steps, including administrator authorization if requested. The app cannot silently bypass macOS installation approval. If you defer the installation, use **Settings → Check for updates → Open installer** later.

Only releases with a matching signed `.pkg` are offered. The update check contacts GitHub; it does not send scanned file names or contents. Official release packages include a detached `.pkg.sig` file. `package.command` can produce the same signature for a release maintainer when `MACTIDY_SIGNING_KEY` points to the private key matching `UpdateVerifier.officialPublicKey`; keep that private key outside the repository. Locally built packages without this signature can still be installed manually, but the in-app updater will reject them.

## Languages and privacy

The app follows the first preferred system/app language. English, Russian, German, Spanish, Italian, Vietnamese, Polish and Indonesian are bundled. Additional languages supported by Apple's Translation framework can be translated on macOS 15+ after the system requests any necessary language-model download. Unsupported languages and declined/unavailable translation fall back to English. Arabic and Hebrew use right-to-left layout. A restart applies system-language changes.

Additional bundled translations were machine translated and may need corrections. This is not a claim of complete support for every language. Only the fixed interface labels are passed to Apple's translation framework; scanned names, paths and file contents are not translated or uploaded. There is no analytics or external translation service.

## Weekly schedule

The per-user LaunchAgent works after login even while MacTidy is closed. A missed sleep-time event may run on wake; no immediate cleanup runs when enabling the option. Folder access restrictions can prevent the helper from moving files; the app shows the last report.

- Helper: `~/Library/Application Support/MacTidy/MacTidyHelper.app`
- Schedule: `~/Library/LaunchAgents/local.mactidy.weekly-downloads.plist`
- Report: `~/Library/Application Support/MacTidy/weekly-report.json`

Disable the weekly option **before uninstalling**. Then move `/Applications/MacTidy.app` to Trash. Updating the main app preserves the existing helper; toggle the schedule off and on if you want to install the updated helper.

## Build and test

Requires Apple Command Line Tools with Swift and the macOS 26+ SDK. There are no third-party dependencies.

```sh
git clone https://github.com/RomanTheDev-cmd/MacTidy.git
cd MacTidy
./build.command
./test.command
./package.command
```

`build.command` produces `MacTidy.app` for the current Mac's architecture. `package.command` builds a standalone `.pkg` in `dist/` and its SHA-256 checksum. Published releases are Apple Silicon; Intel builds have not been verified.

Tests cover scanning, cancellation, symlinks, changed metadata, storage categories, selected-category cleanup, recursive cache changes, deduplication, exclusions, application-removal guards, scheduling, and localization catalogs. The real Trash test only moves and restores a generated temporary fixture.

## Source layout

`Source/` contains the SwiftUI app, scanner, helper and regression tests. `Localization/` contains JSON interface catalogs. `Assets/` contains the transparent icon source and macOS icon bundle. Contributions and translation corrections are welcome through issues and pull requests.

## License

[MIT](LICENSE).
