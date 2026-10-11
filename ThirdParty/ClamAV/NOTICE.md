# ClamAV 1.5.4

MacSpace includes the official universal macOS ClamAV engine as a separate executable component. ClamAV is copyright Cisco Systems, Inc. and contributors and is licensed under GPL-2.0-or-later. The complete license text is in `COPYING.txt`.

The release build downloads the Cisco Talos macOS package and verifies its SHA-256 digest before extracting the engine into `MacSpace.app/Contents/Resources/ClamAV`:

- Binary package: <https://github.com/Cisco-Talos/clamav/releases/download/clamav-1.5.4/clamav-1.5.4.macos.universal.pkg>
- Package SHA-256: `df7fa753e2f9f67f3bc99b2a40a3be7ef559088c68ad6bdf66b4b5764e965bd6`
- Corresponding source archive: <https://github.com/Cisco-Talos/clamav/releases/download/clamav-1.5.4/clamav-1.5.4.tar.gz>
- Source SHA-256: `1af1117a228f1b5bc7fa91a0dabc37848a99e7d25188e9be8043332ce721dfd3`

`package.command` places the matching source archive beside the MacSpace installer in `dist/`. Publish both assets in the same GitHub release so recipients can obtain the corresponding source.
