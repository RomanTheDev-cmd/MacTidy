import Foundation

enum StorageKind: String, CaseIterable, Identifiable, Sendable {
    case photos, videos, audio, documents, installers, archives, applications, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .photos: return L("s159")
        case .videos: return L("s160")
        case .audio: return L("s161")
        case .documents: return L("s162")
        case .installers: return L("s057")
        case .archives: return L("s058")
        case .applications: return L("s014")
        case .other: return L("s163")
        }
    }
    var symbol: String {
        switch self {
        case .photos: return "photo.on.rectangle"
        case .videos: return "film"
        case .audio: return "music.note"
        case .documents: return "doc.text"
        case .installers: return "shippingbox"
        case .archives: return "archivebox"
        case .applications: return "square.grid.2x2"
        case .other: return "ellipsis.circle"
        }
    }
    var reviewable: Bool { self != .other }
}
struct StorageFile: Identifiable, Sendable {
    var id: String { entry.id }
    let entry: Entry
    let root: URL
    let kind: StorageKind
}
struct StorageSnapshot: Sendable {
    var files: [StorageFile] = []
    var apps: [InstalledApplication] = []
    var skipped = 0
    var totals: [StorageKind: Int64] = [:]
    var counts: [StorageKind: Int] = [:]
}
struct StorageScanner {
    static let rootNames = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
    static let protectedDirectoryNames: Set<String> = ["Library", "System", "Applications", "node_modules", ".git", ".svn"]
    static let protectedPackageExtensions: Set<String> = ["app", "photoslibrary", "musiclibrary", "imovielibrary", "bundle", "framework", "plugin", "vst", "vst3", "component", "kext", "xcodeproj", "xcworkspace", "sparsebundle", "backupdb"]
    static let types: [StorageKind: Set<String>] = [
        .photos: ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp", "avif", "dng", "cr2", "nef", "arw", "svg"],
        .videos: ["mov", "mp4", "m4v", "mkv", "avi", "webm", "wmv", "mpg", "mpeg"],
        .audio: ["mp3", "m4a", "wav", "aif", "aiff", "flac", "alac", "ogg", "opus"],
        .documents: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "pages", "numbers", "keynote", "epub", "csv", "odt", "ods", "odp"],
        .installers: ["dmg", "pkg", "mpkg", "xip", "iso"],
        .archives: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "zst"]
    ]
    static func classify(_ url: URL) -> StorageKind {
        let ext = url.pathExtension.lowercased()
        for kind in StorageKind.allCases where types[kind]?.contains(ext) == true { return kind }
        return .other
    }
    static func scan(home: URL, appRoots: [URL] = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")], ownBundleID: String?, progress: @Sendable (String) -> Void = { _ in }) throws -> StorageSnapshot {
        var snapshot = StorageSnapshot()
        let fm = FileManager.default
        for name in rootNames {
            try Task.checkCancellation()
            let requested = home.appendingPathComponent(name)
            guard fm.fileExists(atPath: requested.path) else { continue }
            do { try Scanner.validateRoot(requested) }
            catch { snapshot.skipped += 1; continue }
            let root = Scanner.canonical(requested)
            progress(name)
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(Scanner.keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in snapshot.skipped += 1; return true }) else {
                snapshot.skipped += 1; continue
            }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                do {
                    let values = try Scanner.values(url)
                    if values.isSymbolicLink == true { continue }
                    if values.isDirectory == true {
                        if protectedDirectoryNames.contains(url.lastPathComponent) || protectedPackageExtensions.contains(url.pathExtension.lowercased()) { enumerator.skipDescendants() }
                        continue
                    }
                    guard values.isRegularFile == true, Scanner.isInside(url, root: root) else { continue }
                    let size = Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
                    let kind = classify(url)
                    let entry = Entry(url: url, size: size, stamp: try Scanner.stamp(values), directory: false)
                    snapshot.files.append(StorageFile(entry: entry, root: root, kind: kind))
                    snapshot.totals[kind, default: 0] += size
                    snapshot.counts[kind, default: 0] += 1
                } catch is CancellationError { throw CancellationError() }
                  catch { snapshot.skipped += 1 }
            }
        }
        progress(L("s014"))
        let appScan = try ApplicationScanner.scan(roots: appRoots, ownBundleID: ownBundleID)
        snapshot.apps = appScan.apps
        snapshot.totals[.applications] = appScan.apps.reduce(0) { $0 + $1.entry.size }
        snapshot.counts[.applications] = appScan.apps.count
        snapshot.skipped += appScan.notes.count
        snapshot.files.sort { $0.entry.size == $1.entry.size ? $0.id < $1.id : $0.entry.size > $1.entry.size }
        return snapshot
    }
    static func trash(_ files: [StorageFile], move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> TrashResult {
        var result = TrashResult()
        for file in files {
            do {
                guard file.kind.reviewable, file.kind != .applications, classify(file.entry.url) == file.kind else { throw CleanerError(message: L("s081")) }
                let url = try Cleaner.validate(file.entry, root: file.root, mode: .large, cacheRoot: file.root)
                try move(url)
                result.removed.insert(file.id)
            } catch { result.failures.append("\(file.entry.url.lastPathComponent): \(error.localizedDescription)") }
        }
        return result
    }
}
