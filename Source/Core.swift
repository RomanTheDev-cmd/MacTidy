import Foundation
import CryptoKit
import Darwin

struct Entry: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let stamp: String
    let directory: Bool
}
enum ScanKind: String, CaseIterable, Sendable { case caches, large }
struct ScanResult: Sendable { var entries: [Entry] = []; var skipped = 0 }
struct CleanerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct Scanner {
    static let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
    static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.resolvingSymlinksInPath() }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
    // Make a fresh URL so Foundation cannot return metadata cached during enumeration.
    static func values(_ url: URL) throws -> URLResourceValues {
        try URL(fileURLWithPath: url.path).resourceValues(forKeys: keys)
    }
    static func stamp(_ v: URLResourceValues) throws -> String {
        guard let identity = v.fileResourceIdentifier, let date = v.contentModificationDate else {
            throw CleanerError(message: L("s075"))
        }
        return "\(identity)|\(date.timeIntervalSince1970)|\(v.fileSize ?? -1)|\(v.isDirectory == true)|\(v.isSymbolicLink == true)"
    }
    static func isInside(_ url: URL, root: URL) -> Bool {
        let prefix = root.path == "/" ? "/" : root.path + "/"
        return url.path != root.path && url.path.hasPrefix(prefix)
    }
    static func validateRoot(_ root: URL) throws {
        let v = try values(root)
        guard v.isDirectory == true, v.isSymbolicLink != true else { throw CleanerError(message: L("s076")) }
        // Explicit read distinguishes an inaccessible/missing root from an empty result.
        _ = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    }
    static func measure(_ url: URL) throws -> (size: Int64, stamp: String) {
        try Task.checkCancellation()
        let v = try values(url)
        guard v.isSymbolicLink != true else { throw CleanerError(message: L("s077")) }
        let initial = try stamp(v)
        if v.isRegularFile == true { return (Int64(v.fileAllocatedSize ?? v.fileSize ?? 0), initial) }
        guard v.isDirectory == true else { throw CleanerError(message: L("s078")) }
        var total: Int64 = 0
        var failed = false
        var records: [String] = [initial]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in failed = true; return true }) else {
            throw CleanerError(message: L("s079"))
        }
        for case let item as URL in e {
            try Task.checkCancellation()
            let v = try values(item)
            // Record symlinks, but never follow them or call skipDescendants on them.
            records.append(item.path + "|" + (try stamp(v)))
            if v.isRegularFile == true && v.isSymbolicLink != true { total += Int64(v.fileAllocatedSize ?? v.fileSize ?? 0) }
        }
        guard !failed, try stamp(values(url)) == initial else { throw CleanerError(message: L("s080")) }
        var hash = SHA256()
        for record in records.sorted() { hash.update(data: Data(record.utf8)); hash.update(data: Data([0])) }
        return (total, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
    static func scan(root requestedRoot: URL, caches: Bool, threshold: Int64) throws -> ScanResult {
        try Task.checkCancellation()
        let root = canonical(requestedRoot)
        try validateRoot(root)
        var result = ScanResult()
        let fm = FileManager.default
        if caches {
            for u in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) {
                try Task.checkCancellation()
                do {
                    let v = try values(u)
                    guard v.isSymbolicLink != true else { continue }
                    let measured = try measure(u)
                    if measured.size > 0 { result.entries.append(Entry(url: u, size: measured.size, stamp: measured.stamp, directory: v.isDirectory == true)) }
                } catch is CancellationError { throw CancellationError() }
                  catch { result.skipped += 1 }
            }
        } else {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in result.skipped += 1; return true }) else {
                throw CleanerError(message: L("s079"))
            }
            for case let u as URL in e {
                try Task.checkCancellation()
                do {
                    let v = try values(u)
                    if v.isSymbolicLink == true { continue }
                    if v.isDirectory == true && ["Library", "System", "Applications", "node_modules", ".git"].contains(u.lastPathComponent) { e.skipDescendants(); continue }
                    if v.isRegularFile == true, Int64(v.fileSize ?? 0) >= threshold {
                        result.entries.append(Entry(url: u, size: Int64(v.fileSize ?? 0), stamp: try stamp(v), directory: false))
                    }
                } catch { result.skipped += 1 }
            }
        }
        try Task.checkCancellation()
        result.entries.sort { $0.size == $1.size ? $0.id < $1.id : $0.size > $1.size }
        return result
    }
}
struct TrashResult: Sendable { var removed: Set<String> = []; var failures: [String] = [] }
struct Cleaner {
    static func validate(_ item: Entry, root: URL, mode: ScanKind, cacheRoot: URL) throws -> URL {
        let u = URL(fileURLWithPath: item.url.path)
        guard Scanner.isInside(u, root: root), Scanner.canonical(u).path == u.path,
              Scanner.canonical(root).path == root.path else { throw CleanerError(message: L("s081")) }
        let v = try Scanner.values(u)
        guard v.isSymbolicLink != true else { throw CleanerError(message: L("s082")) }
        let current: String
        switch mode {
        case .caches:
            guard root.path == Scanner.canonical(cacheRoot).path, u.deletingLastPathComponent().path == root.path else { throw CleanerError(message: L("s083")) }
            current = try Scanner.measure(u).stamp
        case .large:
            guard v.isRegularFile == true else { throw CleanerError(message: L("s084")) }
            current = try Scanner.stamp(v)
        }
        guard current == item.stamp else { throw CleanerError(message: L("s085")) }
        return u
    }
    static func trash(_ items: [Entry], root: URL, mode: ScanKind, cacheRoot: URL,
                      move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> TrashResult {
        var result = TrashResult()
        for item in items {
            do {
                let u = try validate(item, root: root, mode: mode, cacheRoot: cacheRoot)
                try move(u)
                result.removed.insert(item.id)
            } catch { result.failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)") }
        }
        return result
    }
}
