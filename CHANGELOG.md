# Changelog

## 3.0.1

- Fix moving app caches to Trash: caches that their apps keep writing to (Spotify, browsers, macOS services) no longer fail with "The item or its contents have changed". A cache folder is still rejected if it was replaced after the scan.
- When app data in the storage window changed because its app is open, explain that and suggest quitting the app instead of the misleading "no longer a regular file" message.
- Explain the macOS "was not opened" warning and how to install anyway in the README.

## 3.0.0

- Refresh the look in the style of macOS: a storage ring that fills smoothly, system-blue buttons with gentle press animations, a calmer antivirus badge, and smooth tab transitions. The app icon now uses a dark graphite tile with an outline so it stays visible on any background.
- Add a Support the project card with a link to the author on Telegram.
- Show live antivirus progress, checked-file count, elapsed time, and an approximate remaining time after file counting. Findings appear as they are detected; users can stop a long scan. Keep a local history of the last 20 scans and their findings.
- Add daily, weekly, and monthly Downloads cleanup schedules. If a scheduled run is missed while the Mac is off, the helper checks for it at the next login. All items go to Trash; Trash is never emptied.
- Scheduled Downloads cleanup keeps Finder's `.localized` and `.DS_Store` files, so the folder keeps its localized name, and leaves unfinished downloads and items changed in the last 10 minutes.
- Refresh an already enabled cleanup helper automatically when the updated app opens, retaining an overdue cleanup time. Fix saving the next cleanup date so enabling the schedule no longer shows a format error.
- Start directly in the main window without a permissions setup sheet; keep the access guide in settings for protected folders.
- Let users move an individual antivirus finding to Trash only after a separate confirmation. iCloud folders are excluded from scanning, and protected system files cannot be moved.
- Finish a full antivirus scan normally when macOS denies access to some system folders, and report how many locations were skipped. Connected flash drives and external disks are scanned too; network shares and Time Machine backup disks are skipped.
- Translate the antivirus interface into all bundled languages. The bundled ClamAV engine loads only its own libraries, never a separately installed copy.
- Keep the bundled ClamAV engine on Cisco Talos's 1.5.4 release. Refresh its official definitions at app launch and every two hours while MacSpace stays open; after the first download, FreshClam applies incremental updates. Definitions are stored separately from the app bundle.

## 2.9.0

- Add an Antivirus tab with the ClamAV engine bundled in the app. Virus definitions update at app launch; full-disk scanning starts only on request and lists findings without uploading files.
- Use the existing signed GitHub release updater to install this app version.

## 2.8.2

- Use the same light silver tile and compact blue brush icon in Finder and in the Dock, both while MacSpace is open and while it is closed.

## 2.8.1

- Rename the app and installer to MacSpace, preserving the bundle identity, preferences, and weekly schedule; the installer keeps a hidden compatibility link for existing Dock shortcuts.
- Simplify visible status messages and keep raw weekly-cleanup errors out of the interface.
- Keep a compatibility installer asset so older MacTidy versions can update to MacSpace.

## 2.8.0

- Simplify navigation: a clear storage action, a compact More menu, and scan settings that reveal categories only when needed.
- Remove technical skipped-item counts and reports from the interface; retain actionable errors when a chosen folder cannot be read or a requested move fails.
- Match macOS Storage's available-space estimate, including space macOS can reclaim automatically, and explain that portion in both disk summaries.

## 2.7.0

- Show specific large personal files, user app-data folders, and removable third-party content such as individual Arturia libraries in Explore remaining space. System folders, Users totals, and protected Apple data are excluded from the cleanup list.
- Move each selected item to Trash only after a specific confirmation and fresh path, identity, and access checks. Shared program content has an extra warning because removing it can affect the program.
- Add a separate iCloud local-copy view. It offers only fully uploaded and locally downloaded files and uses macOS Remove Download; ordinary cleanup and the weekly task exclude iCloud items.
- Give the weekly helper's access explanation enough space to display in full.

## 2.6.0

- Add a navigable disk breakdown that measures large folders, reports local Time Machine snapshot count and marks folders that macOS does not allow MacTidy to read. The unexplained remainder is explicitly approximate and cannot be attributed to one folder.
- Add a single first-run file-access guide with a shortcut to Full Disk Access settings; the same guide is available from analysis settings. macOS still requires the user to grant this access.
- Replace the ambiguous Done button in analysis settings with a clear close icon and Escape shortcut.

## 2.5.0

- Let users review and move other personal files to Trash while keeping system and protected locations excluded.
- Add a compact space-saving planner: enter a target in GB and review alternatives based on installers and archives, genuinely old downloads, large personal files, or a combined selection, with a link to rarely used apps.
- Correct the disk-capacity label and replace the monochrome icon with a transparent cool blue-silver vector design.
- Mark applications requiring additional file permissions before selection, so bulk cleanup skips them and explains why.

## 2.4.0

- Added a Storage by Type window for personal files, installer packages and installed apps, with a compact list of apps unused for 90 days.
- Added explicit selection and Trash review within each safe file category. System data, unknown file types, app libraries and hidden files remain protected.
- Replaced the app icon with a flat monochrome brush and sparkle on a transparent background.

## 2.3.0

- Check GitHub Releases at startup and open the macOS Installer once when a newer signed version is available.
- Verify GitHub SHA-256 digests and the release’s Ed25519 signature before opening the package.
- Show “Select All” and “Deselect” directly beside the cleanup action. Give the skipped-items report a clear close button and a compact size.

## 2.2.0

- Redesigned cleanup and applications windows around one primary action: scan, review, select, then move to Trash.
- Moved category selection, size threshold and weekly schedule into a settings sheet; search and filters appear when results are available.
- Reduced default window sizes and kept existing cleanup safeguards.

## 2.1.0

- Standalone macOS package installer with a fixed Applications destination.
- Automatic interface language selection, eight bundled catalogs, and optional Apple Translation support for additional languages.
- Transparent monochrome app icon and readable graphite controls.
- Unified cleanup window, dedicated application review window, and opt-in weekly Downloads cleanup.
- Regression suite with 57 checks, including localization completeness and placeholder integrity.

First public release. Apple Silicon build, macOS 13+. Ad-hoc signed app; unsigned, non-notarized installer.
