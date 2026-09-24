import SwiftUI
import AppKit

@MainActor final class DiskAuditModel: ObservableObject {
    @Published var current = DiskAudit.dataRoot
    @Published var result: DiskAuditResult?
    @Published var busy = false
    @Published var error: String?
    private var generation = UUID()
    private var worker: Task<DiskAuditResult, Error>?

    func open(_ url: URL) {
        let canonical = url.standardizedFileURL
        guard canonical.path == DiskAudit.dataRoot.path || canonical.path.hasPrefix(DiskAudit.dataRoot.path + "/") else { return }
        worker?.cancel()
        current = canonical
        result = nil
        busy = true
        error = nil
        let token = UUID()
        generation = token
        let task = Task.detached(priority: .userInitiated) { try DiskAudit.scan(root: canonical) }
        worker = task
        Task { await finish(task, token: token) }
    }
    private func finish(_ task: Task<DiskAuditResult, Error>, token: UUID) async {
        do {
            let scan = try await task.value
            if generation == token { result = scan }
        } catch is CancellationError { }
          catch { if generation == token { self.error = error.localizedDescription } }
        if generation == token { busy = false; worker = nil }
    }
    func stop() { generation = UUID(); worker?.cancel(); worker = nil; busy = false }
}

struct DiskAuditView: View {
    @StateObject private var m = DiskAuditModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    let diskUsed: Int64
    let unclassified: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("s198")).font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text(L("s199")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help(L("s197")).accessibilityLabel(L("s197")).keyboardShortcut(.escape)
            }
            HStack(spacing: 12) {
                figure(L("s200"), bytes(diskUsed))
                if let unclassified { figure(L("s201"), bytes(unclassified)) }
                if let result = m.result, result.root == DiskAudit.dataRoot, let measuredBytes = result.measuredBytes {
                    figure(L("s202"), bytes(measuredBytes))
                }
            }
            Text(L("s203")).font(.caption).foregroundStyle(.secondary)
            if let result = m.result, result.root == DiskAudit.dataRoot, result.snapshotCount > 0 {
                Label(L("s204", result.snapshotCount), systemImage: "clock.arrow.circlepath")
                    .font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 8) {
                if m.current != DiskAudit.dataRoot {
                    Button { m.open(m.current.deletingLastPathComponent()) } label: {
                        Label(L("s189"), systemImage: "chevron.left")
                    }
                }
                Text(m.current == DiskAudit.dataRoot ? L("s205") : displayPath(m.current))
                    .font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                if m.busy { ProgressView().controlSize(.small) }
                Button { m.open(m.current) } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("s105")).disabled(m.busy)
            }
            Surface {
                Group {
                    if m.busy && m.result == nil { ProgressView(L("s206")).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else if let result = m.result {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(result.rows) { row in
                                    HStack(spacing: 11) {
                                        Image(systemName: rowIsDirectory(row) ? "folder" : "doc").frame(width: 22).foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                                            Text(row.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer(minLength: 5)
                                        Text(row.bytes.map(bytes) ?? L("s221")).font(.callout.weight(.medium)).foregroundStyle(row.bytes == nil ? .secondary : .primary).monospacedDigit()
                                        if rowIsDirectory(row) {
                                            Button { m.open(row.url) } label: { Image(systemName: "chevron.right") }
                                                .buttonStyle(.plain).help(L("s207", row.url.lastPathComponent))
                                        }
                                        Button { NSWorkspace.shared.activateFileViewerSelecting([row.url]) } label: {
                                            Image(systemName: "arrow.up.right.square")
                                        }.buttonStyle(.plain).help(L("s208")).accessibilityLabel(L("s208"))
                                    }
                                    .padding(.horizontal, 13).padding(.vertical, 9)
                                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                                }
                            }.padding(8)
                        }
                    } else if let error = m.error {
                        Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            if m.result?.accessLimited == true {
                Label(L("s209"), systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(L("s210")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("s211")) { openWindow(id: "storage"); dismiss() }
                Button(L("s212")) { PermissionGuide.openFullDiskAccess() }
            }
        }
        .padding(23).frame(width: 760, height: 650)
        .background(Color(nsColor: .windowBackgroundColor)).tint(.primary)
        .task { if m.result == nil && !m.busy { m.open(DiskAudit.dataRoot) } }
        .onDisappear { m.stop() }
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
    private func rowIsDirectory(_ row: DiskAuditRow) -> Bool {
        (try? row.url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
