import SwiftUI
import AppKit

@MainActor final class ApplicationsModel: ObservableObject {
    @Published var apps: [InstalledApplication] = []
    @Published var selected: Set<String> = []
    @Published var focused: String?
    @Published var busy = false
    @Published var cleaning = false
    @Published var hasScanned = false
    @Published var days = 90
    @Published var includeUnknown = false
    @Published var search = ""
    @Published var status = L("s007")
    @Published var error: String?
    @Published var notes: [String] = []
    @Published var showNotes = false
    @Published var confirm = false
    @Published var running: Set<String> = []
    var worker: Task<ApplicationScan, Error>?
    var generation = UUID()
    var roots: [URL] { [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] }
    var visible: [InstalledApplication] {
        apps.filter { app in
            let matchesAge = days == 0 || ApplicationScanner.isRare(lastUsed: app.lastUsed, days: days) || (includeUnknown && app.lastUsed == nil)
            return matchesAge && (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            if a.lastUsed == b.lastUsed { return a.entry.size > b.entry.size }
            return (a.lastUsed ?? .distantFuture) < (b.lastUsed ?? .distantFuture)
        }
    }
    var picked: [InstalledApplication] { apps.filter { selected.contains($0.id) } }
    var pickedSize: Int64 { picked.reduce(0) { $0 + $1.entry.size } }
    var focusedApp: InstalledApplication? { apps.first { $0.id == focused } }
    var hiddenCount: Int { selected.subtracting(Set(visible.map(\.id))).count }
    func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL.map { Scanner.canonical($0).path } })
        selected.subtract(running)
    }
    func cancel() { worker?.cancel(); worker = nil; generation = UUID(); busy = false; status = L("s008") }
    func scan() {
        guard !cleaning else { return }; cancel(); busy = true; hasScanned = false; apps = []; selected = []; focused = nil; notes = []; error = nil
        refreshRunning(); status = L("s009")
        let token = UUID(); generation = token; let roots = roots; let bundle = Bundle.main.bundleIdentifier
        let task = Task.detached(priority: .userInitiated) { [self] in
            try ApplicationScanner.scan(roots: roots, ownBundleID: bundle) { name in
                Task { @MainActor [weak self] in
                    if self?.generation == token && self?.busy == true { self?.status = L("s010" , name) }
                }
            }
        }
        worker = task
        Task {
            do {
                let result = try await task.value; guard generation == token else { return }
                apps = result.apps; notes = result.notes; hasScanned = true
                status = L("s011" , apps.count, apps.filter { $0.lastUsed == nil }.count)
            } catch is CancellationError { }
              catch { if generation == token { self.error = error.localizedDescription } }
            if generation == token { busy = false; worker = nil; refreshRunning() }
        }
    }
    func trash() {
        guard !cleaning && !busy else { return }
        refreshRunning(); let items = picked; guard !items.isEmpty else { return }
        cleaning = true; error = nil
        let roots = roots; let own = Bundle.main.bundleIdentifier
        Task {
            var removed: Set<String> = []; var failures: [String] = []
            for app in items {
                status = L("s010" , app.name); refreshRunning(); let currentRunning = running
                do {
                    let url = try await Task.detached(priority: .userInitiated) {
                        try ApplicationScanner.validate(app, allowedRoots: roots, runningPaths: currentRunning, ownBundleID: own)
                    }.value
                    refreshRunning()
                    guard !running.contains(app.id) else { throw CleanerError(message: L("s012")) }
                    try await Task.detached(priority: .userInitiated) { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }.value
                    removed.insert(app.id)
                } catch { failures.append("\(app.name): \(error.localizedDescription)") }
            }
            apps.removeAll { removed.contains($0.id) }; selected.subtract(removed)
            if let focused, removed.contains(focused) { self.focused = nil }
            cleaning = false; status = L("s013" , removed.count)
            if !failures.isEmpty { error = failures.prefix(10).joined(separator: "\n") }
        }
    }
}
struct ApplicationsView: View {
    @StateObject private var m = ApplicationsModel()
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "square.grid.2x2").font(.system(size: 30, weight: .light)).frame(width: 48, height: 48).glassPanel(radius: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("s014")).font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(L("s015")).foregroundStyle(.secondary)
                }
                Spacer()
                if m.busy { ProgressView().controlSize(.small); Button(L("s016")) { m.cancel() }.controlSize(.large) }
                else { Button(L("s017"), systemImage: "magnifyingglass") { m.scan() }.controlSize(.large).primaryControl().disabled(m.cleaning) }
            }
            HStack(spacing: 16) {
                Picker(L("s018"), selection: $m.days) { Text(L("s019")).tag(30); Text(L("s020")).tag(90); Text(L("s021")).tag(180); Text(L("s022")).tag(0) }.frame(width: 275)
                Toggle(L("s023"), isOn: $m.includeUnknown).toggleStyle(.checkbox).help(L("s024"))
                Spacer()
                TextField(L("s025"), text: $m.search).textFieldStyle(.roundedBorder).frame(width: 220)
            }.padding(16).glassPanel(radius: 18)
            HStack(alignment: .top, spacing: 16) {
                Surface {
                    VStack(spacing: 0) {
                        HStack {
                            Text(L("s026" , m.visible.count)).font(.subheadline.weight(.semibold)); Spacer()
                            Button(L("s027")) { m.refreshRunning(); m.selected.formUnion(m.visible.filter { !m.running.contains($0.id) }.map(\.id)) }.disabled(m.visible.isEmpty || m.cleaning)
                            Button(L("s028")) { m.selected = [] }.disabled(m.selected.isEmpty || m.cleaning)
                        }.font(.caption).padding(14)
                        Divider()
                        if m.visible.isEmpty {
                            VStack(spacing: 14) {
                                if m.busy { ProgressView().controlSize(.large) }
                                else { Image(systemName: "square.grid.2x2").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.secondary) }
                                Text(m.busy ? L("s029") : (m.hasScanned ? L("s030") : L("s031"))).font(.title3.weight(.semibold))
                                Text(m.busy ? m.status : (m.hasScanned ? L("s032") : L("s033"))).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 3) { ForEach(m.visible) { app in appRow(app) } }.padding(6)
                            }
                        }
                        if m.showNotes && !m.notes.isEmpty {
                            Divider()
                            ScrollView { Text(m.notes.joined(separator: "\n")).font(.caption).textSelection(.enabled).padding(12) }.frame(height: 90)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                details.frame(width: 260)
            }.frame(maxHeight: .infinity)
            HStack {
                if m.cleaning { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("s034" , m.selected.count, bytes(m.pickedSize))).font(.headline)
                    Text(m.hiddenCount > 0 ? L("s035" , m.hiddenCount) : m.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if !m.notes.isEmpty { Button(L("s036" , m.notes.count)) { m.showNotes.toggle() }.font(.caption) }
                Button(L("s037"), systemImage: "trash") { m.confirm = true }.controlSize(.large).primaryControl().disabled(m.selected.isEmpty || m.busy || m.cleaning)
            }.padding(16).glassPanel(radius: 18)
        }.padding(24).padding(.top, 14).frame(minWidth: 1000, minHeight: 700).background(Color(nsColor: .windowBackgroundColor)).tint(.primary)
        .onReceive(NotificationCenter.default.publisher(for: .init("MacTidyLanguageUpdated"))) { _ in m.objectWillChange.send() }
        .onAppear { m.refreshRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in m.refreshRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in m.refreshRunning() }
        .alert(L("s038"), isPresented: $m.confirm) {
            Button(L("s039"), role: .cancel) {}
            Button(L("s040"), role: .destructive) { m.trash() }
        } message: {
            Text(L("s041" , m.selected.count, bytes(m.pickedSize), m.hiddenCount))
        }
        .alert(L("s042"), isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) { Button(L("s043")) { m.error = nil } } message: { Text(m.error ?? "") }
    }
    private func appRow(_ app: InstalledApplication) -> some View {
        HStack(spacing: 12) {
            Toggle(L("s044" , app.name), isOn: Binding(get: { m.selected.contains(app.id) }, set: { if $0 { m.selected.insert(app.id) } else { m.selected.remove(app.id) } })).labelsHidden().toggleStyle(.checkbox).disabled(m.running.contains(app.id) || m.cleaning)
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(app.lastUsed.map { L("s045") + $0.formatted(date: .abbreviated, time: .omitted) } ?? L("s046")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(bytes(app.entry.size)).font(.system(size: 12, weight: .semibold))
                if m.running.contains(app.id) { Text(L("s047")).font(.caption2).foregroundStyle(.secondary) }
            }
        }.padding(10).contentShape(Rectangle()).background(m.focused == app.id ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .onTapGesture { m.focused = app.id }
            .contextMenu { Button(L("s048")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } }
    }
    private var details: some View {
        Surface {
            VStack(alignment: .leading, spacing: 15) {
                if let app = m.focusedApp {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 64, height: 64)
                    Text(app.name).font(.title2.weight(.semibold))
                    Text(bytes(app.entry.size)).font(.title.weight(.medium)).monospacedDigit()
                    Text(app.lastUsed.map { L("s049") + $0.formatted(date: .long, time: .omitted) } ?? L("s050")).font(.callout).foregroundStyle(.secondary)
                    Text(displayPath(app.url)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button(L("s048"), systemImage: "arrow.up.right.square") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                    Divider()
                } else {
                    Label(L("s051"), systemImage: "info.circle").font(.headline)
                }
                Text(L("s052")).font(.callout).foregroundStyle(.secondary)
                Text(L("s053")).font(.caption).foregroundStyle(.secondary)
                Text(L("s054")).font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
