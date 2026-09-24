import Foundation

struct CloudLocalFile: Identifiable, Sendable {
    let url: URL
    let bytes: Int64
    let stamp: String
    var id: String { url.path }
}

enum CloudLocal {
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    private static let keys = Scanner.keys.union([
        .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey,
        .ubiquitousItemIsUploadingKey, .ubiquitousItemHasUnresolvedConflictsKey
    ])

    static func eligible(_ values: URLResourceValues) -> Bool {
        values.isRegularFile == true && values.isSymbolicLink != true &&
            values.isUbiquitousItem == true && values.ubiquitousItemIsUploaded == true &&
            values.ubiquitousItemIsUploading != true &&
            values.ubiquitousItemHasUnresolvedConflicts != true &&
            values.ubiquitousItemDownloadingStatus == .current &&
            (values.fileAllocatedSize ?? 0) > 0
    }

    static func scan(root: URL = root) throws -> [CloudLocalFile] {
        let fm = FileManager.default
        guard fm.isUbiquitousItem(at: root) else { return [] }
        var found: [CloudLocalFile] = []
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true || values.isDirectory == true && url.pathExtension.count > 0 {
                enumerator.skipDescendants()
                continue
            }
            guard eligible(values), let stamp = try? Scanner.stamp(values) else { continue }
            found.append(CloudLocalFile(url: url, bytes: Int64(values.fileAllocatedSize ?? 0), stamp: stamp))
        }
        return found.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
    }

    static func evict(_ file: CloudLocalFile, root: URL = root,
                      action: (URL) throws -> Void = { try FileManager.default.evictUbiquitousItem(at: $0) }) throws {
        let url = URL(fileURLWithPath: file.url.path)
        guard FileManager.default.isUbiquitousItem(at: root),
              Scanner.isInside(url, root: root),
              Scanner.canonical(url).path == url.path else { throw CleanerError(message: L("s251")) }
        let values = try url.resourceValues(forKeys: keys)
        guard eligible(values), try Scanner.stamp(values) == file.stamp else {
            throw CleanerError(message: L("s251"))
        }
        try action(url)
    }
}
