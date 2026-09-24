import SwiftUI
import AppKit

@MainActor final class DiskCleanupModel: ObservableObject {
    @Published var opportunities: [DiskOpportunity] = []
    @Published var busy = false
    @Published var cleaning = false
    @Published var error: String?
    @Published var fileToTrash: StorageFile?
    @Published var appDataToTrash: DiskOpportunity?
    private var worker: Task<[DiskOpportunity], Error>?

    func load() {
        guard !busy else { return }
        busy = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let task = Task.detached(priority: .userInitiated) { try DiskAudit.opportunities(home: home) }
        worker = task
        Task {
            do { opportunities = try await task.value }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
            busy = false
            worker = nil
        }
    }
    func stop() { worker?.cancel(); worker = nil }

    func trashAppData(_ opportunity: DiskOpportunity, storage: StorageModel) {
        guard !cleaning else { return }
        cleaning = true
        error = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try DiskAudit.trashAppData(opportunity) }.value
                opportunities.removeAll { $0.id == opportunity.id }
                storage.refreshDisk()
            } catch { self.error = error.localizedDescription }
            cleaning = false
        }
    }
}

private enum CleanupItem: Identifiable {
    case file(StorageFile), appData(DiskOpportunity)
    var id: String {
        switch self { case .file(let file): return file.id; case .appData(let data): return data.id }
    }
    var size: Int64 {
        switch self { case .file(let file): return file.entry.size; case .appData(let data): return data.bytes }
    }
}

struct DiskAuditView: View {
    @ObservedObject var storage: StorageModel
    @StateObject private var m = DiskCleanupModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    private var items: [CleanupItem] {
        let files = storage.hasScanned ? storage.snapshot.files.filter { $0.kind.reviewable && $0.entry.size >= 100_000_000 }.map(CleanupItem.file) : []
        let appData = m.opportunities.filter { $0.stamp != nil }.map(CleanupItem.appData)
        return (files + appData).sorted { $0.size > $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("s222")).font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text(L("s236")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help(L("s197")).accessibilityLabel(L("s197")).keyboardShortcut(.escape)
            }
            HStack {
                Text(L("s237", items.count, bytes(items.reduce(0) { $0 + $1.size })))
                    .font(.callout.weight(.semibold))
                Spacer()
                if m.busy || storage.busy { ProgressView().controlSize(.small) }
            }
            Surface {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { item in
                            switch item {
                            case .file(let file): personalRow(file)
                            case .appData(let data): appDataRow(data)
                            }
                        }
                        if items.isEmpty {
                            Text(m.busy || storage.busy ? L("s170") : L("s238"))
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }.padding(8)
                }
            }.frame(maxHeight: .infinity)
            if !storage.suggestedApps.isEmpty {
                HStack {
                    Label(L("s239"), systemImage: "square.grid.2x2").font(.callout)
                    Spacer()
                    Button(L("s017")) { openWindow(id: "applications"); dismiss() }
                }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
            Text(L("s240")).font(.caption).foregroundStyle(.secondary)
            if let error = m.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(23).frame(width: 760, height: 610)
        .background(Color(nsColor: .windowBackgroundColor)).tint(.primary)
        .task { m.load() }
        .onDisappear { m.stop() }
        .alert(m.appDataToTrash == nil ? L("s232") : L("s234"), isPresented: Binding(get: { m.fileToTrash != nil || m.appDataToTrash != nil }, set: {
            if !$0 { m.fileToTrash = nil; m.appDataToTrash = nil }
        })) {
            Button(L("s039"), role: .cancel) { m.fileToTrash = nil; m.appDataToTrash = nil }
            Button(L("s040"), role: .destructive) {
                if let file = m.fileToTrash { storage.trash(files: [file]); dismiss() }
                if let data = m.appDataToTrash { m.trashAppData(data, storage: storage) }
                m.fileToTrash = nil; m.appDataToTrash = nil
            }
        } message: {
            Text(m.appDataToTrash.map { data in
                data.kind == .sharedAppData
                    ? L("s241", data.url.lastPathComponent, bytes(data.bytes))
                    : L("s235", data.url.lastPathComponent, bytes(data.bytes))
            } ?? L("s233"))
        }
    }

    private func personalRow(_ file: StorageFile) -> some View {
        row(name: file.entry.url.lastPathComponent, path: file.entry.url.deletingLastPathComponent(),
            size: file.entry.size, symbol: file.kind.symbol, onTrash: { m.fileToTrash = file },
            reveal: file.entry.url)
    }

    private func appDataRow(_ data: DiskOpportunity) -> some View {
        row(name: data.url.lastPathComponent, path: data.url.deletingLastPathComponent(),
            size: data.bytes, symbol: "square.stack.3d.up", onTrash: { m.appDataToTrash = data },
            reveal: data.url)
    }

    private func row(name: String, path: URL, size: Int64, symbol: String,
                     onTrash: @escaping () -> Void, reveal: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.callout.weight(.medium)).lineLimit(1)
                Text(displayPath(path)).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 5)
            Text(bytes(size)).font(.caption.weight(.semibold)).monospacedDigit()
            Button(action: onTrash) { Image(systemName: "trash") }
                .buttonStyle(.plain).help(L("s226")).accessibilityLabel(L("s226"))
                .disabled(m.cleaning || storage.cleaning)
            Button { NSWorkspace.shared.activateFileViewerSelecting([reveal]) } label: {
                Image(systemName: "arrow.up.right.square")
            }.buttonStyle(.plain).help(L("s208")).accessibilityLabel(L("s208"))
        }.padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}
