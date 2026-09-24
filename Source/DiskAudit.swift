import Foundation
import Darwin

struct DiskAuditRow: Identifiable, Sendable {
    let url: URL
    let bytes: Int64?
    var id: String { url.path }
}

struct DiskAuditResult: Sendable {
    let root: URL
    let measuredBytes: Int64?
    let rows: [DiskAuditRow]
    let accessLimited: Bool
    let snapshotCount: Int
}

enum DiskOpportunityKind: Sendable { case userAppData, sharedAppData }
struct DiskOpportunity: Identifiable, Sendable {
    let url: URL
    let bytes: Int64
    let kind: DiskOpportunityKind
    let stamp: String?
    var id: String { url.path }
}

enum DiskAudit {
    static let dataRoot = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)

    static func parse(_ output: String, root: URL) -> (Int64?, [DiskAuditRow]) {
        let path = root.standardizedFileURL.path
        var measured: Int64?
        var rows: [DiskAuditRow] = []
        for line in output.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t"),
                  let blocks = Int64(line[..<tab]), blocks >= 0 else { continue }
            let item = String(line[line.index(after: tab)...])
            guard item == path || item.hasPrefix(path + "/") else { continue }
            let multiplied = blocks.multipliedReportingOverflow(by: 1024)
            let value = multiplied.overflow ? Int64.max : multiplied.partialValue
            if item == path { measured = value }
            else if !item.dropFirst(path.count + 1).contains("/") {
                rows.append(DiskAuditRow(url: URL(fileURLWithPath: item), bytes: value))
            }
        }
        return (measured, sort(rows))
    }

    private static func sort(_ rows: [DiskAuditRow]) -> [DiskAuditRow] {
        rows.sorted { a, b in
            if a.bytes == b.bytes { return a.url.path < b.url.path }
            if a.bytes == nil { return b.bytes == 0 }
            if b.bytes == nil { return a.bytes != 0 }
            return a.bytes! > b.bytes!
        }
    }

    private static func runDu(_ arguments: [String], timeout: TimeInterval) -> (String, Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ("", false) }
        let deadline = DispatchWorkItem {
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus == 0)
    }

    static func scan(root: URL, includeFiles: Bool = true) throws -> DiskAuditResult {
        let path = root.standardizedFileURL.path
        guard path == dataRoot.path || path.hasPrefix(dataRoot.path + "/") else {
            throw CocoaError(.fileReadNoPermission)
        }
        let (output, complete) = runDu((includeFiles ? ["-a"] : []) + ["-x", "-d", "1", "-k", path], timeout: 14)
        try Task.checkCancellation()
        let parsed = parse(output, root: root)
        if parsed.0 != nil && (complete || !parsed.1.isEmpty) {
            return DiskAuditResult(root: root, measuredBytes: parsed.0, rows: parsed.1,
                                   accessLimited: !complete, snapshotCount: path == dataRoot.path ? localSnapshotCount() : 0)
        }
        // A cloud or protected folder can stall the whole walk. Measure direct children
        // individually so one slow folder cannot hide every other result.
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var measured: [String: Int64] = Dictionary(uniqueKeysWithValues: parsed.1.compactMap { row in row.bytes.map { (row.id, $0) } })
        let candidates = Array(children.filter { measured[$0.path] == nil }.sorted { $0.path < $1.path }.prefix(48))
        let lock = NSLock()
        var next = 0
        DispatchQueue.concurrentPerform(iterations: min(6, candidates.count)) { _ in
            while true {
                lock.lock()
                guard next < candidates.count else { lock.unlock(); break }
                let index = next
                next += 1
                lock.unlock()
                let child = candidates[index]
                let (text, _) = runDu(["-x", "-s", "-k", child.path], timeout: 10)
                let size = parse(text, root: child).0
                if let size {
                    lock.lock(); measured[child.path] = size; lock.unlock()
                }
            }
        }
        try Task.checkCancellation()
        let rows = sort(children.map { DiskAuditRow(url: $0, bytes: measured[$0.path]) })
        return DiskAuditResult(root: root, measuredBytes: parsed.0, rows: rows,
                               accessLimited: true, snapshotCount: path == dataRoot.path ? localSnapshotCount() : 0)
    }

    static func opportunities(home: URL, library: URL = URL(fileURLWithPath: "/Library")) throws -> [DiskOpportunity] {
        let homeOnData = dataRoot.appendingPathComponent(home.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let userRoot = homeOnData.appendingPathComponent("Library/Application Support")
        let protectedLibraryNames: Set<String> = ["Apple", "AppStore", "Audio", "Caches", "ColorSync", "Developer", "Extensions", "Frameworks", "Keychains", "LaunchAgents", "LaunchDaemons", "Logs", "Preferences", "PrivilegedHelperTools", "Receipts", "Security", "System", "Updates"]
        let vendorRoots = ((try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? [])
            .filter { candidate in
                let name = candidate.lastPathComponent
                let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true &&
                    !name.hasPrefix(".") && !name.hasPrefix("com.apple.") && !protectedLibraryNames.contains(name) &&
                    FileManager.default.isWritableFile(atPath: candidate.path)
            }
        let roots: [(URL, DiskOpportunityKind)] = [(userRoot, .userAppData)] + vendorRoots.map { vendor in
            (dataRoot.appendingPathComponent(vendor.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), .sharedAppData)
        }
        let reserved: Set<String> = ["Application Support", "Audio", "Caches", "Developer", "Extensions", "Frameworks", "LaunchAgents", "LaunchDaemons", "Logs", "Preferences", "PrivilegedHelperTools", "Receipts", "System", "Updates"]
        var found: [DiskOpportunity] = []
        for (root, kind) in roots {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let result = try scan(root: root, includeFiles: false)
            for row in result.rows {
                guard let size = row.bytes, size >= 100_000_000,
                      !row.url.lastPathComponent.hasPrefix("."),
                      !row.url.lastPathComponent.hasPrefix("com.apple."),
                      row.url.lastPathComponent != "MacTidy",
                      !reserved.contains(row.url.lastPathComponent),
                      FileManager.default.isDeletableFile(atPath: row.url.path),
                      (try? row.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))?.isDirectory == true,
                      (try? row.url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else { continue }
                let displayURL = kind == .userAppData
                    ? home.appendingPathComponent("Library/Application Support").appendingPathComponent(row.url.lastPathComponent)
                    : library.appendingPathComponent(root.lastPathComponent).appendingPathComponent(row.url.lastPathComponent)
                let stamp = try? Scanner.stamp(Scanner.values(displayURL))
                found.append(DiskOpportunity(url: displayURL, bytes: size, kind: kind, stamp: stamp))
            }
        }
        return found.sorted { $0.bytes > $1.bytes }
    }

    static func trashAppData(_ opportunity: DiskOpportunity, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             library: URL = URL(fileURLWithPath: "/Library"),
                             move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        let item = URL(fileURLWithPath: opportunity.url.path)
        let userRoot = Scanner.canonical(home.appendingPathComponent("Library/Application Support"))
        let sharedBase = Scanner.canonical(library)
        let root = item.deletingLastPathComponent()
        let sharedVendor = root.deletingLastPathComponent().path == sharedBase.path &&
            !["Apple", "AppStore", "Audio", "Caches", "ColorSync", "Developer", "Extensions", "Frameworks", "Keychains", "LaunchAgents", "LaunchDaemons", "Logs", "Preferences", "PrivilegedHelperTools", "Receipts", "Security", "System", "Updates"].contains(root.lastPathComponent) &&
            !root.lastPathComponent.hasPrefix(".") && !root.lastPathComponent.hasPrefix("com.apple.") &&
            Scanner.canonical(root).path == root.path
        let name = item.lastPathComponent
        guard (opportunity.kind == .userAppData && root.path == userRoot.path) ||
              (opportunity.kind == .sharedAppData && sharedVendor),
              let stamp = opportunity.stamp,
              Scanner.canonical(item).path == item.path,
              !name.hasPrefix("."), !name.hasPrefix("com.apple."), name != "MacTidy",
              FileManager.default.isDeletableFile(atPath: item.path),
              FileManager.default.isWritableFile(atPath: root.path) else {
            throw CleanerError(message: L("s081"))
        }
        let values = try Scanner.values(item)
        guard values.isDirectory == true, values.isSymbolicLink != true,
              try Scanner.stamp(values) == stamp else {
            throw CleanerError(message: L("s084"))
        }
        _ = try Scanner.measure(item)
        try move(item)
    }

    private static func localSnapshotCount() -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return 0 }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
    }
}
