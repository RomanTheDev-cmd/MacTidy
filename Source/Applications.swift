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
            && fm.isWritableFile(atPath: app.url.deletingLastPathComponent().path)
    }
    static func isPermissionError(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain && [257, 513].contains(e.code) { return true }
        if e.domain == NSPOSIXErrorDomain && [1, 13].contains(e.code) { return true }
        if let underlying = e.userInfo[NSUnderlyingErrorKey] as? Error { return isPermissionError(underlying) }
        return false
    }

    struct AuthorizedMove: Sendable {
        let source: URL
        let destination: URL
        let identity: String
    }

    static func authorizedMoves(_ urls: [URL], trash: URL) throws -> [AuthorizedMove] {
        if !FileManager.default.fileExists(atPath: trash.path) {
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        let trashValues = try trash.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard trashValues.isDirectory == true, trashValues.isSymbolicLink != true else {
            throw CleanerError(message: L("s319"))
        }
        var reserved: Set<String> = []
        return try urls.map { url in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let device = attributes[.systemNumber] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { throw CleanerError(message: L("s006")) }
            var destination = trash.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) || reserved.contains(destination.path) {
                destination = trash.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " (MacSpace " + UUID().uuidString.prefix(8) + ").app")
            }
            reserved.insert(destination.path)
            return AuthorizedMove(source: url, destination: destination, identity: "\(device):\(inode)")
        }
    }

    static func performAuthorizedMoves(_ moves: [AuthorizedMove], elevated: Bool = true) throws -> Set<String> {
        guard !moves.isEmpty else { return [] }
        // AppleScript quotes every path before passing it to the shell. One macOS authorization
        // covers the whole selection; inode checks prevent moving a replacement app after review.
        let privilege = elevated ? " with administrator privileges" : ""
        let script = """
        on run argv
            set commandText to ""
            repeat with itemIndex from 1 to (count of argv) by 3
                set sourcePath to item itemIndex of argv
                set targetPath to item (itemIndex + 1) of argv
                set expectedID to item (itemIndex + 2) of argv
                set commandText to commandText & "if /usr/bin/stat -f '%d:%i' " & quoted form of sourcePath & " 2>/dev/null | /usr/bin/grep -Fxq " & quoted form of expectedID & "; then /bin/mv -n " & quoted form of sourcePath & " " & quoted form of targetPath & "; fi; "
            end repeat
            do shell script commandText\(privilege)
        end run
        """
        let process = Process()
        let diagnostics = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + moves.flatMap { [$0.source.path, $0.destination.path, $0.identity] }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = diagnostics
        try process.run()
        let diagnosticText = String(decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        if process.terminationStatus != 0 { NSLog("MacSpace authorized app move: %@", diagnosticText) }
        return Set(moves.filter {
            !FileManager.default.fileExists(atPath: $0.source.path) && FileManager.default.fileExists(atPath: $0.destination.path)
        }.map { $0.source.path })
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
                    guard v.isDirectory == true, v.isSymbolicLink != true, v.isUbiquitousItem != true, Scanner.canonical(url).path == url.path else { continue }
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
        guard try Scanner.values(u).isUbiquitousItem != true else { throw CleanerError(message: L("s196")) }
        if let ownBundleID, Bundle(url: u)?.bundleIdentifier == ownBundleID {
            throw CleanerError(message: L("s005"))
        }
        let measured = try Scanner.measure(u)
        guard measured.stamp == app.entry.stamp else { throw CleanerError(message: L("s006")) }
        return u
    }
}
