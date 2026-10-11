import Foundation

struct WeeklyReport: Codable {
    let date: Date
    let moved: Int
    let failures: [String]
}
struct CleanupNextRun: Codable {
    let date: Date
}
enum CleanupCadence: String, CaseIterable, Identifiable, Codable {
    case daily, weekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: return L("s287")
        case .weekly: return L("s288")
        case .monthly: return L("s289")
        }
    }
    var calendarComponents: [String: Int] {
        switch self {
        case .daily: return ["Hour": 12, "Minute": 0]
        // launchd numbers Sunday as 0; Foundation uses 1 for Sunday below.
        case .weekly: return ["Weekday": 0, "Hour": 12, "Minute": 0]
        case .monthly: return ["Day": 1, "Hour": 12, "Minute": 0]
        }
    }
    func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.hour = 12; components.minute = 0; components.second = 0
        switch self {
        case .daily: break
        case .weekly: components.weekday = 1
        case .monthly: components.day = 1
        }
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime, direction: .forward)
    }
}
struct WeeklyCleanup {
    // Finder metadata: .localized keeps the localized folder name ("Загрузки").
    static let preservedNames: Set<String> = [".localized", ".DS_Store"]
    // Browsers keep unfinished downloads under these extensions.
    static let partialDownloadExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]
    // Leave items changed in the last few minutes; they may still be downloading.
    static let recentGrace: TimeInterval = 10 * 60

    static func shouldSkip(_ item: URL, now: Date) -> Bool {
        if preservedNames.contains(item.lastPathComponent) { return true }
        if partialDownloadExtensions.contains(item.pathExtension.lowercased()) { return true }
        let values = try? URL(fileURLWithPath: item.path).resourceValues(forKeys: [.contentModificationDateKey])
        if let modified = values?.contentModificationDate, now.timeIntervalSince(modified) < recentGrace { return true }
        return false
    }

    // Direct children only: move directories intact and never traverse symlinks.
    static func run(root requestedRoot: URL, now: Date = Date(), move: (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }) -> WeeklyReport {
        var moved = 0
        var failures: [String] = []
        do {
            let root = Scanner.canonical(requestedRoot)
            try Scanner.validateRoot(root)
            let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for item in children where !shouldSkip(item, now: now) {
                do {
                    guard Scanner.canonical(requestedRoot).path == root.path,
                          item.deletingLastPathComponent().path == root.path else {
                        throw CleanerError(message: L("s144"))
                    }
                    guard FileManager.default.isUbiquitousItem(at: item) == false else {
                        throw CleanerError(message: L("s250"))
                    }
                    try move(item)
                    moved += 1
                } catch { failures.append("\(item.lastPathComponent): \(error.localizedDescription)") }
            }
        } catch { failures.append(error.localizedDescription) }
        return WeeklyReport(date: Date(), moved: moved, failures: failures)
    }
}
struct WeeklySchedule {
    static let label = "local.mactidy.weekly-downloads"
    static var support: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacTidy", isDirectory: true) }
    static var agent: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var reportURL: URL { support.appendingPathComponent("weekly-report.json") }
    static var nextRunURL: URL { support.appendingPathComponent("downloads-cleanup-next-run.plist") }
    static let cadenceDefaultsKey = "downloadsCleanupCadence-v1"
    static var cadence: CleanupCadence {
        get { CleanupCadence(rawValue: UserDefaults.standard.string(forKey: cadenceDefaultsKey) ?? "weekly") ?? .weekly }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: cadenceDefaultsKey) }
    }
    static var nextRun: Date? { (try? Data(contentsOf: nextRunURL)).flatMap { try? PropertyListDecoder().decode(CleanupNextRun.self, from: $0).date } }
    static func isDue(nextRun: Date?, now: Date = Date()) -> Bool { nextRun.map { $0 <= now } ?? false }
    static var installedHelper: URL { support.appendingPathComponent("MacTidyHelper.app") }
    static var enabled: Bool { FileManager.default.fileExists(atPath: agent.path) }
    static var domain: String { "gui/\(getuid())" }
    static func launchctl(_ args: [String]) throws -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl"); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit(); return p.terminationStatus
    }
    static func disable() throws {
        let status = try launchctl(["bootout", domain + "/" + label])
        if try status != 0 && launchctl(["print", domain + "/" + label]) == 0 {
            throw CleanerError(message: L("s145"))
        }
        if enabled { try FileManager.default.removeItem(at: agent) }
        try? FileManager.default.removeItem(at: nextRunURL)
    }
    static func enable(helper: URL, cadence: CleanupCadence = WeeklySchedule.cadence, preserveNextRun: Bool = false) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: helper.appendingPathComponent("Contents/MacOS/MacTidyHelper").path) else {
            throw CleanerError(message: L("s146"))
        }
        let previousNextRun = preserveNextRun ? nextRun : nil
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try fm.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try disable()
        if fm.fileExists(atPath: installedHelper.path) { try fm.removeItem(at: installedHelper) }
        try fm.copyItem(at: helper, to: installedHelper)
        self.cadence = cadence
        if let next = previousNextRun ?? cadence.nextOccurrence(after: Date()) {
            try PropertyListEncoder().encode(CleanupNextRun(date: next)).write(to: nextRunURL, options: .atomic)
        }
        let plist = configuration(helper: installedHelper, cadence: cadence)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agent, options: .atomic)
        let code = try launchctl(["bootstrap", domain, agent.path])
        guard code == 0 else {
            try? fm.removeItem(at: agent)
            throw CleanerError(message: L("s147"))
        }
    }
    static func updateHelperIfNeeded(helper: URL) throws {
        guard enabled else { return }
        let bundledVersion = Bundle(url: helper)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let installedVersion = Bundle(url: installedHelper)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let bundledBuild = Bundle(url: helper)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let installedBuild = Bundle(url: installedHelper)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard bundledVersion != nil,
              bundledVersion != installedVersion || bundledBuild != installedBuild ||
              !FileManager.default.fileExists(atPath: installedHelper.appendingPathComponent("Contents/MacOS/MacTidyHelper").path) else { return }
        try enable(helper: helper, cadence: cadence, preserveNextRun: true)
    }
    static func configuration(helper: URL, cadence: CleanupCadence = WeeklySchedule.cadence) -> [String: Any] {
        return [
            "Label": label,
            "ProgramArguments": [helper.appendingPathComponent("Contents/MacOS/MacTidyHelper").path],
            "StartCalendarInterval": cadence.calendarComponents,
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Background",
            "StandardOutPath": support.appendingPathComponent("weekly.log").path,
            "StandardErrorPath": support.appendingPathComponent("weekly-error.log").path
        ]
    }
    static func markNextOccurrence(from date: Date = Date()) throws {
        guard let next = cadence.nextOccurrence(after: date) else { return }
        try PropertyListEncoder().encode(CleanupNextRun(date: next)).write(to: nextRunURL, options: .atomic)
    }
    static func lastResult() -> String {
        guard let data = try? Data(contentsOf: reportURL), let r = try? JSONDecoder().decode(WeeklyReport.self, from: data) else { return L("s148") }
        let f = DateFormatter(); f.locale = .current; f.dateStyle = .short; f.timeStyle = .short
        let summary = L("s149" , f.string(from: r.date), r.moved, r.failures.count)
        return summary
    }
}
