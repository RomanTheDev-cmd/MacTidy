# MacSpace

A native macOS app for finding large files, reviewing clutter, and moving selected items to Trash. A simple first screen with one Scan button, an Applications tab for reviewing rarely used apps, and an optional daily, weekly, or monthly Downloads cleanup.

[Русская документация](README.ru.md) · [Download installer](https://github.com/RomanTheDev-cmd/MacTidy/releases/latest)

## Install

1. Download **MacSpace-3.0.3-arm64.pkg** from [Releases](https://github.com/RomanTheDev-cmd/MacTidy/releases/latest).
2. Double-click the installer and follow the standard macOS installation steps.
3. Open **MacSpace** in **Applications**.

The standalone installer places the app in `/Applications`. It does not run a cleanup, enable a schedule, or require developer tools. Quit MacSpace before updating. Existing preferences and an enabled schedule are preserved. The installer replaces the old MacTidy app and keeps a hidden compatibility link for existing Dock shortcuts.

MacSpace starts without a setup wizard and scans files it can access. For protected folders, the access guide in analysis settings opens **System Settings → Privacy & Security → Full Disk Access**. macOS requires you to grant that access yourself; an installer cannot grant it. Restart MacSpace after changing Full Disk Access.

If scheduled Downloads cleanup is enabled, **MacSpace Helper** is a separate app and also needs file access. The guide then offers **Show helper** so you can add it in the same Full Disk Access pane. Without that access, scheduled cleanup may fail and will report the error rather than removing files.

The prebuilt installer requires **Apple Silicon (M1 or newer) and macOS 13+**.

### If macOS says the installer "was not opened"

On first launch macOS may show: *"MacSpace-…-arm64.pkg" was not opened — Apple could not verify that it is free of malware.* This is expected and does not mean the file is harmful. **Do not click Move to Trash.**

1. Click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the **Security** section. Next to the message about "MacSpace-…-arm64.pkg", click **Open Anyway**.
4. Confirm with your password or Touch ID, then click **Open** once more. The installer starts.

You only need to do this once. After installation, MacSpace opens and updates without this warning.

**Why this happens.** Apple shows this warning for every app that is not notarized — checked and countersigned by Apple using a paid Apple Developer certificate ($99 per year). MacSpace is a free independent project and doesn't use that paid certificate yet. Instead, every release is signed with the project's own key, and the app checks that signature before installing an update, so updates can't be tampered with. On Macs managed by an organization, an administrator may disable **Open Anyway**.

## What it does

- Reviews application caches, logs older than 30 days, downloaded installers and archives, old downloads, Xcode DerivedData, and large files in a chosen folder.
- Starts with one Scan button. After the scan, review a clean list, choose files, then confirm Move to Trash. Search, sorting, exclusions and Finder reveal remain available.
- Deduplicates overlapping results and rechecks files before moving them.
- The storage window has a **What you can free up** button: it lists specific large personal files, eligible user app-data folders, and removable content inside third-party shared folders such as `/Library/Arturia`. Each row has Finder and Trash actions. A confirmation explains the impact, and MacSpace checks the path, identity, and access again before moving the item. System folders, the broad Users total, and protected Apple data are not in this cleanup list. Figures are approximate because APFS snapshots, shared blocks and access restrictions affect totals.
- The **More** menu in the storage window opens a separate **Local iCloud copies** view. It lists only files already uploaded to iCloud with a downloaded local copy. Its **Remove Download** action uses macOS to evict only the local copy after confirmation; the cloud original stays. Ordinary Trash cleanup and the scheduled Downloads task skip iCloud items. iCloud may download a file again when it is opened.
- The **Applications** tab, next to Cleanup and Antivirus in the main window, follows the same flow: scan first, then review apps unused for 30, 90, or 180 days using Spotlight history. Missing history is separate; running applications and MacSpace itself are protected. Apps in restricted folders remain selectable; macOS asks for administrator authorization when it is needed to move the selected apps to Trash. Only the app bundle is moved; documents and settings remain.
- The Storage by Type window estimates space used by photos, videos, audio, documents, installers, archives, apps, and other files. Select any personal-file category, including Other Files, to review individual files and move only selected items to Trash. System and protected folders remain excluded. The Applications category suggests up to three apps not opened for 90 days and opens the dedicated app review. Available space includes an estimate of space macOS can reclaim automatically, matching System Settings; local snapshots and APFS sharing can make the immediate physical free space smaller.
- **Free up space** accepts a target in GB and presents alternatives: installers and archives, old downloads, large personal files, or a combined selection. It also links to rarely used apps for separate review. Review each suggested file, change the selection, and confirm before anything moves to Trash. Estimates may fall short of the target.
- Optionally moves **everything in Downloads, including hidden files and whole folders**, to Trash daily, weekly, or monthly at 12:00 local time. Finder's `.localized` and `.DS_Store` files stay, so the folder keeps its localized name; unfinished downloads (`.crdownload`, `.download`, `.part`, `.partial`, `.opdownload`) and items changed in the last 10 minutes are left for the next run. If the Mac is off at the scheduled time, the helper checks for a missed run at the next login. This requires explicit opt-in. Trash is never emptied.
- The main window has an **Antivirus** tab with the ClamAV engine included in the app. MacSpace checks the official virus definitions when it opens and every two hours while it remains open. If a check fails, it retries automatically after 3, 10, 30, and 60 seconds, then every five minutes; an existing database remains available. The first download requires internet and stores the databases separately under Application Support; later checks use FreshClam's incremental updates when available. A full-disk scan starts only when you press **Search for viruses**. It first counts accessible files, then shows checked files, elapsed time, an approximate remaining time, findings as they appear, and a Stop button. The last 20 scan summaries and findings remain in local history. Full Disk Access is needed to scan protected personal locations. iCloud folders are excluded. A file moves to Trash only after you choose **Move to Trash** and confirm. MacSpace never empties Trash or uploads files.
- Uses native glass on macOS 26+, standard materials on earlier versions, and the system appearance. The silver tile and blue brush icon has a transparent outer canvas.

Cleanup always needs judgment: old or large files can still be valuable. Close relevant apps before clearing caches and close Xcode before clearing DerivedData. Disk space figures are estimates; APFS sharing, snapshots and cloud files affect actual reclaimed space.

Antivirus includes the official universal macOS [ClamAV](https://github.com/Cisco-Talos/clamav) 1.5.4 engine, licensed under GPL-2.0-or-later. The build verifies Cisco Talos's pinned SHA-256 digest before embedding it in the app. Virus definitions are stored in the user's Application Support folder. `package.command` also creates the matching ClamAV source archive as a release asset; publish it alongside the MacSpace installer. The source and license are linked from the [official 1.5.4 release](https://github.com/Cisco-Talos/clamav/releases/tag/clamav-1.5.4). Scanned files and paths stay on the Mac.

## Updates

MacSpace checks for updates on every launch, using releases from the **RomanTheDev-cmd/MacTidy** repository only. When a newer signed Apple Silicon installer is available, MacSpace shows an offer; it downloads and opens the macOS Installer only after you click **Install update**. Before opening it, MacSpace verifies GitHub's SHA-256 digest and the release's Ed25519 signature against the public key built into the app. Complete the normal Installer steps, including administrator authorization if requested. The app cannot bypass macOS installation approval. If you defer the update, the offer appears again at the next launch; you can also check through **Settings → Check for updates**.

Only releases with a matching signed `.pkg` are offered. The app update check contacts GitHub; it does not send scanned file names or contents. Official release packages include a detached `.pkg.sig` file. `package.command` can produce the same signature for a release maintainer when `MACTIDY_SIGNING_KEY` points to the private key matching `UpdateVerifier.officialPublicKey`; keep that private key outside the repository. Locally built packages without this signature can still be installed manually, but the in-app updater will reject them.

## Languages and privacy

The app follows the first preferred system/app language. English, Russian, German, Spanish, Italian, Vietnamese, Polish and Indonesian are bundled. Additional languages supported by Apple's Translation framework can be translated on macOS 15+ after the system requests any necessary language-model download. Unsupported languages and declined/unavailable translation fall back to English. Arabic and Hebrew use right-to-left layout. A restart applies system-language changes.

Additional bundled translations were machine translated and may need corrections. This is not a claim of complete support for every language. Only the fixed interface labels are passed to Apple's translation framework; scanned names, paths and file contents are not translated or uploaded. There is no analytics or external translation service.

## Scheduled Downloads cleanup

The per-user LaunchAgent runs at noon on the selected daily, weekly, or monthly cadence, even while MacSpace is closed. If the computer was off at the scheduled time, it checks and runs the overdue cleanup at the next login. No cleanup runs immediately when you enable or change the schedule. Folder access restrictions can prevent the helper from moving files; the app shows the last report.

- Helper: `~/Library/Application Support/MacTidy/MacTidyHelper.app`
- Schedule: `~/Library/LaunchAgents/local.mactidy.weekly-downloads.plist`
- Report: `~/Library/Application Support/MacTidy/weekly-report.json`

Disable the scheduled cleanup **before uninstalling**. Then move `/Applications/MacSpace.app` to Trash. After an app update, opening MacSpace automatically refreshes an already enabled helper and keeps its pending cleanup time.

## Antivirus

The separate Antivirus tab uses the official ClamAV engine and virus definitions. Each detection stays untouched until you explicitly confirm moving that file to Trash. MacSpace does not permanently remove files or upload scan data.

## Build and test

Building from source requires Apple Command Line Tools with Swift and the macOS 26+ SDK. End users install the ready-made package and do not need build tools or a separate ClamAV installation. The build downloads the pinned ClamAV package and verifies its SHA-256 digest before embedding the engine. `package.command` also downloads the matching source archive for release distribution.

```sh
git clone https://github.com/RomanTheDev-cmd/MacTidy.git
cd MacTidy
./build.command
./test.command
./package.command
```

`build.command` produces `MacSpace.app` for the current Mac's architecture. `package.command` builds a standalone `.pkg` in `dist/` and its SHA-256 checksum. Published releases are Apple Silicon; Intel builds have not been verified.

Tests cover scanning, cancellation, symlinks, changed metadata, storage categories, selected-category cleanup, recursive cache changes, deduplication, exclusions, application-removal guards, scheduling, and localization catalogs. The real Trash test only moves and restores a generated temporary fixture.

## Source layout

`Source/` contains the SwiftUI app, scanner, helper and regression tests. `Localization/` contains JSON interface catalogs. `Assets/` contains the transparent icon source and macOS icon bundle. Contributions and translation corrections are welcome through issues and pull requests.

## License

MacSpace is [MIT](LICENSE). The bundled ClamAV engine is GPL-2.0-or-later; its matching source archive is produced beside the installer for release distribution.
