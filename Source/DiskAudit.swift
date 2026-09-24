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

    static func scan(root: URL) throws -> DiskAuditResult {
        let path = root.standardizedFileURL.path
        guard path == dataRoot.path || path.hasPrefix(dataRoot.path + "/") else {
            throw CocoaError(.fileReadNoPermission)
        }
        let (output, complete) = runDu(["-a", "-x", "-d", "1", "-k", path], timeout: 14)
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
