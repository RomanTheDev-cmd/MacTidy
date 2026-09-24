# Changelog

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
