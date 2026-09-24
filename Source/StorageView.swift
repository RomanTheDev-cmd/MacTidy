import SwiftUI
import AppKit

@MainActor final class StorageModel: ObservableObject {
    @Published var snapshot = StorageSnapshot()
    @Published var kind = StorageKind.photos
    @Published var selected: Set<String> = []
    @Published var search = ""
    @Published var busy = false
    @Published var cleaning = false
    @Published var hasScanned = false
    @Published var confirm = false
    @Published var error: String?
    @Published var status = ""
    @Published var free: Int64 = 0
    @Published var total: Int64 = 0
    var worker: Task<StorageSnapshot, Error>?
    var generation = UUID()
    var visible: [StorageFile] {
        snapshot.files.filter { $0.kind == kind && (search.isEmpty || $0.entry.url.lastPathComponent.localizedCaseInsensitiveContains(search)) }
    }
    var picked: [StorageFile] { snapshot.files.filter { selected.contains($0.id) && $0.kind == kind } }
    var pickedSize: Int64 { picked.reduce(0) { $0 + $1.entry.size } }
    var suggestedApps: [InstalledApplication] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL.map { Scanner.canonical($0).path } })
        return snapshot.apps.filter { !running.contains($0.id) && ApplicationScanner.isRare(lastUsed: $0.lastUsed, days: 90) }
            .sorted { $0.entry.size > $1.entry.size }
    }
    var scannedSize: Int64 { snapshot.totals.values.reduce(0, +) }
    var used: Int64 { max(0, total - free) }
    var protectedSize: Int64 { max(0, used - scannedSize) }
    init() { refreshDisk() }
    func refreshDisk() {
        if let a = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            free = (a[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            total = (a[.systemSize] as? NSNumber)?.int64Value ?? 0
        }
    }
    func size(_ kind: StorageKind) -> Int64 { snapshot.totals[kind] ?? 0 }
    func count(_ kind: StorageKind) -> Int { snapshot.counts[kind] ?? 0 }
    func choose(_ kind: StorageKind) { self.kind = kind; selected = []; search = "" }
    func cancel() { worker?.cancel(); worker = nil; generation = UUID(); busy = false }
    func scan() {
        guard !cleaning else { return }
        cancel()
        busy = true
        hasScanned = false
        selected = []
        snapshot = StorageSnapshot()
        error = nil
        status = L("s170")
        let token = UUID()
        generation = token
        let home = FileManager.default.homeDirectoryForCurrentUser
        let own = Bundle.main.bundleIdentifier
        let task: Task<StorageSnapshot, Error> = Task.detached(priority: .userInitiated) {
            try StorageScanner.scan(home: home, ownBundleID: own)
        }
        worker = task
        Task { await finish(task, token: token) }
    }
    private func finish(_ task: Task<StorageSnapshot, Error>, token: UUID) async {
        do {
            let result = try await task.value
            guard generation == token else { return }
            snapshot = result
            hasScanned = true
            kind = .documents
            status = L("s171", result.files.count + result.apps.count)
        } catch is CancellationError { }
          catch { if generation == token { self.error = error.localizedDescription } }
        if generation == token { busy = false; worker = nil; refreshDisk() }
    }
    func trash() {
        guard !busy, !cleaning, kind.reviewable, kind != .applications, !picked.isEmpty else { return }
        let files = picked; cleaning = true; error = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { StorageScanner.trash(files) }.value
            let removedFiles = snapshot.files.filter { result.removed.contains($0.id) }
            for file in removedFiles {
                snapshot.totals[file.kind, default: 0] -= file.entry.size
                snapshot.counts[file.kind, default: 0] -= 1
            }
            snapshot.files.removeAll { result.removed.contains($0.id) }
            selected.subtract(result.removed)
            cleaning = false; refreshDisk()
            status = L("s098", result.removed.count)
            if !result.failures.isEmpty { error = result.failures.prefix(10).joined(separator: "\n") }
        }
    }
}

