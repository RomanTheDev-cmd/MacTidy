import Foundation

struct WeeklyReport: Codable {
    let date: Date
    let moved: Int
    let failures: [String]
}
struct WeeklyCleanup {
    // Direct children only: move directories intact and never traverse symlinks.
    static func run(root requestedRoot: URL, move: (URL) throws -> Void = {
        try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }) -> WeeklyReport {
        var moved = 0
        var failures: [String] = []
        do {
            let root = Scanner.canonical(requestedRoot)
            try Scanner.validateRoot(root)
            let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for item in children {
                do {
                    guard Scanner.canonical(requestedRoot).path == root.path,
                          item.deletingLastPathComponent().path == root.path else {
                        throw CleanerError(message: L("s144"))
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
    }
    static func enable(helper: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: helper.appendingPathComponent("Contents/MacOS/MacTidyHelper").path) else {
            throw CleanerError(message: L("s146"))
        }
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try fm.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try disable()
        if fm.fileExists(atPath: installedHelper.path) { try fm.removeItem(at: installedHelper) }
        try fm.copyItem(at: helper, to: installedHelper)
        let plist = configuration(helper: installedHelper)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agent, options: .atomic)
        let code = try launchctl(["bootstrap", domain, agent.path])
        guard code == 0 else {
            try? fm.removeItem(at: agent)
            throw CleanerError(message: L("s147" , code))
        }
    }
    static func configuration(helper: URL) -> [String: Any] {
        return [
            "Label": label,
            "ProgramArguments": [helper.appendingPathComponent("Contents/MacOS/MacTidyHelper").path],
            "StartCalendarInterval": ["Weekday": 0, "Hour": 12, "Minute": 0],
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Background",
            "StandardOutPath": support.appendingPathComponent("weekly.log").path,
            "StandardErrorPath": support.appendingPathComponent("weekly-error.log").path
        ]
    }
    static func lastResult() -> String {
        guard let data = try? Data(contentsOf: reportURL), let r = try? JSONDecoder().decode(WeeklyReport.self, from: data) else { return L("s148") }
        let f = DateFormatter(); f.locale = .current; f.dateStyle = .short; f.timeStyle = .short
        let summary = L("s149" , f.string(from: r.date), r.moved, r.failures.count)
        return r.failures.isEmpty ? summary : summary + " " + r.failures.prefix(2).joined(separator: " ")
    }
}
