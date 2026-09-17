import Foundation

@main struct WeeklyMain {
    static func main() {
        // A stale/manual helper launch must do nothing when the option is disabled.
        guard WeeklySchedule.enabled else { return }
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let report = WeeklyCleanup.run(root: downloads)
        do {
            try FileManager.default.createDirectory(at: WeeklySchedule.support, withIntermediateDirectories: true)
            try JSONEncoder().encode(report).write(to: WeeklySchedule.reportURL, options: .atomic)
        } catch { fputs(L("s150" , error.localizedDescription), stderr) }
        if !report.failures.isEmpty { exit(1) }
    }
}
