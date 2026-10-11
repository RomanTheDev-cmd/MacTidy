import Foundation
import Combine

struct AntivirusFinding: Identifiable, Hashable {
    var id: String { path + "\u{0}" + signature }
    let path: String
    let signature: String
    let stamp: String?
    let removable: Bool
}

struct AntivirusScanResult {
    let findings: [AntivirusFinding]
    let completed: Bool
    let cancelled: Bool
    let scannedFiles: Int
    let estimatedFiles: Int
    var skippedLocations = 0

    // clamscan exits with 2 when some locations could not be opened, which is routine for a
    // whole-disk scan without root. Only a run that scanned nothing is treated as a failure.
    static func isCompleted(status: Int32, scannedFiles: Int) -> Bool {
        status == 0 || status == 1 || (status == 2 && scannedFiles > 0)
    }
}

struct AntivirusScanProgress {
    enum Phase: Equatable { case counting, scanning }
    let phase: Phase
    let countedFiles: Int
    let scannedFiles: Int
    let estimatedFiles: Int
    let foundThreats: Int

    static func estimatedSecondsRemaining(scanned: Int, total: Int, elapsed: TimeInterval) -> TimeInterval? {
        guard scanned >= 50, total > scanned, elapsed >= 10 else { return nil }
        let estimate = elapsed * Double(total - scanned) / Double(scanned)
        return estimate.isFinite && estimate < 7 * 24 * 3600 ? estimate : nil
    }
}

struct AntivirusHistoryFinding: Codable, Hashable {
    let path: String
    let signature: String
}

struct AntivirusScanRecord: Codable, Identifiable {
    enum Outcome: String, Codable { case finished, stopped, partial, failed }
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let scannedFiles: Int
    let outcome: Outcome
    let findings: [AntivirusHistoryFinding]
}

enum AntivirusScanLine {
    static func parse(_ line: String) -> (path: String, signature: String?)? {
        guard let separator = line.range(of: ": ", options: .backwards) else { return nil }
        let path = String(line[..<separator.lowerBound])
        let result = String(line[separator.upperBound...])
        guard path.hasPrefix("/") else { return nil }
        if result == "OK" || result.hasSuffix(" ERROR") { return (path, nil) }
        if result.hasSuffix(" FOUND") { return (path, String(result.dropLast(" FOUND".count))) }
        return nil
    }

    static func isSkippedLocation(_ line: String) -> Bool {
        guard line.hasPrefix("/"), let separator = line.range(of: ": ", options: .backwards) else { return false }
        let result = line[separator.upperBound...]
        return result == "Can't open directory." || result.hasSuffix(" ERROR")
    }
}

final class AntivirusScanControl {
    private let lock = NSLock()
    private var stopped = false
    private var process: Process?

    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    func attach(_ process: Process) {
        lock.lock(); self.process = process; let shouldStop = stopped; lock.unlock()
        if shouldStop && process.isRunning { process.terminate() }
    }

    func stop() {
        lock.lock(); stopped = true; let current = process; lock.unlock()
        if let current, current.isRunning { current.terminate() }
    }
}

enum AntivirusError: LocalizedError {
    case engineMissing
    case command(String)
    case definitionsMissing
    case protectedFile

    var errorDescription: String? {
        switch self {
        case .engineMissing: return L("s278")
        case .command: return L("s280")
        case .definitionsMissing: return L("s279")
        case .protectedFile: return L("s290")
        }
    }
}

