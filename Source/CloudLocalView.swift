import SwiftUI
import AppKit

@MainActor final class CloudLocalModel: ObservableObject {
    @Published var files: [CloudLocalFile] = []
    @Published var busy = false
    @Published var error: String?
    @Published var selected: CloudLocalFile?
    private var worker: Task<[CloudLocalFile], Error>?

    func load() {
        guard !busy else { return }
        busy = true
        let task = Task.detached(priority: .userInitiated) { try CloudLocal.scan() }
        worker = task
        Task {
            do { files = try await task.value }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
            busy = false
            worker = nil
        }
    }
    func stop() { worker?.cancel(); worker = nil }
    func evict(_ file: CloudLocalFile, storage: StorageModel) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try CloudLocal.evict(file) }.value
                files.removeAll { $0.id == file.id }
                storage.refreshDisk()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct CloudLocalView: View {
    @ObservedObject var storage: StorageModel
    @StateObject private var m = CloudLocalModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("s242")).font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text(L("s244")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help(L("s197")).accessibilityLabel(L("s197")).keyboardShortcut(.escape)
            }
            HStack {
                Text(L("s237", m.files.count, bytes(m.files.reduce(0) { $0 + $1.bytes })))
                    .font(.callout.weight(.semibold))
                Spacer()
                if m.busy { ProgressView().controlSize(.small) }
            }
            Surface {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(m.files) { file in
                            HStack(spacing: 10) {
                                Image(systemName: "icloud").frame(width: 22).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                                    Text(displayPath(file.url.deletingLastPathComponent()))
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 5)
                                Text(bytes(file.bytes)).font(.caption.weight(.semibold)).monospacedDigit()
                                Button { m.selected = file } label: { Image(systemName: "icloud.and.arrow.up") }
                                    .buttonStyle(.plain).help(L("s245")).accessibilityLabel(L("s245"))
                                    .disabled(m.busy)
                                Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: {
                                    Image(systemName: "arrow.up.right.square")
                                }.buttonStyle(.plain).help(L("s208")).accessibilityLabel(L("s208"))
                            }.padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        }
                        if m.files.isEmpty {
                            Text(m.busy ? L("s249") : L("s248"))
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }.padding(8)
                }
            }.frame(maxHeight: .infinity)
            Text(L("s243")).font(.caption).foregroundStyle(.secondary)
            if let error = m.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(23).frame(width: 760, height: 570)
        .background(Color(nsColor: .windowBackgroundColor)).tint(.primary)
        .task { m.load() }
        .onDisappear { m.stop() }
        .alert(m.selected.map { L("s246", $0.url.lastPathComponent) } ?? L("s242"),
               isPresented: Binding(get: { m.selected != nil }, set: { if !$0 { m.selected = nil } })) {
            Button(L("s039"), role: .cancel) { m.selected = nil }
            Button(L("s245")) {
                if let file = m.selected { m.evict(file, storage: storage) }
                m.selected = nil
            }
        } message: {
            Text(m.selected.map { L("s247", bytes($0.bytes)) } ?? L("s243"))
        }
    }
}
