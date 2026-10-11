import Foundation

@main struct WeeklyMain {
    static func main() {
        // RunAtLoad makes a missed cleanup happen on the next login after shutdown.
        // Ignore ordinary login starts until the next scheduled occurrence is due.
        guard WeeklySchedule.enabled else { return }
        guard WeeklySchedule.isDue(nextRun: WeeklySchedule.nextRun) else { return }
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let report = WeeklyCleanup.run(root: downloads)
        do {
            try FileManager.default.createDirectory(at: WeeklySchedule.support, withIntermediateDirectories: true)
            try JSONEncoder().encode(report).write(to: WeeklySchedule.reportURL, options: .atomic)
            // Advance after recording the result. If the process stops midway,
            // remaining entries are retried at the next helper launch.
            try WeeklySchedule.markNextOccurrence()
        } catch { fputs(L("s150" , error.localizedDescription), stderr) }
        if !report.failures.isEmpty { exit(1) }
    }
}
