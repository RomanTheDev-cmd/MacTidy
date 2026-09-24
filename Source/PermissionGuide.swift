import SwiftUI
import AppKit

enum PermissionGuide {
    static func openFullDiskAccess() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}

struct PermissionGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Image(systemName: "lock.shield").font(.system(size: 29)).frame(width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("s213")).font(.title2.weight(.semibold))
                    Text(L("s214")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").frame(width: 20, height: 20) }
                    .buttonStyle(.plain).help(L("s197")).accessibilityLabel(L("s197"))
                    .keyboardShortcut(.escape)
            }
            Text(L("s215")).font(.callout)
            Text(L("s216")).font(.callout).foregroundStyle(.secondary)
            if WeeklySchedule.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("s219")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(L("s220")) {
                        NSWorkspace.shared.activateFileViewerSelecting([WeeklySchedule.installedHelper])
                    }.disabled(!FileManager.default.fileExists(atPath: WeeklySchedule.installedHelper.path))
                }
            }
            HStack {
                Button(L("s212")) { PermissionGuide.openFullDiskAccess() }.primaryControl()
                Spacer()
                Button(L("s217")) { close() }
            }
        }
        .padding(25).frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor)).tint(.primary)
    }

    private func close() {
        UserDefaults.standard.set(true, forKey: "permissionsGuideSeen-v2")
        dismiss()
    }
}
