import Foundation
import CoreServices

struct InstalledApplication: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String?
    let lastUsed: Date?
    let entry: Entry
    let root: URL
}
struct ApplicationScan: Sendable { var apps: [InstalledApplication] = []; var notes: [String] = [] }
struct ApplicationScanner {
    static func canMoveToTrash(_ app: InstalledApplication) -> Bool {
        let fm = FileManager.default
        return fm.isDeletableFile(atPath: app.url.path)
            && fm.isWritableFile(atPath: app.url.path)
            && fm.isWritableFile(atPath: app.url.deletingLastPathComponent().path)
    }
    static func lastUsed(_ url: URL) -> Date? {
        guard let metadata = MDItemCreate(kCFAllocatorDefault, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(metadata, kMDItemLastUsedDate) as? Date
    }
    static func isRare(lastUsed: Date?, days: Int, now: Date = Date()) -> Bool {
        guard let lastUsed else { return false }
        return lastUsed < now.addingTimeInterval(-Double(days) * 86400)
    }
    static func scan(roots: [URL], ownBundleID: String?, progress: @Sendable (String) -> Void = { _ in }) throws -> ApplicationScan {
        var result = ApplicationScan()
        var seen: Set<String> = []
        for requested in roots {
            let root = Scanner.canonical(requested)
            if !FileManager.default.fileExists(atPath: root.path) { continue }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(Scanner.keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, _ in
                result.notes.append(L("s001" , url.lastPathComponent)); return true
            }) else { result.notes.append(L("s002" , root.path)); continue }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                guard url.pathExtension.lowercased() == "app" else { continue }
                do {
                    let v = try Scanner.values(url)
                    guard v.isDirectory == true, v.isSymbolicLink != true, Scanner.canonical(url).path == url.path else { continue }
                    guard seen.insert(url.path).inserted else { continue }
                    let bundle = Bundle(url: url)
                    if let ownBundleID, bundle?.bundleIdentifier == ownBundleID { continue }
                    let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
                    progress(name)
                    let measured = try Scanner.measure(url)
                    let entry = Entry(url: url, size: measured.size, stamp: measured.stamp, directory: true)
                    result.apps.append(InstalledApplication(url: url, name: name, bundleID: bundle?.bundleIdentifier, lastUsed: lastUsed(url), entry: entry, root: root))
                } catch is CancellationError { throw CancellationError() }
                  catch { result.notes.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        result.apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }
    static func validate(_ app: InstalledApplication, allowedRoots: [URL], runningPaths: Set<String>, ownBundleID: String?) throws -> URL {
        let u = URL(fileURLWithPath: app.url.path)
        guard u.pathExtension.lowercased() == "app", app.entry.directory,
              allowedRoots.map({ Scanner.canonical($0).path }).contains(app.root.path),
              Scanner.isInside(u, root: app.root), Scanner.canonical(u).path == u.path else {
            throw CleanerError(message: L("s003"))
        }
        guard !runningPaths.contains(u.path) else { throw CleanerError(message: L("s004")) }
        guard canMoveToTrash(app) else { throw CleanerError(message: L("s196")) }
        if let ownBundleID, Bundle(url: u)?.bundleIdentifier == ownBundleID {
            throw CleanerError(message: L("s005"))
        }
        let measured = try Scanner.measure(u)
        guard measured.stamp == app.entry.stamp else { throw CleanerError(message: L("s006")) }
        return u
    }
}