struct StorageView: View {
    @StateObject private var m = StorageModel()
    @Environment(\.openWindow) private var openWindow
    private let shades: [Double] = [0.90, 0.77, 0.65, 0.55, 0.44, 0.34, 0.24, 0.18]

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("s164")).font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text(L("s165")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if m.busy { ProgressView().controlSize(.small); Button(L("s016")) { m.cancel() } }
                else { Button { m.scan() } label: { Image(systemName: "arrow.clockwise") }.help(L("s105")).disabled(m.cleaning) }
            }
            overview
            HStack(alignment: .top, spacing: 14) {
                categoryList.frame(width: 255)
                filePanel.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxHeight: .infinity)
            Text(L("s166")).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24).frame(minWidth: 850, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor)).tint(.primary)
        .task { if !m.hasScanned && !m.busy { m.scan() } }
        .onDisappear { m.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .init("MacTidyLanguageUpdated"))) { _ in m.objectWillChange.send() }
        .alert(L("s102"), isPresented: $m.confirm) {
            Button(L("s039"), role: .cancel) {}
            Button(L("s040"), role: .destructive) { m.trash() }
        } message: { Text(L("s103", m.selected.count, bytes(m.pickedSize), 0)) }
        .alert(L("s042"), isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
            Button(L("s043")) { m.error = nil }
        } message: { Text(m.error ?? "") }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(bytes(m.used)).font(.system(size: 31, weight: .semibold, design: .rounded))
                Text(L("s167", bytes(m.total))).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(L("s168", bytes(m.free))).font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(Array(StorageKind.allCases.enumerated()), id: \.element) { index, kind in
                        let width = CGFloat(Double(m.size(kind)) / Double(max(1, m.total))) * geometry.size.width
                        if width >= 2 { Rectangle().fill(Color.primary.opacity(shades[index])).frame(width: width) }
                    }
                    let protected = CGFloat(Double(m.protectedSize) / Double(max(1, m.total))) * geometry.size.width
                    if protected >= 2 { Rectangle().fill(Color.primary.opacity(0.10)).frame(width: protected) }
                    Spacer(minLength: 0)
                }
            }.frame(height: 12).clipShape(Capsule())
            Text(m.busy ? L("s170") + " " + m.status : (m.hasScanned ? L("s171", m.snapshot.files.count + m.snapshot.apps.count) : L("s170")))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).glassPanel(radius: 20)
    }

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 5) {
                ForEach(Array(StorageKind.allCases.enumerated()), id: \.element) { index, kind in
                    Button { m.choose(kind) } label: {
                        HStack(spacing: 11) {
                            Image(systemName: kind.symbol).frame(width: 20)
                                .foregroundStyle(Color.primary.opacity(shades[index]))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title).font(.subheadline.weight(.medium))
                                Text(m.hasScanned ? L("s172", m.count(kind)) : " ")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 2)
                            Text(m.hasScanned ? bytes(m.size(kind)) : "—")
                                .font(.caption.weight(.medium)).monospacedDigit()
                        }.padding(11).contentShape(Rectangle())
                            .background(m.kind == kind ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain)
                }
                Divider().padding(.vertical, 5)
                HStack(spacing: 11) {
                    Image(systemName: "lock.shield").frame(width: 20).foregroundStyle(.secondary)
                    Text(L("s169")).font(.caption)
                    Spacer()
                    Text(m.hasScanned ? bytes(m.protectedSize) : "—").font(.caption).monospacedDigit()
                }.foregroundStyle(.secondary).padding(11)
            }.padding(10)
        }.glassPanel(radius: 18)
    }

    private var filePanel: some View {
        Surface {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(m.kind.title).font(.headline)
                    Spacer()
                    if m.kind != .applications && m.kind != .other && m.hasScanned {
                        TextField(L("s119"), text: $m.search).textFieldStyle(.roundedBorder).frame(width: 200)
                    }
                }.padding(15)
                Divider()
                if m.kind == .applications {
                    VStack(spacing: 15) {
                        Image(systemName: "square.grid.2x2").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.secondary)
                        Text(L("s173", m.snapshot.apps.count, bytes(m.size(.applications))))
                            .font(.title3.weight(.medium)).multilineTextAlignment(.center)
                        Text(L("s174")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if !m.suggestedApps.isEmpty {
                            Text(L("s177")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            VStack(spacing: 8) {
                                ForEach(m.suggestedApps.prefix(3)) { app in
                                    HStack(spacing: 10) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 27, height: 27)
                                        Text(app.name).font(.callout).lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text(bytes(app.entry.size)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.padding(13).frame(maxWidth: 350).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                        Button(L("s017")) { openWindow(id: "applications") }.primaryControl()
                    }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if m.kind == .other {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.secondary)
                        Text(L("s175")).font(.title3.weight(.medium))
                        Text(L("s176")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if m.visible.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.secondary)
                        Text(m.busy ? L("s170") : L("s123")).font(.title3.weight(.medium))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(m.visible) { file in
                                HStack(spacing: 11) {
                                    Toggle(L("s044", file.entry.url.lastPathComponent), isOn: Binding(
                                        get: { m.selected.contains(file.id) },
                                        set: { if $0 { m.selected.insert(file.id) } else { m.selected.remove(file.id) } }
                                    )).labelsHidden().toggleStyle(.checkbox).disabled(m.cleaning)
                                    Image(systemName: m.kind.symbol).frame(width: 22).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.entry.url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                                        Text(displayPath(file.entry.url.deletingLastPathComponent())).font(.caption)
                                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer(minLength: 3)
                                    Text(bytes(file.entry.size)).font(.caption.weight(.semibold)).monospacedDigit()
                                }.padding(10)
                            }
                        }.padding(7)
                    }
                }
                if m.kind != .applications && m.kind != .other && m.hasScanned {
                    Divider()
                    HStack(spacing: 12) {
                        Text(m.selected.isEmpty ? L("s140") : L("s141", m.selected.count, bytes(m.pickedSize)))
                            .font(.caption.weight(.medium)).lineLimit(1)
                        Spacer()
                        Button(L("s121")) { m.selected.formUnion(m.visible.map(\.id)) }
                            .disabled(m.visible.isEmpty || m.cleaning)
                        if !m.selected.isEmpty { Button(L("s028")) { m.selected = [] }.disabled(m.cleaning) }
                        Button(L("s037"), systemImage: "trash") { m.confirm = true }
                            .primaryControl().disabled(m.selected.isEmpty || m.cleaning || m.busy)
                    }.padding(14)
                }
            }
        }
    }
}