enum AntivirusEngine {
    // The ClamAV engine is included in the MacSpace application bundle.
    static let release = "1.5.4"
    private static let scanLock = NSLock()
    private static var activeScan: AntivirusScanControl?
    static var engine: URL { Bundle.main.resourceURL!.appendingPathComponent("ClamAV", isDirectory: true) }

    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacTidy/Antivirus", isDirectory: true)
    }
    static var database: URL { support.appendingPathComponent("Database", isDirectory: true) }
    static var config: URL { support.appendingPathComponent("freshclam.conf") }
    static var certificates: URL { engine.appendingPathComponent("etc/certs", isDirectory: true) }
    static var scanner: URL { engine.appendingPathComponent("bin/clamscan") }
    static var updater: URL { engine.appendingPathComponent("bin/freshclam") }
    static var historyURL: URL { support.appendingPathComponent("scan-history.json") }

    static func loadHistory() -> [AntivirusScanRecord] {
        guard let data = try? Data(contentsOf: historyURL),
              let records = try? JSONDecoder().decode([AntivirusScanRecord].self, from: data) else { return [] }
        return Array(records.prefix(20))
    }

    static func saveHistory(_ records: [AntivirusScanRecord]) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(records.prefix(20))).write(to: historyURL, options: .atomic)
    }

    static func cancelActiveScan() {
        scanLock.lock(); let scan = activeScan; scanLock.unlock()
        scan?.stop()
    }

    static func updateDefinitions() throws -> String {
        guard FileManager.default.isExecutableFile(atPath: scanner.path),
              FileManager.default.isExecutableFile(atPath: updater.path) else { throw AntivirusError.engineMissing }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        let configText = "DatabaseDirectory \(database.path)\nDatabaseMirror database.clamav.net\nCVDCertsDirectory \(certificates.path)\n"
        try configText.write(to: config, atomically: true, encoding: .utf8)
        let result = try run(updater, ["--config-file=\(config.path)", "--cvdcertsdir=\(certificates.path)", "--stdout"])
        guard result.status == 0 else { throw AntivirusError.command(result.output.isEmpty ? "ClamAV could not update its virus definitions." : result.output) }
        guard hasDefinitions else { throw AntivirusError.definitionsMissing }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasDefinitions: Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(at: database, includingPropertiesForKeys: nil) else { return false }
        return hasCompleteDefinitions(files)
    }

    static func hasCompleteDefinitions(_ files: [URL]) -> Bool {
        let present = Set(files.filter { ["cvd", "cld"].contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent.lowercased() })
        return ["main", "daily", "bytecode"].allSatisfy { present.contains($0) }
    }

    static func scanComputer(onProgress: @escaping (AntivirusScanProgress) -> Void,
                             onFinding: @escaping (AntivirusFinding) -> Void) throws -> AntivirusScanResult {
        guard FileManager.default.isExecutableFile(atPath: scanner.path) else { throw AntivirusError.engineMissing }
        guard hasDefinitions else { throw AntivirusError.definitionsMissing }
        let control = AntivirusScanControl()
        scanLock.lock(); activeScan = control; scanLock.unlock()
        defer {
            scanLock.lock(); if activeScan === control { activeScan = nil }; scanLock.unlock()
        }
        let targets = scanTargets
        let estimatedFiles = countScannableFiles(targets: targets, control: control, onProgress: onProgress)
        if control.isStopped {
            return AntivirusScanResult(findings: [], completed: false, cancelled: true, scannedFiles: 0, estimatedFiles: estimatedFiles)
        }
        var scannedFiles = 0
        var skippedLocations = 0
        var completed = true
        var findings: [AntivirusFinding] = []
        var lastReport = Date.distantPast
        func handle(_ line: String) {
            if AntivirusScanLine.isSkippedLocation(line) { skippedLocations += 1 }
            guard let parsed = AntivirusScanLine.parse(line) else { return }
            scannedFiles += 1
            if let signature = parsed.signature {
                let url = URL(fileURLWithPath: parsed.path)
                if !isCloudPath(url) {
                    let values = try? Scanner.values(url)
                    let stamp = values.flatMap { try? Scanner.stamp($0) }
                    let finding = AntivirusFinding(path: parsed.path, signature: signature, stamp: stamp,
                                                   removable: isRemovableCandidate(url, values: values) && stamp != nil)
                    findings.append(finding)
                    onFinding(finding)
                }
            }
            if Date().timeIntervalSince(lastReport) >= 0.5 || scannedFiles == 1 {
                lastReport = Date()
                onProgress(AntivirusScanProgress(phase: .scanning, countedFiles: estimatedFiles,
                                                scannedFiles: scannedFiles, estimatedFiles: estimatedFiles,
                                                foundThreats: findings.count))
            }
        }
        // The startup disk and each connected external drive are scanned by separate clamscan runs,
        // because the startup disk run must skip /Volumes while a drive run starts inside it.
        for target in targets {
            if control.isStopped { break }
            let process = Process()
            let pipe = Pipe()
            process.executableURL = scanner
            process.arguments = ["--recursive", "--no-summary", "--stdout", "--database=\(database.path)"]
                + scanExclusions(target.excluded) + [target.root.path]
            process.environment = ProcessInfo.processInfo.environment.merging(["CVD_CERTS_DIR": certificates.path]) { _, new in new }
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch {
                if target.root.path == "/" { throw AntivirusError.command(error.localizedDescription) }
                completed = false; continue
            }
            control.attach(process)
            let scannedBefore = scannedFiles
            var pending = Data()
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    handle(line)
                }
            }
            if !pending.isEmpty { handle(String(decoding: pending, as: UTF8.self)) }
            process.waitUntilExit()
            if !AntivirusScanResult.isCompleted(status: process.terminationStatus, scannedFiles: scannedFiles - scannedBefore) {
                completed = false
            }
        }
        onProgress(AntivirusScanProgress(phase: .scanning, countedFiles: estimatedFiles,
                                        scannedFiles: scannedFiles, estimatedFiles: estimatedFiles,
                                        foundThreats: findings.count))
        return AntivirusScanResult(findings: findings, completed: completed && !control.isStopped,
                                   cancelled: control.isStopped, scannedFiles: scannedFiles, estimatedFiles: estimatedFiles,
                                   skippedLocations: skippedLocations)
    }

    private static func countScannableFiles(targets: [(root: URL, excluded: [String])], control: AntivirusScanControl,
                                            onProgress: (AntivirusScanProgress) -> Void) -> Int {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var count = 0
        var lastReport = Date.distantPast
        for target in targets {
            guard let enumerator = FileManager.default.enumerator(at: target.root, includingPropertiesForKeys: keys,
                                                                   errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                if control.isStopped { break }
                let path = url.standardizedFileURL.path
                if target.excluded.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                    enumerator.skipDescendants(); continue
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true { count += 1 }
                if Date().timeIntervalSince(lastReport) >= 0.5 {
                    lastReport = Date()
                    onProgress(AntivirusScanProgress(phase: .counting, countedFiles: count,
                                                    scannedFiles: 0, estimatedFiles: 0, foundThreats: 0))
                }
            }
        }
        onProgress(AntivirusScanProgress(phase: .counting, countedFiles: count,
                                        scannedFiles: 0, estimatedFiles: 0, foundThreats: 0))
        return count
    }

    private static var scanTargets: [(root: URL, excluded: [String])] {
        [(URL(fileURLWithPath: "/", isDirectory: true), scanExcludedPaths)] + externalDrives().map { ($0, []) }
    }

    /// Connected flash drives and external disks. Network shares and Time Machine backup disks are left out:
    /// they are slow to read and can hold many copies of the same files.
    static func externalDrives(fileManager: FileManager = .default) -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey, .volumeIsBrowsableKey]
        let volumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { url in
            guard url.standardizedFileURL.path.hasPrefix("/Volumes/"),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true, values.volumeIsBrowsable != false else { return false }
            return !isTimeMachineDrive(url, fileManager: fileManager)
        }
    }

    static func isTimeMachineDrive(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let names = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        return names.contains { $0 == "Backups.backupdb" || $0.hasSuffix(".backup") || $0.hasSuffix(".previous") || $0.hasSuffix(".inprogress") }
    }

    static func moveToTrash(_ finding: AntivirusFinding) throws {
        let url = URL(fileURLWithPath: finding.path)
        guard finding.removable, let stamp = finding.stamp,
              isRemovableCandidate(url, values: try? Scanner.values(url)) else { throw AntivirusError.protectedFile }
        let entry = Entry(url: url, size: 0, stamp: stamp, directory: false)
        let validated = try Cleaner.validate(entry, root: URL(fileURLWithPath: "/"), mode: .large, cacheRoot: URL(fileURLWithPath: "/Library/Caches"))
        try FileManager.default.trashItem(at: validated, resultingItemURL: nil)
    }

    private static var cloudRoots: [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return [library.appendingPathComponent("Mobile Documents", isDirectory: true),
                library.appendingPathComponent("CloudStorage", isDirectory: true)]
    }
    private static func isCloudPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let roots = cloudRoots.map(\.path) + cloudRoots.map { "/System/Volumes/Data" + $0.path }
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
    private static func regexEscaped(_ value: String) -> String {
        let meta = CharacterSet(charactersIn: "\\.^$|?*+()[]{}")
        return value.unicodeScalars.map { meta.contains($0) ? "\\" + String($0) : String($0) }.joined()
    }
    private static var scanExcludedPaths: [String] {
        cloudRoots.map(\.path) + ["/System/Volumes/Data", "/Volumes", "/dev", database.path,
                                  Bundle.main.bundleURL.standardizedFileURL.path]
    }
    private static func scanExclusions(_ paths: [String]) -> [String] {
        guard !paths.isEmpty else { return [] }
        let pattern = "^(" + paths.map { regexEscaped($0) }.joined(separator: "|") + ")(/|$)"
        return ["--exclude-dir=\(pattern)"]
    }
    private static func isRemovableCandidate(_ url: URL, values: URLResourceValues?) -> Bool {
        let path = url.standardizedFileURL.path
        let resolvedPath = Scanner.canonical(url).path
        let protectedPrefixes = ["/System/", "/System/Volumes/Data/System/", "/usr/", "/System/Volumes/Data/usr/",
                                 "/bin/", "/System/Volumes/Data/bin/", "/sbin/", "/System/Volumes/Data/sbin/",
                                 "/private/etc/", "/System/Volumes/Data/private/etc/", "/private/var/db/", "/System/Volumes/Data/private/var/db/",
                                 Bundle.main.bundleURL.standardizedFileURL.path + "/"]
        guard path.hasPrefix("/"), !isCloudPath(url), !isCloudPath(URL(fileURLWithPath: resolvedPath)),
              !protectedPrefixes.contains(where: { path.hasPrefix($0) || resolvedPath.hasPrefix($0) }),
              values?.isRegularFile == true, values?.isSymbolicLink != true, values?.isUbiquitousItem != true else { return false }
        return true
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["CVD_CERTS_DIR": certificates.path]) { _, new in new }
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw AntivirusError.command(error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

@MainActor final class AntivirusModel: ObservableObject {
    // FreshClam applies small database patches after its first download. Keep
    // checking while the app is open without polling Talos on every UI refresh.
    private static let updateInterval: UInt64 = 2 * 60 * 60 * 1_000_000_000
    private static let scanRetryInterval: UInt64 = 5 * 60 * 1_000_000_000
    @Published var updating = false
    @Published var scanning = false
    @Published var ready = false
    @Published var status = L("s257")
    @Published var lastUpdated: Date?
    @Published var findings: [AntivirusFinding] = []
    @Published var history = AntivirusEngine.loadHistory()
    @Published var historyExpanded = false
    @Published var scanPhase: AntivirusScanProgress.Phase = .counting
    @Published var countedFiles = 0
    @Published var scannedFiles = 0
    @Published var estimatedFiles = 0
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var stopping = false
    @Published var pendingRemoval: AntivirusFinding?
    @Published var error: String?
    private var scanID: UUID?
    private var elapsedTask: Task<Void, Never>?

    init() {
        ready = FileManager.default.isExecutableFile(atPath: AntivirusEngine.scanner.path) && AntivirusEngine.hasDefinitions
        if let files = try? FileManager.default.contentsOfDirectory(at: AntivirusEngine.database, includingPropertiesForKeys: [.contentModificationDateKey]),
           let date = files.compactMap({ try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }).max() {
            lastUpdated = date
        }
    }

    func maintainDefinitions() async {
        while !Task.isCancelled {
            if !scanning { await updateDefinitions() }
            do {
                try await Task.sleep(nanoseconds: scanning ? Self.scanRetryInterval : Self.updateInterval)
            } catch { return }
        }
    }

    func updateDefinitions() async {
        guard !updating else { return }
        updating = true
        error = nil
        status = L("s257")
        do {
            _ = try await Task.detached(priority: .utility) {
                try AntivirusEngine.updateDefinitions()
            }.value
            ready = true
            lastUpdated = Date()
            status = L("s258")
        } catch {
            ready = AntivirusEngine.hasDefinitions
            self.error = error.localizedDescription
            status = ready ? L("s259") : L("s260")
        }
        updating = false
    }

    func scan() {
        guard ready, !updating, !scanning else { return }
        let id = UUID()
        let startedAt = Date()
        scanID = id
        scanning = true
        stopping = false
        scanPhase = .counting
        countedFiles = 0
        scannedFiles = 0
        estimatedFiles = 0
        elapsedSeconds = 0
        findings = []
        error = nil
        status = L("s261")
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.scanID == id, self.scanning else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startedAt)
            }
        }
        Task { [self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) { [weak self] in
                    try AntivirusEngine.scanComputer(onProgress: { progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.scanID == id else { return }
                            self.scanPhase = progress.phase
                            self.countedFiles = progress.countedFiles
                            self.scannedFiles = max(self.scannedFiles, progress.scannedFiles)
                            self.estimatedFiles = progress.estimatedFiles
                        }
                    }, onFinding: { finding in
                        Task { @MainActor [weak self] in
                            guard let self, self.scanID == id else { return }
                            self.findings.append(finding)
                        }
                    })
                }.value
                guard scanID == id else { return }
                findings = result.findings
                scannedFiles = result.scannedFiles
                estimatedFiles = result.estimatedFiles
                let outcome: AntivirusScanRecord.Outcome
                if result.cancelled {
                    outcome = .stopped
                    status = L("s300")
                } else if result.completed {
                    outcome = .finished
                    status = result.findings.isEmpty ? L("s262") : L("s263", result.findings.count)
                    if result.skippedLocations > 0 { status += " " + L("s311", result.skippedLocations) }
                } else {
                    outcome = .partial
                    error = L("s270")
                    status = L("s264")
                }
                saveRecord(startedAt: startedAt, scanned: result.scannedFiles, findings: result.findings, outcome: outcome)
            } catch {
                guard scanID == id else { return }
                self.error = error.localizedDescription
                status = L("s264")
                saveRecord(startedAt: startedAt, scanned: scannedFiles, findings: findings, outcome: .failed)
            }
            elapsedTask?.cancel()
            elapsedSeconds = Date().timeIntervalSince(startedAt)
            scanID = nil
            stopping = false
            scanning = false
        }
    }

    func stopScan() {
        guard scanning, !stopping else { return }
        stopping = true
        status = L("s299")
        AntivirusEngine.cancelActiveScan()
    }

    private func saveRecord(startedAt: Date, scanned: Int, findings: [AntivirusFinding],
                            outcome: AntivirusScanRecord.Outcome) {
        let record = AntivirusScanRecord(id: UUID(), startedAt: startedAt, finishedAt: Date(),
                                         scannedFiles: scanned, outcome: outcome,
                                         findings: findings.map { AntivirusHistoryFinding(path: $0.path, signature: $0.signature) })
        history.insert(record, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        do { try AntivirusEngine.saveHistory(history) }
        catch { self.error = L("s308") }
    }

    func requestRemoval(_ finding: AntivirusFinding) {
        guard finding.removable, !scanning, !updating else { return }
        pendingRemoval = finding
    }

    func confirmRemoval() {
        guard let finding = pendingRemoval, finding.removable else { pendingRemoval = nil; return }
        pendingRemoval = nil
        error = nil
        Task {
            do {
                try await Task.detached(priority: .utility) { try AntivirusEngine.moveToTrash(finding) }.value
                findings.removeAll { $0.id == finding.id }
                status = L("s284")
            } catch {
                self.error = L("s285", error.localizedDescription)
            }
        }
    }
}
