import Foundation
import CryptoKit
func blockOn(_ gate: DispatchSemaphore) { gate.wait() }

@main struct Tests {
    static var count = 0
    static func check(_ value: Bool, _ name: String) {
        precondition(value, name); count += 1; fputs("PASS: \(name)\n", stderr)
    }
    static func rejects(_ name: String, _ action: () throws -> Void) {
        do { try action(); preconditionFailure(name) } catch { count += 1; fputs("PASS: \(name)\n", stderr) }
    }
    @MainActor static func main() async throws {
        check(AppLocalization.base("en-US") == "en", "regional language resolution")
        check(AppLocalization.base("zh-TW") == "zh-Hant", "traditional Chinese resolution")
        check(AppLocalization.format("{1} / {0}", ["literal {1}", "second"]) == "second / literal {1}", "translation placeholders cannot expand argument content")
        let catalogs = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MACTIDY_LOCALIZATION_DIR"]!)
        let english = AppLocalization.shared.english
        check(english.count == 253, "English fallback is complete")
        for url in try FileManager.default.contentsOfDirectory(at: catalogs, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            let catalog = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
            check(Set(catalog.keys) == Set(english.keys) && english.allSatisfy { AppLocalization.tokens($0.value) == AppLocalization.tokens(catalog[$0.key] ?? "") }, "catalog keys and placeholders: " + url.lastPathComponent)
        }
        check(AppVersion("v2.3.0")! > AppVersion("2.2.9")!, "semantic update version comparison")
        check(AppVersion("2.3.0-beta") == nil && AppVersion("2.3") == nil, "prerelease and malformed versions rejected")
        let key = Curve25519.Signing.PrivateKey()
        let package = Data("test package".utf8)
        let signature = try key.signature(for: package)
        check(UpdateVerifier.verify(package: package, signature: signature, publicKey: key.publicKey.rawRepresentation), "valid update signature")
        check(!UpdateVerifier.verify(package: Data("tampered".utf8), signature: signature, publicKey: key.publicKey.rawRepresentation), "changed package rejected")
        func asset(_ name: String, _ size: Int) -> [String: Any] {
            ["name": name, "size": size, "digest": "sha256:" + String(repeating: "a", count: 64),
             "browser_download_url": "https://github.com/RomanTheDev-cmd/MacTidy/releases/download/v2.4.0/" + name]
        }
        let release: [String: Any] = ["tag_name": "v2.4.0", "draft": false, "prerelease": false,
                                       "assets": [asset("MacTidy-2.4.0-arm64.pkg", 2_000_000), asset("MacTidy-2.4.0-arm64.pkg.sig", 64)]]
        let releaseData = try JSONSerialization.data(withJSONObject: release)
        check(try AvailableUpdate.parse(releaseData, current: AppVersion("2.3.0")!)?.version == AppVersion("2.4.0"), "signed update selected")
        check(try AvailableUpdate.parse(releaseData, current: AppVersion("2.4.0")!) == nil, "current release is not reinstalled")
        var unsigned = release; unsigned["assets"] = [asset("MacTidy-2.4.0-arm64.pkg", 2_000_000)]
        rejects("unsigned release rejected") { _ = try AvailableUpdate.parse(JSONSerialization.data(withJSONObject: unsigned), current: AppVersion("2.3.0")!) }
        let fm = FileManager.default
        let capacity = DiskCapacity.current()!
        let diskURL = fm.homeDirectoryForCurrentUser
        if let systemAvailable = try diskURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
            let tolerance = max(1_000_000_000, capacity.total / 100)
            check(abs(capacity.available - systemAvailable) < tolerance,
                  "displayed disk availability follows macOS purgeable-aware capacity")
        }
        let parsedDisk = DiskAudit.parse("100\t/System/Volumes/Data\n60\t/System/Volumes/Data/Library\n40\t/System/Volumes/Data/Users\n5\t/System/Volumes/Data/Users/name\n", root: DiskAudit.dataRoot)
        check(parsedDisk.0 == 102_400 && parsedDisk.1.map(\.url.lastPathComponent) == ["Library", "Users"], "disk overview parses only direct children and sorts largest first")
        let rawRoot = fm.temporaryDirectory.appendingPathComponent("MacTidy-tests-" + UUID().uuidString)
        try fm.createDirectory(at: rawRoot, withIntermediateDirectories: true)
        let root = Scanner.canonical(rawRoot)
        defer { try? fm.removeItem(at: root) }
        check(try CloudLocal.scan(root: root).isEmpty, "ordinary folders are not scanned as iCloud Drive")
        let ordinaryCloudCandidate = CloudLocalFile(url: root.appendingPathComponent("local.bin"), bytes: 8192, stamp: "test")
        rejects("ordinary files cannot use the iCloud local-copy action") {
            try CloudLocal.evict(ordinaryCloudCandidate, root: root) { _ in }
        }
        func write(_ path: String, _ size: Int = 8192) throws {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: size).write(to: url)
        }
        try write("appdatahome/Library/Application Support/Vendor/data.bin")
        let appDataHome = root.appendingPathComponent("appdatahome")
        let vendor = appDataHome.appendingPathComponent("Library/Application Support/Vendor")
        let reviewableData = DiskOpportunity(url: vendor, bytes: 8192, kind: .userAppData,
                                             stamp: try Scanner.stamp(Scanner.values(vendor)))
        var movedAppData: [URL] = []
        try DiskAudit.trashAppData(reviewableData, home: appDataHome) { movedAppData.append($0) }
        check(movedAppData == [vendor], "explicitly selected user app data can be validated before Trash")
        try write("appdatahome/Library/Application Support/Vendor/new.bin")
        rejects("changed app data is rejected before Trash") { try DiskAudit.trashAppData(reviewableData, home: appDataHome) { _ in } }
        let protectedData = DiskOpportunity(url: appDataHome.appendingPathComponent("Library/Application Support/com.apple.test"), bytes: 8192, kind: .userAppData, stamp: "test")
        rejects("Apple app data is not offered for direct Trash") { try DiskAudit.trashAppData(protectedData, home: appDataHome) { _ in } }
        let sharedData = DiskOpportunity(url: vendor, bytes: 8192, kind: .sharedAppData, stamp: nil)
        rejects("shared app resources cannot be trashed directly") { try DiskAudit.trashAppData(sharedData, home: appDataHome) { _ in } }
        try write("Library/Arturia/Analog Lab V/content.bin")
        let sharedVendor = root.appendingPathComponent("Library/Arturia/Analog Lab V")
        let eligibleShared = DiskOpportunity(url: sharedVendor, bytes: 8192, kind: .sharedAppData,
                                             stamp: try Scanner.stamp(Scanner.values(sharedVendor)))
        var movedShared: [URL] = []
        try DiskAudit.trashAppData(eligibleShared, home: appDataHome, library: root.appendingPathComponent("Library")) { movedShared.append($0) }
        check(movedShared == [sharedVendor], "individual third-party shared content can be validated before Trash")
        let protectedShared = DiskOpportunity(url: root.appendingPathComponent("Library/Audio/Instrument"), bytes: 8192,
                                              kind: .sharedAppData, stamp: "test")
        rejects("system audio library cannot be offered for direct Trash") {
            try DiskAudit.trashAppData(protectedShared, home: appDataHome, library: root.appendingPathComponent("Library")) { _ in }
        }
        let nestedData = DiskOpportunity(url: vendor.appendingPathComponent("data.bin"), bytes: 8192, kind: .userAppData, stamp: "test")
        rejects("nested app data cannot be trashed by a folder suggestion") { try DiskAudit.trashAppData(nestedData, home: appDataHome) { _ in } }
        for name in ["scan/large.bin", "scan/Library/skip.bin", "scan/.hidden/skip.bin", "scan/sample.app/skip.bin", "scan/nested/second.bin"] { try write(name) }
        try write("scan/small.bin", 10)
        try write("storagehome/Documents/report.pdf")
        try write("storagehome/Downloads/setup.pkg")
        try write("storagehome/Downloads/archive.zip")
        try write("storagehome/Pictures/photo.heic")
        try write("storagehome/Documents/cache.db")
        try write("storagehome/Documents/.secret.key")
        try write("storagehome/Pictures/Family.photoslibrary/internal.jpg")
        let storageHome = root.appendingPathComponent("storagehome")
        try fm.createSymbolicLink(at: storageHome.appendingPathComponent("Documents/outside.pdf"), withDestinationURL: root.appendingPathComponent("scan/large.bin"))
        let overview = try StorageScanner.scan(home: storageHome, appRoots: [], ownBundleID: nil)
        check(overview.counts[.documents] == 1 && overview.counts[.installers] == 1 && overview.counts[.archives] == 1 && overview.counts[.photos] == 1, "personal file types and packages classified")
        check(!overview.files.contains { $0.entry.url.path.contains("photoslibrary") || $0.entry.url.lastPathComponent == "outside.pdf" || $0.entry.url.lastPathComponent == ".secret.key" }, "protected packages, links and hidden files skipped")
        check(overview.files.contains { $0.kind == .other && $0.entry.url.lastPathComponent == "cache.db" } && StorageKind.other.reviewable && !StorageKind.applications.reviewable, "other personal files are reviewable; apps use their own window")
        let other = overview.files.first { $0.kind == .other }!
        var movedOther: [URL] = []
        let otherResult = StorageScanner.trash([other]) { movedOther.append($0) }
        check(otherResult.removed == [other.id] && movedOther == [other.entry.url], "selected other personal file can be moved to Trash")
        let plans = StoragePlanner.suggest(snapshot: overview, target: 1)
        check(plans.first { $0.kind == .packages }?.files.allSatisfy { $0.kind == .installers || $0.kind == .archives } == true, "package suggestion contains installers and archives only")
        let plannedLarge = StorageFile(entry: Entry(url: other.entry.url, size: 150_000_000, stamp: other.entry.stamp, directory: false), root: other.root, kind: .other, modified: Date().addingTimeInterval(-40 * 86400), created: Date().addingTimeInterval(-40 * 86400), added: nil)
        let largePlans = StoragePlanner.suggest(snapshot: StorageSnapshot(files: [plannedLarge]), target: 100_000_000)
        check(largePlans.first { $0.kind == .largeFiles }?.targetReached == true, "large personal file can meet space target")
        check(largePlans.first { $0.kind == .combined }?.targetReached == true, "combined suggestion can reach space target")
        let freshDownload = StorageFile(entry: plannedLarge.entry, root: storageHome.appendingPathComponent("Downloads"), kind: .other, modified: Date().addingTimeInterval(-40 * 86400), created: Date(), added: Date())
        check(StoragePlanner.suggest(snapshot: StorageSnapshot(files: [freshDownload]), target: 1).first { $0.kind == .oldDownloads } == nil, "recently downloaded old file is not suggested as an old download")
        let document = overview.files.first { $0.kind == .documents }!
        var movedStorage: [URL] = []
        let planned = StorageScanner.trash([document]) { movedStorage.append($0) }
        check(planned.removed == [document.id] && movedStorage == [document.entry.url], "selected category file validated before cleanup")
        try write("storagehome/Documents/report.pdf", 16_384)
        let changed = StorageScanner.trash([document]) { movedStorage.append($0) }
        check(changed.removed.isEmpty && movedStorage.count == 1, "changed category file rejected before cleanup")
        let scanRoot = root.appendingPathComponent("scan")
        try fm.createSymbolicLink(at: scanRoot.appendingPathComponent("link.bin"), withDestinationURL: scanRoot.appendingPathComponent("large.bin"))
        let r = try Scanner.scan(root: scanRoot, caches: false, threshold: 4096)
        check(Set(r.entries.map { $0.url.lastPathComponent }) == ["large.bin", "second.bin"], "recursive scan and excluded paths")
        check(r.entries.reduce(0) { $0 + $1.size } == 16384, "size threshold")
        rejects("missing root is an error") { _ = try Scanner.scan(root: root.appendingPathComponent("missing"), caches: false, threshold: 0) }
        rejects("file cannot be scan root") { _ = try Scanner.scan(root: scanRoot.appendingPathComponent("large.bin"), caches: false, threshold: 0) }
        let alias = root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: scanRoot)
        let aliased = try Scanner.scan(root: alias, caches: false, threshold: 4096)
        check(aliased.entries == r.entries, "canonical results for folder aliases")
        _ = try Cleaner.validate(r.entries[0], root: scanRoot, mode: .large, cacheRoot: root)
        check(Scanner.isInside(root, root: URL(fileURLWithPath: "/")), "root filesystem containment")
        check(!Scanner.isInside(root.appendingPathComponent("scan-other/file"), root: scanRoot), "sibling prefix is outside scan root")
        let original = r.entries.first { $0.url.lastPathComponent == "large.bin" }!
        // Populate Foundation URL cache before modifying the file.
        _ = try original.url.resourceValues(forKeys: Scanner.keys)
        try write("scan/large.bin", 20000)
        rejects("stale cached metadata cannot authorize modified file") { _ = try Cleaner.validate(original, root: scanRoot, mode: .large, cacheRoot: root) }
        let second = r.entries.first { $0.url.lastPathComponent == "second.bin" }!
        try fm.removeItem(at: second.url)
        try fm.createSymbolicLink(at: second.url, withDestinationURL: original.url)
        rejects("replacement symlink is rejected") { _ = try Cleaner.validate(second, root: scanRoot, mode: .large, cacheRoot: root) }
        try write("cache/app/nested/data")
        let cache = root.appendingPathComponent("cache")
        let cached = try Scanner.scan(root: cache, caches: true, threshold: 0).entries[0]
        let appDate = try Scanner.values(cached.url).contentModificationDate!
        try write("cache/app/nested/data", 24000)
        try fm.setAttributes([.modificationDate: appDate], ofItemAtPath: cached.url.path)
        rejects("nested cache change detected with unchanged top-level mtime") { _ = try Cleaner.validate(cached, root: cache, mode: .caches, cacheRoot: cache) }
        try write("trash/a"); try write("trash/b")
        let trashRoot = root.appendingPathComponent("trash")
        let pending = try Scanner.scan(root: trashRoot, caches: false, threshold: 0).entries
        var called: [String] = []
        let batch = Cleaner.trash(pending, root: trashRoot, mode: .large, cacheRoot: cache) { u in
            called.append(u.lastPathComponent)
            if u.lastPathComponent == "a" { throw CleanerError(message: "Injected failure") }
        }
        check(called.count == 2 && batch.removed.count == 1 && batch.failures.count == 1, "trash continues after individual failure")
        // Test real Trash API only with our own fixture, then restore it immediately.
        var destination: NSURL?
        let testFile = pending[0].url
        try fm.trashItem(at: testFile, resultingItemURL: &destination)
        guard let destination else { throw CleanerError(message: "Trash API returned no restore URL") }
        try fm.moveItem(at: destination as URL, to: testFile)
        check(fm.fileExists(atPath: testFile.path), "real Trash move and restore of generated fixture")
        try write("weekly/fresh.txt", 10); try write("weekly/folder/child", 10); try write("weekly/.hidden", 10)
        let weekly = root.appendingPathComponent("weekly")
        try fm.createSymbolicLink(at: weekly.appendingPathComponent("link"), withDestinationURL: original.url)
        var moved: [String] = []
        let report = WeeklyCleanup.run(root: weekly) { moved.append($0.lastPathComponent) }
        check(Set(moved) == ["fresh.txt", "folder", ".hidden", "link"] && report.moved == 4, "weekly includes new files, whole folders, hidden files and links")
        check(fm.fileExists(atPath: original.url.path), "weekly does not traverse symlink targets")
        let partial = WeeklyCleanup.run(root: weekly) { u in if u.lastPathComponent == "folder" { throw CleanerError(message: "Injected failure") } }
        check(partial.moved == 3 && partial.failures.count == 1, "weekly reports partial failures")
        let missing = WeeklyCleanup.run(root: root.appendingPathComponent("missing")) { _ in preconditionFailure("Must not move") }
        check(missing.moved == 0 && missing.failures.count == 1, "weekly reports inaccessible root")
        let gate = DispatchSemaphore(value: 0)
        let task = Task.detached { blockOn(gate); return try Scanner.scan(root: scanRoot, caches: false, threshold: 0) }
        task.cancel(); gate.signal()
        do { _ = try await task.value; preconditionFailure("Cancellation") } catch is CancellationError { check(true, "scanner observes cancellation directly") }
        let model = Model(); model.enabled = [.large]; model.folder = scanRoot; model.threshold = 0
        model.scan(); model.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        check(!model.busy && model.candidates.isEmpty && !model.hasScanned, "cancelled scan cannot publish stale results")
        model.search = "old filter"; model.reset()
        check(model.search.isEmpty && model.completed.isEmpty, "new scan clears filters and prior scope")
        model.cleaning = true; model.scan()
        check(!model.busy, "scan is blocked while trash operation runs")
        let weeklyConfig = WeeklySchedule.configuration(helper: root.appendingPathComponent("Helper With Spaces.app"))
        let calendar = weeklyConfig["StartCalendarInterval"] as? [String: Int]
        check(calendar == ["Weekday": 0, "Hour": 12, "Minute": 0], "weekly launch calendar")
        check(weeklyConfig["RunAtLoad"] == nil && weeklyConfig["KeepAlive"] == nil, "enabling does not trigger immediate cleanup or retries")
        let args = weeklyConfig["ProgramArguments"] as? [String]
        check(args?.count == 1 && args![0].contains("Helper With Spaces.app"), "helper path with spaces remains a single argument")
        let now = Date()
        let old = now.addingTimeInterval(-40 * 86400)
        check(Audit.matches(.installers, url: URL(fileURLWithPath: "/a/Install.DMG"), modified: nil, created: nil, added: nil, now: now), "installer extensions are case insensitive")
        check(!Audit.matches(.archives, url: URL(fileURLWithPath: "/a/photo.jpg"), modified: nil, created: nil, added: nil, now: now), "ordinary documents are not archives")
        check(Audit.matches(.oldDownloads, url: original.url, modified: old, created: old, added: old, now: now), "old downloads date rule")
        check(!Audit.matches(.oldDownloads, url: original.url, modified: old, created: old, added: now, now: now), "recently downloaded old file is retained")
        check(!Audit.matches(.logs, url: original.url, modified: now, created: old, added: nil, now: now), "recent logs are retained")
        try write("home/Downloads/installer.dmg")
        try write("home/Downloads/archive.zip")
        try write("home/Downloads/video.mov")
        try write("home/Library/Caches/TestCache/content")
        try write("home/Library/Logs/old.log")
        try write("home/Library/Logs/current.log")
        try write("home/Library/Developer/Xcode/DerivedData/Build/output")
        let home = root.appendingPathComponent("home")
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: home.appendingPathComponent("Library/Logs/old.log").path)
        var config = AuditConfiguration(home: home, folder: home.appendingPathComponent("Downloads"), threshold: 1, categories: Set(CleanupCategory.allCases), now: now)
        let audited = try Audit.scan(config)
        check(!audited.unavailableChosenFolder, "readable chosen folder has no access warning")
        var inaccessibleConfig = config
        inaccessibleConfig.categories = [.large]
        inaccessibleConfig.folder = root.appendingPathComponent("missing-folder")
        let inaccessibleAudit = try Audit.scan(inaccessibleConfig)
        check(inaccessibleAudit.unavailableChosenFolder && inaccessibleAudit.candidates.isEmpty,
              "inaccessible chosen folder produces an actionable warning")
        check(audited.candidates.filter { $0.entry.url.lastPathComponent == "installer.dmg" }.count == 1, "overlapping categories count a file once")
        check(audited.candidates.first { $0.entry.url.lastPathComponent == "installer.dmg" }?.category == .installers, "installer classification takes priority over large file")
        check(audited.candidates.filter { $0.category == .logs }.map { $0.entry.url.lastPathComponent } == ["old.log"], "only old log files included")
        check(audited.candidates.contains { $0.category == .developer }, "Xcode DerivedData included when requested")
        let cacheItem = audited.candidates.first { $0.category == .caches }!
        let nestedURL = home.appendingPathComponent("Library/Caches/TestCache/content")
        let child = try Scanner.scan(root: nestedURL.deletingLastPathComponent(), caches: false, threshold: 0).entries[0]
        let overlap = Candidate(entry: child, root: nestedURL.deletingLastPathComponent(), mode: .large, category: .large, modified: nil)
        check(Audit.deduplicate([overlap, cacheItem]).count == 1, "parent directory suppresses nested file")
        config.excluded = [nestedURL.path]
        let excludedAudit = try Audit.scan(config)
        check(!excludedAudit.candidates.contains { $0.category == .caches }, "excluded file protects its containing cache folder")
        let dataFile = audited.candidates.first { $0.entry.url.lastPathComponent == "video.mov" }!
        var movedCandidates: [String] = []
        let movedResult = Audit.trash([dataFile, dataFile]) { movedCandidates.append($0.path) }
        check(movedResult.removed.count == 1 && movedCandidates.count == 1, "mixed cleanup deduplicates selected candidates")
        check(ApplicationScanner.isRare(lastUsed: old, days: 30, now: now), "rare application age filter")
        check(!ApplicationScanner.isRare(lastUsed: nil, days: 30, now: now), "unknown history never implies rarely used")
        check(!ApplicationScanner.isRare(lastUsed: now, days: 90, now: now), "recent app is not rare")
        try write("Apps/Example.app/Contents/MacOS/example")
        let appsRoot = root.appendingPathComponent("Apps")
        let appURL = appsRoot.appendingPathComponent("Example.app")
        let info: [String: Any] = ["CFBundleIdentifier": "test.example", "CFBundleName": "Example", "CFBundlePackageType": "APPL", "CFBundleExecutable": "example"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        let appScan = try ApplicationScanner.scan(roots: [appsRoot], ownBundleID: nil)
        check(appScan.apps.count == 1, "application discovery handles absent own bundle ID")
        let example = appScan.apps[0]
        _ = try ApplicationScanner.validate(example, allowedRoots: [appsRoot], runningPaths: [], ownBundleID: "other.app")
        check(ApplicationScanner.canMoveToTrash(example), "writable app in writable folder is removable")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: appURL.path)
        check(!ApplicationScanner.canMoveToTrash(example), "read-only app is not offered for cleanup")
        rejects("read-only app is rejected before Trash") { _ = try ApplicationScanner.validate(example, allowedRoots: [appsRoot], runningPaths: [], ownBundleID: nil) }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appURL.path)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: appsRoot.path)
        check(!ApplicationScanner.canMoveToTrash(example), "app in read-only folder is not offered for cleanup")
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appsRoot.path)
        rejects("running app cannot be removed") { _ = try ApplicationScanner.validate(example, allowedRoots: [appsRoot], runningPaths: [example.id], ownBundleID: nil) }
        rejects("app outside allowed roots cannot be removed") { _ = try ApplicationScanner.validate(example, allowedRoots: [root.appendingPathComponent("Elsewhere")], runningPaths: [], ownBundleID: nil) }
        rejects("MacTidy cannot remove itself") { _ = try ApplicationScanner.validate(example, allowedRoots: [appsRoot], runningPaths: [], ownBundleID: "test.example") }
        try write("Apps/Example.app/Contents/MacOS/example", 30000)
        rejects("updated application rejected after scan") { _ = try ApplicationScanner.validate(example, allowedRoots: [appsRoot], runningPaths: [], ownBundleID: nil) }
        let unknownApp = InstalledApplication(url: example.url, name: example.name, bundleID: example.bundleID, lastUsed: nil, entry: example.entry, root: example.root)
        let appModel = ApplicationsModel(); appModel.apps = [unknownApp]; appModel.days = 90
        check(appModel.visible.isEmpty, "unknown app history hidden by default")
        appModel.includeUnknown = true
        check(appModel.visible.count == 1, "unknown history opt-in filter")
        print("\(count) checks passed")
    }
}
