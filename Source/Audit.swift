import Foundation

enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case caches, logs, installers, archives, oldDownloads, developer, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .caches: return L("s055")
        case .logs: return L("s056")
        case .installers: return L("s057")
        case .archives: return L("s058")
        case .oldDownloads: return L("s059")
        case .developer: return L("s060")
        case .large: return L("s061")
        }
    }
    var symbol: String {
        switch self {
        case .caches: return "square.stack.3d.up.fill"
        case .logs: return "doc.text.fill"
        case .installers: return "shippingbox.fill"
        case .archives: return "archivebox.fill"
        case .oldDownloads: return "clock.arrow.circlepath"
        case .developer: return "hammer.fill"
        case .large: return "internaldrive.fill"
        }
    }
    var detail: String {
        switch self {
        case .caches: return L("s062")
        case .logs: return L("s063")
        case .installers: return L("s064")
        case .archives: return L("s065")
        case .oldDownloads: return L("s066")
        case .developer: return L("s067")
        case .large: return L("s068")
        }
    }
    var shortDetail: String {
        switch self {
        case .caches: return L("s069")
        case .logs: return L("s070")
        case .installers: return "DMG · PKG · ISO · XIP"
        case .archives: return "ZIP · RAR · 7Z · TAR"
        case .oldDownloads: return L("s071")
        case .developer: return "DerivedData"
        case .large: return L("s072")
        }
    }
}
struct Candidate: Identifiable, Hashable, Sendable {
    var id: String { entry.id }
    let entry: Entry
    let root: URL
    let mode: ScanKind
    let category: CleanupCategory
    let modified: Date?
}
struct AuditConfiguration: Sendable {
    var home = FileManager.default.homeDirectoryForCurrentUser
    var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    var threshold: Int64 = 100_000_000
    var categories = Set(CleanupCategory.allCases.filter { $0 != .developer })
    var excluded: Set<String> = []
    var now = Date()
}
struct AuditResult: Sendable {
    var candidates: [Candidate] = []
    var notes: [String] = []
    var completed: Set<CleanupCategory> = []
    var unavailableChosenFolder = false
}
struct Audit {
    static let installerExtensions: Set<String> = ["dmg", "pkg", "iso", "xip", "mpkg"]
    static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "zst"]
    static func excluded(_ url: URL, paths: Set<String>) -> Bool {
        paths.contains { url.path == $0 || url.path.hasPrefix($0 + "/") }
    }
    static func matches(_ category: CleanupCategory, url: URL, modified: Date?, created: Date?, added: Date?, now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        switch category {
        case .installers: return installerExtensions.contains(url.pathExtension.lowercased())
        case .archives: return archiveExtensions.contains(url.pathExtension.lowercased())
        case .logs: return modified.map { $0 < cutoff } ?? false
        case .oldDownloads:
            guard let modified, let created else { return false }
            return max(modified, created, added ?? .distantPast) < cutoff
        default: return true
        }
    }
    static func root(for category: CleanupCategory, config: AuditConfiguration) -> URL {
        switch category {
        case .caches: return config.home.appendingPathComponent("Library/Caches")
        case .logs: return config.home.appendingPathComponent("Library/Logs")
        case .developer: return config.home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        case .large: return config.folder
        default: return config.home.appendingPathComponent("Downloads")
        }
    }
    static func scan(_ config: AuditConfiguration, progress: @Sendable (CleanupCategory) -> Void = { _ in }) throws -> AuditResult {
        var result = AuditResult()
        var scans: [String: ScanResult] = [:]
        for category in CleanupCategory.allCases where config.categories.contains(category) {
            try Task.checkCancellation()
            progress(category)
            let root = Scanner.canonical(root(for: category, config: config))
            // Missing optional system folders are normal; an unavailable custom folder is an error.
            if category != .large && !FileManager.default.fileExists(atPath: root.path) {
                let parent = root.deletingLastPathComponent()
                if FileManager.default.isReadableFile(atPath: parent.path) { result.completed.insert(category); continue }
            }
            do {
                let direct = category == .caches || category == .developer
                let key = root.path + (direct ? "/direct" : "/recursive")
                let scanned: ScanResult
                if let previous = scans[key] { scanned = previous }
                else {
                    scanned = try Scanner.scan(root: root, caches: direct, threshold: 0)
                    scans[key] = scanned
                }
                if scanned.skipped > 0 { result.notes.append(L("s073" , category.title, scanned.skipped)) }
                for item in scanned.entries {
                    try Task.checkCancellation()
                    if excluded(item.url, paths: config.excluded) || (item.directory && config.excluded.contains { $0.hasPrefix(item.id + "/") }) { continue }
                    if category == .large && item.size < config.threshold { continue }
                    do {
                        let dates = try URL(fileURLWithPath: item.url.path).resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey])
                        guard matches(category, url: item.url, modified: dates.contentModificationDate, created: dates.creationDate, added: dates.addedToDirectoryDate, now: config.now) else { continue }
                        result.candidates.append(Candidate(entry: item, root: root, mode: direct ? .caches : .large, category: category, modified: dates.contentModificationDate))
                    } catch { result.notes.append(L("s074" , item.url.lastPathComponent)) }
                }
                result.completed.insert(category)
            } catch is CancellationError { throw CancellationError() }
              catch {
                  if category == .large { result.unavailableChosenFolder = true }
                  else { result.notes.append("\(category.title): \(error.localizedDescription)") }
              }
        }
        result.candidates = deduplicate(result.candidates)
        return result
    }
    static func deduplicate(_ candidates: [Candidate]) -> [Candidate] {
        // Keep one row per path. If a cache directory is present, do not count its children twice.
        var paths: Set<String> = []
        let unique = candidates.filter { paths.insert($0.id).inserted }
        let directories = Set(unique.filter { $0.entry.directory }.map(\.id))
        return unique.filter { item in
            var parent = item.entry.url.deletingLastPathComponent()
            while parent.path != "/" {
                if directories.contains(parent.path) { return false }
                parent.deleteLastPathComponent()
            }
            return true
        }.sorted { $0.entry.size == $1.entry.size ? $0.id < $1.id : $0.entry.size > $1.entry.size }
    }
    static func trash(_ items: [Candidate], move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> TrashResult {
        var result = TrashResult()
        for item in deduplicate(items) {
            let partial = Cleaner.trash([item.entry], root: item.root, mode: item.mode, cacheRoot: item.root, move: move)
            result.removed.formUnion(partial.removed); result.failures += partial.failures
        }
        return result
    }
}
