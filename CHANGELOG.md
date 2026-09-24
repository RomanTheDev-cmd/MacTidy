# Changelog

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
